//
//  MaintenanceManager.swift
//  vpncore - Created on 20/08/2020.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of LegacyCommon.
//
//  vpncore is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  vpncore is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with LegacyCommon.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

public protocol MaintenanceManagerFactory {
    func makeMaintenanceManager() -> MaintenanceManagerProtocol
}

public typealias BoolCallback = GenericCallback<Bool>

public protocol MaintenanceManagerProtocol {
    func observeCurrentServerState(every timeInterval: TimeInterval, repeats: Bool, completion: BoolCallback?, failure: ErrorCallback?)
    func stopObserving()
}

public class MaintenanceManager: MaintenanceManagerProtocol {
    
    public typealias Factory = VpnApiServiceFactory & AppStateManagerFactory & VpnGatewayFactory & CoreAlertServiceFactory & ServerStorageFactory & VpnKeychainFactory
    
    private let factory: Factory
    
    private lazy var vpnApiService: VpnApiService = self.factory.makeVpnApiService()
    private lazy var appStateManager: AppStateManager = self.factory.makeAppStateManager()
    private lazy var vpnGateWay: VpnGatewayProtocol = self.factory.makeVpnGateway()
    private lazy var vpnKeychain: VpnKeychainProtocol = self.factory.makeVpnKeychain()
    private lazy var alertService: CoreAlertService = self.factory.makeCoreAlertService()
    private lazy var serverStorage: ServerStorage = self.factory.makeServerStorage()
    
    private var timer: Timer?
    
    public init( factory: Factory) {
        self.factory = factory
    }
    
    // MARK: - MaintenanceManagerProtocol
    
    public func observeCurrentServerState(every timeInterval: TimeInterval, repeats: Bool, completion: BoolCallback?, failure: ErrorCallback?) {
        if !repeats || timeInterval <= 0 {
            self.checkServer(completion, failure: failure)
            return
        }
        
        if timer != nil {
            guard timer?.timeInterval != timeInterval else {
                return // Only restart timer if time interval has changed
            }
            timer?.invalidate()
            timer = nil
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { timer in
            self.checkServer(completion, failure: failure)
        }
    }
    
    public func stopObserving() {
        if timer != nil {
            timer?.invalidate()
        }
        timer = nil
    }
    
    private func checkServer(_ completion: BoolCallback?, failure: ErrorCallback?) {
        guard let activeConnection = appStateManager.activeConnection() else {
            log.info("No active connection", category: .app)
            completion?(false)
            return
        }
        
        switch appStateManager.state {
        case .connected, .connecting:
            break
        default:
            log.info("VPN Not connected", category: .app)
            completion?(false)
            return
        }
        
        let serverID = activeConnection.serverIp.id

        // This doesn't need to be a strict check, it's just to reduce load on the API
        let isFree = (try? vpnKeychain.fetchCached().isFreeTier) ?? false

        vpnApiService.serverState(serverId: serverID) { result in
            switch result {
            case let .success(vpnServerState):
                guard vpnServerState.status != 1 else {
                    completion?(false)
                    return
                }

                self.vpnApiService.serverInfo(
                    ip: nil,
                    freeTier: isFree
                ) { result in
                    switch result {
                    case let .success(servers):
                        self.serverStorage.store(servers)
                        completion?(true)
                    case let .failure(error):
                        failure?(error)
                    }
                }
            case let .failure(error):
                failure?(error)
            }
        }
    }
}
