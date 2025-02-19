//
//  MapSectionViewModel.swift
//  ProtonVPN - Created on 27.06.19.
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
import MapKit

import Dependencies

import Domain
import Ergonomics
import Localization
import Persistence
import LegacyCommon

// Refactor annotation O(n^2) grouping logic when number of secure core servers ever exceed this value
private let maximumSecureCoreServerCount = 512

struct AnnotationChange {
    let oldAnnotations: [CountryAnnotationViewModel]
    let newAnnotations: [CountryAnnotationViewModel]
}

protocol MapSectionViewModelFactory {
    func makeMapSectionViewModel(viewToggle: Notification.Name) -> MapSectionViewModel
}

extension DependencyContainer: MapSectionViewModelFactory {
    func makeMapSectionViewModel(viewToggle: Notification.Name) -> MapSectionViewModel {
        return MapSectionViewModel(appStateManager: makeAppStateManager(),
                                   propertiesManager: makePropertiesManager(),
                                   vpnGateway: makeVpnGateway(),
                                   navService: makeNavigationService(),
                                   vpnKeychain: makeVpnKeychain(),
                                   viewToggle: viewToggle,
                                   alertService: makeCoreAlertService())
    }
}

class MapSectionViewModel {
    
    private let countrySelected = Notification.Name("MapSectionViewModelCountrySelected")
    private let scEntryCountrySelected = Notification.Name("MapSectionViewModelScEntryCountrySelected")
    private let scExitCountrySelected = Notification.Name("MapSectionViewModelScExitCountrySelected")
    private let appStateManager: AppStateManager
    private let vpnGateway: VpnGatewayProtocol
    private let navService: NavigationService
    private let vpnKeychain: VpnKeychainProtocol
    private let propertiesManager: PropertiesManagerProtocol
    private let alertService: CoreAlertService
    
    var contentChanged: ((AnnotationChange) -> Void)?
    var connectionsChanged: (([ConnectionViewModel]) -> Void)?
    
    private var activeView: ServerType = .standard
    
    var annotations: [CountryAnnotationViewModel] = []
    var connections: [ConnectionViewModel] = []

