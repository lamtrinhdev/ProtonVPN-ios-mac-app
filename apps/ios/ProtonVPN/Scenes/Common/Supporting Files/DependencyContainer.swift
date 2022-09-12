//
//  DependencyContainer.swift
//  ProtonVPN - Created on 09/09/2019.
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

import Foundation
import vpncore
import KeychainAccess
import BugReport
import Search
import Review
import NetworkExtension
import Timer

// FUTURETODO: clean up objects that are possible to re-create if memory warning is received

final class DependencyContainer: Container {
    // Singletons
    private lazy var navigationService = NavigationService(self)

    private lazy var vpnGateway: VpnGateway = VpnGateway(vpnApiService: makeVpnApiService(),
                                                         appStateManager: makeAppStateManager(),
                                                         alertService: makeCoreAlertService(),
                                                         vpnKeychain: makeVpnKeychain(),
                                                         authKeychain: makeAuthKeychainHandle(),
                                                         siriHelper: SiriHelper(),
                                                         netShieldPropertyProvider: makeNetShieldPropertyProvider(),
                                                         natTypePropertyProvider: makeNATTypePropertyProvider(),
                                                         safeModePropertyProvider: makeSafeModePropertyProvider(),
                                                         propertiesManager: makePropertiesManager(),
                                                         profileManager: makeProfileManager(),
                                                         availabilityCheckerResolverFactory: self,
                                                         serverStorage: makeServerStorage())
    private lazy var wireguardFactory = WireguardProtocolFactory(bundleId: AppConstants.NetworkExtensions.wireguard, appGroup: config.appGroup, propertiesManager: makePropertiesManager(), vpnManagerFactory: self)
    private lazy var ikeFactory = IkeProtocolFactory(factory: self)
    private lazy var openVpnFactory = OpenVpnProtocolFactory(bundleId: AppConstants.NetworkExtensions.openVpn, appGroup: config.appGroup, propertiesManager: makePropertiesManager(), vpnManagerFactory: self)
    private lazy var windowService: WindowService = WindowServiceImplementation(window: UIWindow(frame: UIScreen.main.bounds))
    private lazy var timerFactory: TimerFactory = TimerFactoryImplementation()
    private lazy var appStateManager: AppStateManager = AppStateManagerImplementation(
                                                                        vpnApiService: makeVpnApiService(),
                                                                        vpnManager: makeVpnManager(),
                                                                        networking: makeNetworking(),
                                                                        alertService: makeCoreAlertService(),
                                                                        timerFactory: timerFactory,
                                                                        propertiesManager: makePropertiesManager(),
                                                                        vpnKeychain: makeVpnKeychain(),
                                                                        configurationPreparer: makeVpnManagerConfigurationPreparer(),
                                                                        vpnAuthentication: makeVpnAuthentication(),
                                                                        doh: makeDoHVPN(),
                                                                        serverStorage: makeServerStorage(),
                                                                        natTypePropertyProvider: makeNATTypePropertyProvider(),
                                                                        netShieldPropertyProvider: makeNetShieldPropertyProvider(),
                                                                        safeModePropertyProvider: makeSafeModePropertyProvider())
    private lazy var appSessionManager: AppSessionManagerImplementation = AppSessionManagerImplementation(factory: self)
    private lazy var uiAlertService: UIAlertService = IosUiAlertService(windowService: makeWindowService(), planService: makePlanService())
    private lazy var iosAlertService: CoreAlertService = IosAlertService(self)
    
    private lazy var maintenanceManager: MaintenanceManagerProtocol = MaintenanceManager(factory: self)
    private lazy var maintenanceManagerHelper: MaintenanceManagerHelper = MaintenanceManagerHelper(factory: self)
    
    // Refreshes app data at predefined time intervals
    private lazy var refreshTimer = AppSessionRefreshTimer(factory: self,
                                                           timerFactory: timerFactory,
                                                           refreshIntervals: (AppConstants.Time.fullServerRefresh,
                                                                              AppConstants.Time.serverLoadsRefresh,
                                                                              AppConstants.Time.userAccountRefresh))
    // Refreshes announements from API
    private lazy var announcementRefresher = AnnouncementRefresherImplementation(factory: self)
    
