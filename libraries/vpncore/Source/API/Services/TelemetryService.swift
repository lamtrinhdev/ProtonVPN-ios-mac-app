//
//  Created on 13/12/2022.
//
//  Copyright (c) 2022 Proton AG
//
//  ProtonVPN is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ProtonVPN is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ProtonVPN.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import LocalFeatureFlags
import Reachability

public enum UserInitiatedVPNChange {
    case connect
    case disconnect(TelemetryDimensions.VPNTrigger)
    case abort
}

public extension Notification.Name {
    static let userInitiatedVPNChange = Notification.Name("UserInitiatedVPNChange")
}

public protocol TelemetryServiceFactory {
    func makeTelemetryService() async -> TelemetryService
}

protocol TelemetryTimer {
    func updateConnectionStarted(_ date: Date)
    func markStartedConnecting()
    func markFinishedConnecting()
    func markConnectionStoped()
    var connectionDuration: TimeInterval? { get }
    var timeToConnect: TimeInterval? { get }
    var timeConnecting: TimeInterval? { get }
}

public protocol TelemetryService: AnyObject {
    func vpnGatewayConnectionChanged(_ connectionStatus: ConnectionStatus)
    func userInitiatedVPNChange(_ change: UserInitiatedVPNChange)
    func reachabilityChanged(_ networkType: TelemetryDimensions.NetworkType)
}

public class TelemetryServiceImplementation: TelemetryService {

    public typealias Factory = NetworkingFactory & AppStateManagerFactory & PropertiesManagerFactory & VpnKeychainFactory & TelemetryAPIFactory

    private let factory: Factory

    private lazy var networking: Networking = factory.makeNetworking()
    private lazy var appStateManager: AppStateManager = factory.makeAppStateManager()
    private lazy var propertiesManager: PropertiesManagerProtocol = factory.makePropertiesManager()
    private lazy var vpnKeychain: VpnKeychainProtocol = factory.makeVpnKeychain()
    private lazy var telemetryAPI: TelemetryAPI = factory.makeTelemetryAPI(networking: networking)

    private var networkType: TelemetryDimensions.NetworkType = .other
    private var previousConnectionStatus: ConnectionStatus?
    private lazy var previousConnectionConfiguration: ConnectionConfiguration? = {
        appStateManager.activeConnection()
    }()
    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()
    private var userInitiatedVPNChange: UserInitiatedVPNChange?

    private let connectionNotifier: TelemetryConnectionNotifier
    private let timer: TelemetryTimer
    private let buffer = TelemetryBuffer()

    init(factory: Factory, timer: TelemetryTimer, connectionNotifier: TelemetryConnectionNotifier = .init()) async {
        self.factory = factory
        self.timer = timer
        self.connectionNotifier = connectionNotifier
        self.connectionNotifier.telemetryService = self
        await timer.updateConnectionStarted(appStateManager.connectedDate())
    }

    public func reachabilityChanged(_ networkType: TelemetryDimensions.NetworkType) {
        self.networkType = networkType
    }

    public func userInitiatedVPNChange(_ change: UserInitiatedVPNChange) {
        self.userInitiatedVPNChange = change
    }

    public func vpnGatewayConnectionChanged(_ connectionStatus: ConnectionStatus) {
        // Assume the first status is generated by the system upon app launch
        guard previousConnectionStatus != nil else {
            previousConnectionStatus = connectionStatus
            return
        }
        defer {
            if [.connected, .disconnected, .connecting].contains(connectionStatus) {
                previousConnectionStatus = connectionStatus
            }
        }
        var eventType: ConnectionEventType?
        switch connectionStatus {
        case .connected:
            timer.markFinishedConnecting()
            eventType = connectionEventType(state: connectionStatus)
        case .connecting:
            timer.markConnectionStoped()
            eventType = connectionEventType(state: connectionStatus)
            timer.markStartedConnecting()
        case .disconnected:
            timer.markConnectionStoped()
            eventType = connectionEventType(state: connectionStatus)
        case .disconnecting:
            return
        }
        collectDimensionsAndReport(outcome: connectionOutcome(connectionStatus), eventType: eventType)
    }

    private func connectionOutcome(_ state: ConnectionStatus) -> TelemetryDimensions.Outcome {
        switch state {
        case .disconnected:
            if [.connected, .connecting].contains(previousConnectionStatus) {
                guard let userInitiatedVPNChange else { return .failure }
                switch userInitiatedVPNChange {
                case .connect:
                    return .failure
                case .disconnect:
                    return .success
                case .abort:
                    return .aborted
                }
            }
            return .success
        case .connected:
            return .success
        case .connecting:
            if previousConnectionStatus == .connected {
                return .success
            }
            return .failure
        case .disconnecting:
            return .failure
        }
    }

