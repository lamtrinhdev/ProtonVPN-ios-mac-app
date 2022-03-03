//
//  AppSessionManager.swift
//  ProtonVPN - Created on 01.07.19.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of ProtonVPN.
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
//

import vpncore
import UIKit
import Foundation
import TunnelKit

enum SessionStatus {
    
    case notEstablished
    case established
}

protocol AppSessionManagerFactory {
    func makeAppSessionManager() -> AppSessionManager
}

protocol AppSessionManager {
    var vpnGateway: VpnGatewayProtocol? { get }
    var sessionStatus: SessionStatus { get set }
    var loggedIn: Bool { get }
    
    var sessionChanged: Notification.Name { get }
    var dataReloaded: Notification.Name { get }

    func attemptSilentLogIn(completion: @escaping (Result<(), Error>) -> Void)
    func refreshVpnAuthCertificate(success: @escaping () -> Void, failure: @escaping (Error) -> Void)
    func finishLogin(authCredentials: AuthCredentials, completion: @escaping (Result<(), Error>) -> Void)
    func logOut(force: Bool)
    
    func loadDataWithoutFetching() -> Bool
    func loadDataWithoutLogin(success: @escaping () -> Void, failure: @escaping (Error) -> Void)
    func canPreviewApp() -> Bool
}

class AppSessionManagerImplementation: AppSessionRefresherImplementation, AppSessionManager {
    
    typealias Factory = VpnApiServiceFactory & AppStateManagerFactory & VpnKeychainFactory & PropertiesManagerFactory & ServerStorageFactory & VpnGatewayFactory & CoreAlertServiceFactory & NavigationServiceFactory & NetworkingFactory & AppSessionRefreshTimerFactory & AnnouncementRefresherFactory & VpnAuthenticationFactory & PlanServiceFactory & ProfileManagerFactory & NATTypePropertyProviderFactory & SafeModePropertyProviderFactory
    private let factory: Factory
    
    internal lazy var appStateManager: AppStateManager = factory.makeAppStateManager()
    private var navService: NavigationService? {
        return factory.makeNavigationService()
    }

    private lazy var networking: Networking = factory.makeNetworking()
    private lazy var refreshTimer: AppSessionRefreshTimer = factory.makeAppSessionRefreshTimer()
    private lazy var announcementRefresher: AnnouncementRefresher = factory.makeAnnouncementRefresher()
    private lazy var vpnAuthentication: VpnAuthentication = factory.makeVpnAuthentication()
    private lazy var planService: PlanService = factory.makePlanService()
    private lazy var profileManager: ProfileManager = factory.makeProfileManager()
    private lazy var natTypePropertyProvider: NATTypePropertyProvider = factory.makeNATTypePropertyProvider()
    private lazy var safeModePropertyProvider: SafeModePropertyProvider = factory.makeSafeModePropertyProvider()
    var vpnGateway: VpnGatewayProtocol?

    let sessionChanged = Notification.Name("AppSessionManagerSessionChanged")
    let sessionRefreshed = Notification.Name("AppSessionManagerSessionRefreshed")
    let dataReloaded = Notification.Name("AppSessionManagerDataReloaded")
        
    var sessionStatus: SessionStatus = .notEstablished
    
    init(factory: Factory) {
        self.factory = factory
        super.init(factory: factory)

        planService.delegate = self
    }
    
    // MARK: - Beginning of the login logic.
    override func attemptSilentLogIn(completion: @escaping (Result<(), Error>) -> Void) {
        guard AuthKeychain.fetch() != nil else {
            completion(.failure(ProtonVpnErrorConst.userCredentialsMissing))
            return
        }

        retrievePropertiesAndLogIn(success: { completion(.success) }, failure: { error in
            DispatchQueue.main.async { completion(.failure(error)) }
        })
    }