    // Instance of DynamicBugReportManager is persisted because it has a timer that refreshes config from time to time.
    private lazy var dynamicBugReportManager = DynamicBugReportManager(
        api: makeReportsApiService(),
        storage: DynamicBugReportStorageUserDefaults(userDefaults: Storage()),
        alertService: makeCoreAlertService(),
        propertiesManager: makePropertiesManager(),
        updateChecker: makeUpdateChecker(),
        vpnKeychain: makeVpnKeychain(),
        logContentProvider: makeLogContentProvider()
    )

    private lazy var vpnAuthentication: VpnAuthentication = {
        return VpnAuthenticationRemoteClient(sessionService: makeSessionService(),
                                             authenticationStorage: makeVpnAuthenticationStorage(),
                                             safeModePropertyProvider: makeSafeModePropertyProvider())
    }()
    
    #if TLS_PIN_DISABLE
    private lazy var trustKitHelper: TrustKitHelper? = nil
    #else
    private lazy var trustKitHelper: TrustKitHelper? = TrustKitHelper()
    #endif

    private lazy var networkingDelegate: NetworkingDelegate = iOSNetworkingDelegate(alertingService: makeCoreAlertService()) // swiftlint:disable:this weak_delegate
    private lazy var planService = CorePlanService(networking: makeNetworking(), alertService: makeCoreAlertService(), storage: makeStorage(), authKeychain: makeAuthKeychainHandle())
    private lazy var doh: DoHVPN = {
        let propertiesManager = makePropertiesManager()
        let doh = DoHVPN(alternativeRouting: propertiesManager.alternativeRouting,
                         customHost: propertiesManager.apiEndpoint)

        propertiesManager.onAlternativeRoutingChange = { alternativeRouting in
            doh.alternativeRouting = alternativeRouting
        }
        return doh
    }()
    private lazy var searchStorage = SearchModuleStorage(storage: makeStorage())
    private lazy var review = Review(configuration: Configuration(settings: makePropertiesManager().ratingSettings), plan: (try? makeVpnKeychain().fetchCached().accountPlan.description), logger: { message in log.debug("\(message)", category: .review) })

    init() {
        let prefix = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String

        super.init(
            Config(appIdentifierPrefix: prefix,
                   appGroup: AppConstants.AppGroups.main,
                   accessGroup: "\(prefix)prt.ProtonVPN",
                   openVpnExtensionBundleIdentifier: AppConstants.NetworkExtensions.openVpn,
                   wireguardVpnExtensionBundleIdentifier: AppConstants.NetworkExtensions.wireguard)
        )
    }

    // MARK: - Overridden factory methods
    // MARK: DoHVPNFactory
    override func makeDoHVPN() -> DoHVPN {
        doh
    }

    // MARK: NetworkingDelegate
    override func makeNetworkingDelegate() -> NetworkingDelegate {
        networkingDelegate
    }

    // MARK: CoreAlertServiceFactory
    override func makeCoreAlertService() -> CoreAlertService {
        iosAlertService
    }

    // MARK: OpenVPNProtocolFactoryCreator
    override func makeOpenVpnProtocolFactory() -> OpenVpnProtocolFactory {
        openVpnFactory
    }

    // MARK: WireguardProtocolFactoryCreator
    override func makeWireguardProtocolFactory() -> WireguardProtocolFactory {
        wireguardFactory
    }

    // MARK: VpnCredentialsConfiguratorFactoryCreator
    override func makeVpnCredentialsConfiguratorFactory() -> VpnCredentialsConfiguratorFactory {
          IOSVpnCredentialsConfiguratorFactory(propertiesManager: makePropertiesManager())
    }

    // MARK: VpnAuthentication
    override func makeVpnAuthentication() -> VpnAuthentication {
        vpnAuthentication
    }
}

extension DoHVPN {
    convenience init(alternativeRouting: Bool, customHost: String?) {
        #if !RELEASE
        let atlasSecret: String? = ObfuscatedConstants.atlasSecret
        #else
        let atlasSecret: String? = nil
        #endif

        self.init(apiHost: ObfuscatedConstants.apiHost,
                  verifyHost: ObfuscatedConstants.humanVerificationV3Host,
                  alternativeRouting: alternativeRouting,
                  customHost: customHost,
                  atlasSecret: atlasSecret,
                  // Will get updated once AppStateManager is initialized
                  appState: .disconnected)
    }
}

// MARK: NavigationServiceFactory
extension DependencyContainer: NavigationServiceFactory {
    func makeNavigationService() -> NavigationService {
        return navigationService
    }
}