    init(appStateManager: AppStateManager, propertiesManager: PropertiesManagerProtocol,
         vpnGateway: VpnGatewayProtocol, navService: NavigationService, vpnKeychain: VpnKeychainProtocol,
         viewToggle: Notification.Name, alertService: CoreAlertService) {
        
        self.appStateManager = appStateManager
        self.propertiesManager = propertiesManager
        self.vpnGateway = vpnGateway
        self.navService = navService
        self.vpnKeychain = vpnKeychain
        self.alertService = alertService

        NotificationCenter.default.addObserver(forName: .AppStateManager.stateChange,
                                               object: nil,
                                               queue: nil,
                                               using: appStateChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(viewToggled(_:)),
                                               name: viewToggle, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetCurrentState), name: ServerListUpdateNotification.name, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetCurrentState),
                                               name: type(of: propertiesManager).vpnProtocolNotification, object: nil)
        
        activeView = propertiesManager.serverTypeToggle
        annotations = annotations(forView: activeView)
        connections = connections(forView: activeView)
    }
    
    // MARK: - Private functions
    private func appStateChanged(_ notification: Notification) {
        guard let state = notification.object as? AppState else {
            return
        }

        if state.isConnected,
            let serverType = appStateManager.activeConnection()?.server.serverType, serverType != activeView {
            setView(serverType)
        }
        
        annotations.forEach { (annotation) in
            annotation.appStateChanged(to: state)
        }
        
        updateConnections()
    }
    
    @objc private func viewToggled(_ notification: Notification) {
        setView(propertiesManager.serverTypeToggle)
    }
    
    @objc private func resetCurrentState() {
        executeOnUIThread {
            self.setView(self.activeView)
            self.updateConnections()
        }
    }
    
    private func updateConnections() {
        connections = connections(forView: activeView)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            self.connectionsChanged?(self.connections)
        }
    }
    
    private func setView(_ newView: ServerType) {
        let oldAnnotations = annotations
        activeView = newView
        annotations = annotations(forView: activeView)
        let contentChange = AnnotationChange(oldAnnotations: oldAnnotations, newAnnotations: annotations)
        
        connections = connections(forView: activeView)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            self.contentChanged?(contentChange)
        }
        
    }
    
    private func annotations(forView viewType: ServerType) -> [CountryAnnotationViewModel] {
        do {
            let userTier = try vpnKeychain.fetchCached().maxTier
            
            let annotations: [CountryAnnotationViewModel]
            switch viewType {
            case .standard, .p2p, .tor, .unspecified:
                annotations = standardAnnotations(userTier)
            case .secureCore:
                annotations = secureCoreAnnotations(userTier)
            }
            return annotations
        } catch {
            alertService.push(alert: CannotAccessVpnCredentialsAlert())
            return []
        }
    }
    
    private func connections(forView viewType: ServerType) -> [ConnectionViewModel] {
        let connections: [ConnectionViewModel]
        switch viewType {
        case .standard, .p2p, .tor, .unspecified:
            connections = standardConnections()
        case .secureCore:
            connections = secureCoreConnections()
        }
        return connections
    }
    
    private func standardAnnotations(_ userTier: Int) -> [CountryAnnotationViewModel] {
        @Dependency(\.serverRepository) var repository
        let isCountry = VPNServerFilter.kind(.country)
        let isNotSecureCore = VPNServerFilter.features(.standard)
        let countryGroups = repository.getGroups(filteredBy: [isCountry, isNotSecureCore])
        return countryGroups.compactMap { group in
            guard case .country(let code) = group.kind else {
                assertionFailure("Gateways should have been filtered out but we got: \(group.kind)")
                return nil
            }
            return StandardCountryAnnotationViewModel(
                appStateManager: appStateManager,
                vpnGateway: vpnGateway,
                countryCode: code,
                minTier: group.minTier,
                userTier: userTier,
                coordinate: LocationUtility.coordinate(forCountry: code)
            )
        }
    }
    
    private func secureCoreEntrySelectionChange(_ selection: SCEntryCountrySelection) {
        annotations.forEach({ (annotation) in
            if let annotation = annotation as? SCEntryCountryAnnotationViewModel {
                if annotation.countryCode != selection.countryCode {
                    annotation.secureCoreSelected(selection)
                }
            }
        })
        
        updateConnections()
    }
    
    private func secureCoreExitSelectionChange(_ selection: SCExitCountrySelection) {
        annotations.forEach({ (annotation) in
            if let annotation = annotation as? SCEntryCountryAnnotationViewModel {
                if annotation.countryCode != selection.countryCode {
                    annotation.countrySelected(selection)
                }
            }
        })
        
        updateConnections()
    }

    private func fetchSecureCoreServers() -> [ServerInfo] {
        @Dependency(\.serverRepository) var repository
        let isSecureCore = VPNServerFilter.features(.secureCore)
        let isCountry = VPNServerFilter.kind(.country)
        return repository.getServers(filteredBy: [isSecureCore, isCountry], orderedBy: .none)
    }

    /// Let's refactor this during the redesign, or when we trigger the secure core server count assertion.
    private func secureCoreAnnotations(_ userTier: Int) -> [CountryAnnotationViewModel] {
        let secureCoreServers = fetchSecureCoreServers()
        assert(secureCoreServers.count < maximumSecureCoreServerCount, "Refactor O(n^2) grouping algorithm")

        let exitCountryCodes = secureCoreServers.map(\.logical.exitCountryCode).uniqued
        let entryCountryCodes = secureCoreServers.map(\.logical.entryCountryCode).uniqued

        let exitCountryAnnotations: [CountryAnnotationViewModel] = exitCountryCodes.map { exitCountryCode in
            let servers = secureCoreServers.filter { $0.logical.exitCountryCode == exitCountryCode }

            let annotation = SCExitCountryAnnotationViewModel(
                appStateManager: appStateManager,
                vpnGateway: vpnGateway,
                countryCode: exitCountryCode,
                minTier: servers.map(\.logical.tier).min() ?? .freeTier,
                servers: servers,
                userTier: userTier,
                coordinate: LocationUtility.coordinate(forCountry: exitCountryCode)
            )
            annotation.externalViewStateChange = { [weak self] selection in
                self?.secureCoreExitSelectionChange(selection)
            }
            return annotation
        }

        // e.g [CH: [CA, UK, US], IS: [DE, LT]]
        let entryToExitCountryCodeMap = entryCountryCodes.reduce(into: [:]) { map, entryCode in
            map[entryCode] = secureCoreServers
                .filter { $0.logical.entryCountryCode == entryCode }
                .map(\.logical.exitCountryCode)
        }
        
        let entryCountryAnnotations: [CountryAnnotationViewModel] = entryToExitCountryCodeMap.map { entry, exits in
            let annotation = SCEntryCountryAnnotationViewModel(
                appStateManager: appStateManager,
                countryCode: entry,
                exitCountryCodes: exits,
                coordinate: LocationUtility.coordinate(forCountry: entry)
            )
            annotation.externalViewStateChange = { [weak self] selection in
                self?.secureCoreEntrySelectionChange(selection)
            }
            return annotation
        }
        
        return entryCountryAnnotations + exitCountryAnnotations
    }
    
    private func standardConnections() -> [ConnectionViewModel] {
        return annotations.filter({ (annotation) -> Bool in
            guard let annotation = annotation as? StandardCountryAnnotationViewModel else { return false }
            return annotation.isConnected
        }).map({ (annotation) -> ConnectionViewModel in
            return ConnectionViewModel(.connected, fromHomeTo: annotation)
        })
    }
    
    // swiftlint:disable cyclomatic_complexity
    private func secureCoreConnections() -> [ConnectionViewModel] {
        var secureCores = [SCEntryCountryAnnotationViewModel]()
        var selectedAnnotation: CountryAnnotationViewModel?
        var connectedAnnotation: CountryAnnotationViewModel?
        annotations.forEach { (annotation) in
            if let entryAnnotation = annotation as? SCEntryCountryAnnotationViewModel {
                secureCores.append(entryAnnotation)
                if entryAnnotation.state == .hovered {
                    selectedAnnotation = entryAnnotation
                }
            } else if let exitAnnotation = annotation as? SCExitCountryAnnotationViewModel {
                if exitAnnotation.isConnected {
                    connectedAnnotation = exitAnnotation
                }
                if exitAnnotation.state == .hovered {
                    selectedAnnotation = exitAnnotation
                }
            }
        }
        
        var connections = [ConnectionViewModel]()
        
        if let connectedAnnotation = connectedAnnotation {
            if let exitAnnotation = connectedAnnotation as? SCExitCountryAnnotationViewModel {
                annotations.forEach({ (annotation) in
                    if let annotation = annotation as? SCEntryCountryAnnotationViewModel,
                       annotation.isConnected {
                        connections.append(ConnectionViewModel(.connected, between: exitAnnotation, and: annotation))
                        connections.append(ConnectionViewModel(.connected, fromHomeTo: annotation))
                    }
                })
            }
        }
        if let selectedAnnotation = selectedAnnotation {
            if let entryAnnotation = selectedAnnotation as? SCEntryCountryAnnotationViewModel {
                connections.append(ConnectionViewModel(.proposed, fromHomeTo: entryAnnotation))
                
                entryAnnotation.exitCountryCodes.forEach({ (code) in
                    annotations.forEach({ (annotation) in
                        if let serverAnnotation = annotation as? SCExitCountryAnnotationViewModel,
                           serverAnnotation.matches(code) {
                            connections.append(ConnectionViewModel(.proposed, between: entryAnnotation, and: annotation))
                        }
                    })
                })
            } else if let exitAnnotation = selectedAnnotation as? SCExitCountryAnnotationViewModel {
                annotations.forEach({ (annotation) in
                    if let annotation = annotation as? SCEntryCountryAnnotationViewModel,
                       annotation.exitCountryCodes.contains(exitAnnotation.countryCode) {
                        connections.append(ConnectionViewModel(.proposed, between: exitAnnotation, and: annotation))
                        connections.append(ConnectionViewModel(.proposed, fromHomeTo: annotation))
                    }
                })
            }
        }
        
        if connectedAnnotation == nil && selectedAnnotation == nil {
            for (index, element) in secureCores.enumerated() {
                connections.append(ConnectionViewModel(.connected, between: element, and: secureCores[(index + 1) % secureCores.count]))
            }
        }
        
        return connections
    }
    // swiftlint:enable cyclomatic_complexity
    
}