    private func vpnTrigger(eventType: ConnectionEventType) -> TelemetryDimensions.VPNTrigger? {
        guard let userInitiatedVPNChange else {
            return nil
        }
        switch userInitiatedVPNChange {
        case .connect:
            if case .vpnDisconnection = eventType {
                return .newConnection
            } else {
                return propertiesManager.lastConnectionRequest?.trigger
            }
        case .disconnect(let trigger):
            return trigger
        case .abort:
            return nil
        }
    }

    private func connection(eventType: ConnectionEventType) -> ConnectionConfiguration? {
        switch eventType {
        case .vpnConnection:
            return appStateManager.activeConnection()
        case .vpnDisconnection:
            return previousConnectionConfiguration
        }
    }

    private func collectDimensionsAndReport(outcome: TelemetryDimensions.Outcome, eventType: ConnectionEventType?) {
        guard let eventType,
              let connection = connection(eventType: eventType),
              let port = connection.ports.first else {
            return
        }
        let dimensions = TelemetryDimensions(outcome: outcome,
                                             userTier: userTier(),
                                             vpnStatus: previousConnectionStatus == .connected ? .on : .off,
                                             vpnTrigger: vpnTrigger(eventType: eventType),
                                             networkType: networkType,
                                             serverFeatures: connection.server.feature,
                                             vpnCountry: connection.server.countryCode,
                                             userCountry: propertiesManager.userLocation?.country ?? "",
                                             protocol: connection.vpnProtocol,
                                             server: connection.server.name,
                                             port: String(port),
                                             isp: propertiesManager.userLocation?.isp ?? "",
                                             isServerFree: connection.server.isFree)

        previousConnectionConfiguration = appStateManager.activeConnection()
        report(event: ConnectionEvent(event: eventType, dimensions: dimensions))
    }

    private func userTier() -> TelemetryDimensions.UserTier {
        let cached = try? vpnKeychain.fetchCached()
        let accountPlan = cached?.accountPlan ?? .free
        if cached?.maxTier == 3 {
            return .internal
        } else {
            return [.free, .trial].contains(accountPlan) ? .free : .paid
        }
    }

    private func connectionEventType(state: ConnectionStatus) -> ConnectionEventType? {
        switch state {
        case .connected:
            guard let timeInterval = timer.timeToConnect else { return nil }
            return .vpnConnection(timeToConnection: timeInterval)
        case .disconnected:
            if previousConnectionStatus == .connected {
                return .vpnDisconnection(sessionLength: timer.connectionDuration ?? 0)
            } else if previousConnectionStatus == .connecting {
                return .vpnConnection(timeToConnection: timer.timeConnecting ?? 0)
            }
            return nil
        case .connecting:
            if previousConnectionStatus == .connected {
                return .vpnDisconnection(sessionLength: timer.connectionDuration ?? 0)
            }
            return nil
        default:
            return nil
        }
    }

    private func report(event: TelemetryEvent) {
        guard isEnabled(TelemetryFeature.telemetryOptIn) else { return }
        Task {
            await sendEvent(event)
        }
    }

    private func sendEvent(_ event: TelemetryEvent) async {
        guard isEnabled(TelemetryFeature.useBuffer) else {
            try? await telemetryAPI.flushEvent(event: event.toJSONDictionary())
            return
        }
        guard await buffer.events.isEmpty else {
            await scheduleEvent(event)
            await sendScheduledEvents()
            return
        }
        do {
            try await telemetryAPI.flushEvent(event: event.toJSONDictionary())
        } catch {
            log.warning("Failed to send telemetry event, saving to storage: \(event)", category: .telemetry)
            await scheduleEvent(event)
        }
    }

    private func scheduleEvent(_ event: TelemetryEvent) async {
        do {
            let data = try encoder.encode(event)
            await buffer.save(event: .init(data))
            log.debug("Telemetry event scheduled:\n\(String(data: data, encoding: .utf8)!)")
        } catch {
            log.warning("Failed to serialize telemetry event: \(event)", category: .telemetry)
        }
    }

    var taskHandle: Task<(), Never>?

    private func sendScheduledEvents() async {
        guard taskHandle == nil else {
            log.debug("Sending events already in progress", category: .telemetry)
            return
        }
        taskHandle = Task {
            while let bufferedEvent = await buffer.oldestEvent() {
                do {
                    guard let event = try JSONSerialization.jsonObject(with: bufferedEvent.data) as? JSONDictionary else {
                        log.warning("Couldn't serialize stored event", category: .telemetry)
                        return
                    }
                    try await telemetryAPI.flushEvent(event: event)
                    await buffer.remove(event: bufferedEvent)
                } catch {
                    log.warning("Failed to send scheduled telemetry events: \(error)", category: .telemetry)
                    break
                }
            }
            taskHandle = nil
        }
    }
}