// MARK: SettingsServiceFactory
extension DependencyContainer: SettingsServiceFactory {
    func makeSettingsService() -> SettingsService {
        return navigationService
    }
}

// MARK: VpnManagerConfigurationPreparer
extension DependencyContainer: VpnManagerConfigurationPreparerFactory {
    func makeVpnManagerConfigurationPreparer() -> VpnManagerConfigurationPreparer {
        return VpnManagerConfigurationPreparer(vpnKeychain: makeVpnKeychain(),
                                               alertService: makeCoreAlertService(),
                                               propertiesManager: makePropertiesManager()
        )
    }
}

// MARK: WindowServiceFactory
extension DependencyContainer: WindowServiceFactory {
    func makeWindowService() -> WindowService {
        return windowService
    }
}

// MARK: VpnApiServiceFactory
extension DependencyContainer: VpnApiServiceFactory {
    func makeVpnApiService() -> VpnApiService {
        return VpnApiService(networking: makeNetworking())
    }
}

// MARK: AppStateManagerFactory
extension DependencyContainer: AppStateManagerFactory {
    func makeAppStateManager() -> AppStateManager {
        return appStateManager
    }
}

// MARK: AppSessionManagerFactory
extension DependencyContainer: AppSessionManagerFactory {
    func makeAppSessionManager() -> AppSessionManager {
        return appSessionManager
    }
}

// MARK: VpnGatewayFactory
extension DependencyContainer: VpnGatewayFactory {
    func makeVpnGateway() -> VpnGatewayProtocol {
        return vpnGateway
    }
}

// MARK: ReportBugViewModelFactory
extension DependencyContainer: ReportBugViewModelFactory {
    func makeReportBugViewModel() -> ReportBugViewModel {
        return ReportBugViewModel(os: "iOS",
                                  osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                  propertiesManager: makePropertiesManager(),
                                  reportsApiService: makeReportsApiService(),
                                  alertService: makeCoreAlertService(),
                                  vpnKeychain: makeVpnKeychain(),
                                  logContentProvider: makeLogContentProvider(),
                                  authKeychain: makeAuthKeychainHandle())
    }
}

// MARK: ReportsApiServiceFactory
extension DependencyContainer: ReportsApiServiceFactory {
    func makeReportsApiService() -> ReportsApiService {
        return ReportsApiService(networking: makeNetworking(), authKeychain: makeAuthKeychainHandle())
    }
}

// MARK: UIAlertServiceFactory
extension DependencyContainer: UIAlertServiceFactory {
    func makeUIAlertService() -> UIAlertService {
        return uiAlertService
    }
}

// MARK: TrustKitHelperFactory
extension DependencyContainer: TrustKitHelperFactory {
    func makeTrustKitHelper() -> TrustKitHelper? {
        return trustKitHelper
    }
}

// MARK: AppSessionRefreshTimerFactory
extension DependencyContainer: AppSessionRefreshTimerFactory {
    func makeAppSessionRefreshTimer() -> AppSessionRefreshTimer {
        return refreshTimer
    }
}

// MARK: - AppSessionRefresherFactory
extension DependencyContainer: AppSessionRefresherFactory {
    func makeAppSessionRefresher() -> AppSessionRefresher {
        return appSessionManager
    }
}
        
// MARK: - MaintenanceManagerFactory
extension DependencyContainer: MaintenanceManagerFactory {
    func makeMaintenanceManager() -> MaintenanceManagerProtocol {
        return maintenanceManager
    }
}

// MARK: - MaintenanceManagerHelperFactory
extension DependencyContainer: MaintenanceManagerHelperFactory {
    func makeMaintenanceManagerHelper() -> MaintenanceManagerHelper {
        return maintenanceManagerHelper
    }
}

// MARK: - AnnouncementRefresherFactory
extension DependencyContainer: AnnouncementRefresherFactory {
    func makeAnnouncementRefresher() -> AnnouncementRefresher {
        return announcementRefresher
    }
}

// MARK: - AnnouncementStorageFactory
extension DependencyContainer: AnnouncementStorageFactory {
    func makeAnnouncementStorage() -> AnnouncementStorage {
        return AnnouncementStorageUserDefaults(userDefaults: Storage.userDefaults(), keyNameProvider: nil)
    }
}