    func finishLogin(authCredentials: AuthCredentials, completion: @escaping (Result<(), Error>) -> Void) {
        do {
            try AuthKeychain.store(authCredentials)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(ProtonVpnError.keychainWriteFailed))
            }
            return
        }
       
        retrievePropertiesAndLogIn(success: { [weak self] in
            self?.checkForSubuserWithoutSessions(completion: completion)
        }, failure: { error in
            log.error("Failed to obtain user's auth credentials", category: .user, metadata: ["error": "\(error)"])
            completion(.failure(error))
        })
    }
    
    func loadDataWithoutFetching() -> Bool {
        guard !self.serverStorage.fetch().isEmpty,
              self.propertiesManager.userIp != nil else {
            return false
        }
        
        // swiftlint:disable unused_optional_binding
        if let _ = try? vpnKeychain.fetchCached() {
            setAndNotify(for: .established)
        } else {
            setAndNotify(for: .notEstablished)
        }
        // swiftlint:enable unused_optional_binding
        
        return true
    }
    
    func canPreviewApp() -> Bool {
        guard !self.serverStorage.fetch().isEmpty, self.propertiesManager.userIp != nil else {
            return false
        }
        return true
    }
    
    func loadDataWithoutLogin(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        vpnApiService.vpnProperties(isDisconnected: appStateManager.state.isDisconnected,
                                    lastKnownIp: propertiesManager.userIp) { [weak self] result in
            guard let self = self else {
                return
            }

            switch result {
            case let .success(properties):
                if let credentials = properties.vpnCredentials {
                    self.vpnKeychain.store(vpnCredentials: credentials)
                }
                self.propertiesManager.streamingServices = properties.streamingResponse?.streamingServices ?? [:]
                self.propertiesManager.streamingResourcesUrl = properties.streamingResponse?.resourceBaseURL
                self.serverStorage.store(properties.serverModels)
                self.propertiesManager.userIp = properties.ip

                self.resolveActiveSession(success: {
                    self.refreshVpnAuthCertificate(success: success, failure: failure)
                }, failure: { error in
                    self.logOutCleanup()
                    failure(error)
                })
            case let .failure(error):
                log.error("Failed to obtain user's VPN properties", category: .app, metadata: ["error": "\(error)"])
                guard !self.serverStorage.fetch().isEmpty, // only fail if there is a major reason
                    self.propertiesManager.userIp != nil,
                      !(error is vpncore.KeychainError) else {
                        failure(error)
                        return
                }

                self.refreshVpnAuthCertificate(success: success, failure: failure)
            }
        }
    }

    func refreshVpnAuthCertificate(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        guard loggedIn else {
            success()
            return
        }

        self.vpnAuthentication.refreshCertificates { result in
            switch result {
            case .success:
                success()
            case let .failure(error):
                failure(error)
            }
        }
    }

    // swiftlint:disable function_body_length
    private func retrievePropertiesAndLogIn(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        let group = DispatchGroup()

        var vpnPropertiesError: Error?
        group.enter()
        vpnApiService.vpnProperties(isDisconnected: appStateManager.state.isDisconnected,
                                    lastKnownIp: propertiesManager.userIp) { [weak self] result in
            let fail = { (error: Error) in
                vpnPropertiesError = error
                group.leave()
            }
            let ok = {
                group.leave()
            }

            guard let self = self else {
                ok()
                return
            }

            switch result {
            case let .success(properties):
                if let credentials = properties.vpnCredentials {
                    self.vpnKeychain.store(vpnCredentials: credentials)
                }
                self.serverStorage.store(properties.serverModels)
                self.propertiesManager.streamingServices = properties.streamingResponse?.streamingServices ?? [:]
                self.propertiesManager.streamingResourcesUrl = properties.streamingResponse?.resourceBaseURL
                self.propertiesManager.userIp = properties.ip
                self.propertiesManager.openVpnConfig = properties.clientConfig.openVPNConfig
                self.propertiesManager.wireguardConfig = properties.clientConfig.wireGuardConfig
                self.propertiesManager.smartProtocolConfig = properties.clientConfig.smartProtocolConfig
                self.propertiesManager.maintenanceServerRefreshIntereval = properties.clientConfig.serverRefreshInterval
                self.propertiesManager.featureFlags = properties.clientConfig.featureFlags
                if self.propertiesManager.featureFlags.pollNotificationAPI {
                    self.announcementRefresher.refresh()
                }

                self.resolveActiveSession(success: { [weak self] in
                    self?.setAndNotify(for: .established)
                    self?.profileManager.refreshProfiles()
                    self?.refreshVpnAuthCertificate(success: ok, failure: fail)
                }, failure: { error in
                    fail(error)
                    self.logOutCleanup()
                })
            case let .failure(error):
                log.error("Failed to obtain user's VPN properties", category: .app, metadata: ["error": "\(error)"])
                guard !self.serverStorage.fetch().isEmpty, // only fail if there is a major reason
                      self.propertiesManager.userIp != nil,
                      !(error is vpncore.KeychainError) else {
                          fail(error)
                          return
                }

                self.setAndNotify(for: .established)
                self.profileManager.refreshProfiles()
                self.refreshVpnAuthCertificate(success: ok, failure: fail)
            }
        }

        var plansError: Error?
        group.enter()
        planService.updateServicePlans { result in
            switch result {
            case .success:
                break
            case let .failure(error):
                plansError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let error = vpnPropertiesError ?? plansError {
                failure(error)
                return
            }

            success()
        }
    }
    // swiftlint:enable function_body_length
    
    private func resolveActiveSession(success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        let refreshNotification = Notification(name: sessionRefreshed, object: nil)
        DispatchQueue.main.async { NotificationCenter.default.post(refreshNotification) }
        
        guard appStateManager.state.isConnected else {
            success()
            return
        }
        
        guard let activeUsername = appStateManager.state.descriptor?.username, let vpnCredentials = try? vpnKeychain.fetch() else {
            failure(ProtonVpnError.fetchSession)
            return
        }
        
        if activeUsername.removeSubstring(startingWithCharacter: VpnManagerConfiguration.configConcatChar)
            == vpnCredentials.name.removeSubstring(startingWithCharacter: VpnManagerConfiguration.configConcatChar) {
            success()
            return
        }
    }
    
    private func checkForSubuserWithoutSessions(completion: @escaping (Result<(), Error>) -> Void) {
        guard let credentials = try? self.vpnKeychain.fetchCached() else {
            completion(.success)
            return
        }
        guard credentials.isSubuserWithoutSessions else {
            completion(.success)
            return
        }
        
        log.error("User with insufficient sessions detected. Throwing and error insted of login.", category: .app)
        logOutCleanup()
        completion(.failure(ProtonVpnError.subuserWithoutSessions))
    }
    
    // MARK: - Log out
    func logOut(force: Bool = false) {
        let logOutRoutine: () -> Void = { [weak self] in
            self?.loggedIn = false
            self?.logOutCleanup()
            self?.setAndNotify(for: .notEstablished)
        }
        
        if appStateManager.state.isSafeToEnd {
            logOutRoutine()
            return
        }
        
        let confirmationClosure: () -> Void = { [weak self] in
            guard let `self` = self else { return }
            if self.appStateManager.state.isConnected {
                self.appStateManager.disconnect { logOutRoutine() }
                return
            }
            logOutRoutine()
        }
        
        if force {
            confirmationClosure()
        } else {
            alertService.push(alert: LogoutWarningAlert(confirmHandler: confirmationClosure))
        }
    }
    
    private func logOutCleanup() {
        refreshTimer.stop()
        loggedIn = false
        
        AuthKeychain.clear()
        vpnKeychain.clear()
        vpnAuthentication.clearEverything()
        announcementRefresher.clear()
        planService.clear()
        
        propertiesManager.logoutCleanup()
        safeModePropertyProvider.logoutCleanup()
        natTypePropertyProvider.logoutCleanup()
    }
    // End of the logout logic
    // MARK: -
    
    // Updates the status of the app, including refreshing the VpnGateway object if the VPN creds change
    private func setAndNotify(for state: SessionStatus) {
        guard !loggedIn else { return }
        
        sessionStatus = state
        
        var object: VpnGatewayProtocol?
        if state == .established {
            loggedIn = true
            object = factory.makeVpnGateway()            
            propertiesManager.hasConnected = true
        } else if state == .notEstablished {
            // Clear auth token and vpn creds to ensure they won't be used
            logOutCleanup()
        }
        vpnGateway = object
        
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            NotificationCenter.default.post(name: self.sessionChanged, object: object)
        }
        
        refreshTimer.start()
    }
}

extension AppSessionManagerImplementation: PlanServiceDelegate {
    func paymentTransactionDidFinish() {
        guard AuthKeychain.fetch() != nil else {
            return
        }

        log.debug("Reloading data after plan purchase", category: .app)
        retrievePropertiesAndLogIn(success: { [dataReloaded] in
            NotificationCenter.default.post(name: dataReloaded, object: nil)
        }, failure: { error in
            log.error("Data reload failed after plan purchase", category: .app, metadata: ["error": "\(error)"])
        })
    }
}