// MARK: - AnnouncementManagerFactory
extension DependencyContainer: AnnouncementManagerFactory {
    func makeAnnouncementManager() -> AnnouncementManager {
        return AnnouncementManagerImplementation(factory: self)
    }
}

// MARK: - CoreApiServiceFactory
extension DependencyContainer: CoreApiServiceFactory {
    func makeCoreApiService() -> CoreApiService {
        return CoreApiServiceImplementation(networking: makeNetworking())
    }
}

// MARK: - AnnouncementsViewModelFactory
extension DependencyContainer: AnnouncementsViewModelFactory {
    func makeAnnouncementsViewModel() -> AnnouncementsViewModel {
        return AnnouncementsViewModel(factory: self)
    }
}

// MARK: - SafariServiceFactory
extension DependencyContainer: SafariServiceFactory {
    func makeSafariService() -> SafariServiceProtocol {
        return SafariService()
    }
}

// MARK: TroubleshootViewModelFactory
extension DependencyContainer: TroubleshootViewModelFactory {
    func makeTroubleshootViewModel() -> TroubleshootViewModel {
        return TroubleshootViewModel(propertiesManager: makePropertiesManager())
    }
}

// MARK: LoginServiceFactory
extension DependencyContainer: LoginServiceFactory {
    func makeLoginService() -> LoginService {
        return CoreLoginService(factory: self)
    }
}

// MARK: PlanServiceFactory
extension DependencyContainer: PlanServiceFactory {
    func makePlanService() -> PlanService {
        return planService
    }
}

// MARK: LogFileManagerFactory
extension DependencyContainer: LogFileManagerFactory {
    func makeLogFileManager() -> LogFileManager {
        return LogFileManagerImplementation()
    }
}

// MARK: OnboardingServiceFactory
extension DependencyContainer: OnboardingServiceFactory {
    func makeOnboardingService() -> OnboardingService {
        return OnboardingModuleService(factory: self)
    }
}

// MARK: BugReportCreatorFactory
extension DependencyContainer: BugReportCreatorFactory {
    func makeBugReportCreator() -> BugReportCreator {
        return iOSBugReportCreator()
    }
}

// MARK: DynamicBugReportManagerFactory
extension DependencyContainer: DynamicBugReportManagerFactory {
    func makeDynamicBugReportManager() -> DynamicBugReportManager {
        return dynamicBugReportManager
    }
}

// MARK: SearchStorageFactory
extension DependencyContainer: SearchStorageFactory {
    func makeSearchStorage() -> SearchStorage {
        return searchStorage
    }
}

// MARK: ReviewFactory
extension DependencyContainer: ReviewFactory {
    func makeReview() -> Review {
        return review
    }
}

// MARK: PaymentsApiServiceFactory
extension DependencyContainer: PaymentsApiServiceFactory {
    func makePaymentsApiService() -> PaymentsApiService {
        return PaymentsApiServiceImplementation(networking: makeNetworking(), vpnKeychain: makeVpnKeychain(), vpnApiService: makeVpnApiService())
    }
}

// MARK: CouponViewModelFactory
extension DependencyContainer: CouponViewModelFactory {
    func makeCouponViewModel() -> CouponViewModel {
        return CouponViewModel(paymentsApiService: makePaymentsApiService(), appSessionRefresher: appSessionManager)
    }
}

// MARK: LogContentProviderFactory
extension DependencyContainer: LogContentProviderFactory {
    func makeLogContentProvider() -> LogContentProvider {
        return IOSLogContentProvider(appLogsFolder: LogFileManagerImplementation().getFileUrl(named: AppConstants.Filenames.appLogFilename).deletingLastPathComponent(),
                                     appGroup: AppConstants.AppGroups.main,
                                     wireguardProtocolFactory: wireguardFactory)
    }
}

// MARK: SessionServiceFactory
extension DependencyContainer: SessionServiceFactory {
    func makeSessionService() -> SessionService {
        return SessionServiceImplementation(factory: self)
    }
}

// MARK: AvailabilityCheckerResolverFactory
extension DependencyContainer: AvailabilityCheckerResolverFactory {
    func makeAvailabilityCheckerResolver(openVpnConfig: OpenVpnConfig, wireguardConfig: WireguardConfig) -> AvailabilityCheckerResolver {
        AvailabilityCheckerResolverImplementation(openVpnConfig: openVpnConfig, wireguardConfig: wireguardConfig)
    }
}
