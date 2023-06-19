//
//  Created on 18/05/2023.
//
//  Copyright (c) 2023 Proton AG
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

import SwiftUI

import ComposableArchitecture

import Strings
import Theme
import Theme_iOS

extension EdgeInsets {
    static var zero = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

public struct SettingsView: View {
    typealias NavigationStore = Store<
        PresentationState<SettingsFeature.Destination.State>,
        PresentationAction<SettingsFeature.Destination.Action>
    >

    let store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    struct ChildFeature {
        let icon: ImageAsset
        let title: String
        let accessory: Accessory.Style
    }

    let features = (
        netShield: ChildFeature(icon: Asset.icNetShield, title: Localizable.settingsTitleNetshield, accessory: .disclosure),
        killSwitch: ChildFeature(icon: Asset.icKillswitch, title: Localizable.settingsTitleKillSwitch, accessory: .disclosure),

        vpnProtocol: ChildFeature(icon: Asset.icServers, title: Localizable.settingsTitleProtocol, accessory: .disclosure),
        vpnAccelerator: ChildFeature(icon: Asset.icRocket, title: Localizable.settingsTitleVpnAccelerator, accessory: .disclosure),
        advanced: ChildFeature(icon: Asset.icSliders, title: Localizable.settingsTitleAdvanced, accessory: .disclosure),

        theme: ChildFeature(icon: Asset.icCircleHalfFilled, title: Localizable.settingsTitleTheme, accessory: .disclosure),
        betaAccess: ChildFeature(icon: Asset.icKeySkeleton, title: Localizable.settingsTitleBetaAccess, accessory: .disclosure),
        widget: ChildFeature(icon: Asset.icGrid, title: Localizable.settingsTitleWidget, accessory: .disclosure),

        supportCenter: ChildFeature(icon: Asset.icLifeRing, title: Localizable.settingsTitleSupportCenter, accessory: .externalLink),
        reportAnIssue: ChildFeature(icon: Asset.icBug, title: Localizable.settingsTitleReportIssue, accessory: .disclosure),
        debugLogs: ChildFeature(icon: Asset.icCode, title: Localizable.settingsTitleDebugLogs, accessory: .disclosure),

        censorship: ChildFeature(icon: Asset.icUsers, title: Localizable.settingsTitleCensorship, accessory: .externalLink),
        rateProtonVPN: ChildFeature(icon: Asset.icStar, title: Localizable.settingsTitleRate, accessory: .disclosure),

        restoreDefault: ChildFeature(icon: Asset.icArrowRotateRight, title: Localizable.settingsTitleRestoreDefaultSettings, accessory: .none),

        signOut: ChildFeature(icon: Asset.icArrowInToRectangle, title: Localizable.settingsTitleSignOut, accessory: .none)
    )

    private var destinationStore: NavigationStore {
        return store.scope(state: \.$destination, action: SettingsFeature.Action.destination)
    }

    private var accountSection: some View {
        section(named: Localizable.settingsSectionTitleAccount) {
            SettingsCell(
                icon: Asset.avatar,
                content: .multiline(title: "Eric Norbert", subtitle: "eric.norbert@proton.me"),
                accessory: .disclosure
            )
        }
    }

    private var featuresSection: some View {
        section(named: Localizable.settingsSectionTitleFeatures) {
            WithViewStore(store, observe: { $0.netShield }) { viewStore in
                CustomNavigationLinkStore(
                    self.destinationStore,
                    state: /SettingsFeature.Destination.State.netShield,
                    action: SettingsFeature.Destination.Action.netShield,
                    onTap: { viewStore.send(.netShieldTapped) },
                    destination: { store in NetShieldSettingsView(store: store) },
                    label: { SettingsCell(feature: features.netShield, value: viewStore.state) }
                )
            }
            WithViewStore(store, observe: { $0.killSwitch}) { viewStore in
                CustomNavigationLinkStore(
                    self.destinationStore,
                    state: /SettingsFeature.Destination.State.killSwitch,
                    action: SettingsFeature.Destination.Action.killSwitch,
                    onTap: { viewStore.send(.killSwitchTapped) },
                    destination: { store in KillSwitchSettingsView(store: store) },
                    label: { SettingsCell(feature: features.killSwitch, value: viewStore.state) }
                )
            }
        }
    }

    private var connectionSection: some View {
        section(named: Localizable.settingsSectionTitleConnection) {
            SettingsCell(feature: features.vpnProtocol, value: nil)
            SettingsCell(feature: features.vpnAccelerator, value: nil)
            SettingsCell(feature: features.advanced, value: nil)
        }
    }

    private var generalSection: some View {
        section(named: Localizable.settingsSectionTitleGeneral) {
            WithViewStore(store, observe: { $0.theme }) { viewStore in
                CustomNavigationLinkStore(
                    self.destinationStore,
                    state: /SettingsFeature.Destination.State.theme,
                    action: SettingsFeature.Destination.Action.theme,
                    onTap: { viewStore.send(.themeTapped) },
                    destination: { store in ThemeSettingsView(store: store) },
                    label: { SettingsCell(feature: features.theme, value: viewStore.state) }
                )
            }
        }
    }

    private var supportSection: some View {
        section(named: Localizable.settingsSectionTitleSupport) {
            SettingsCell(feature: features.supportCenter, value: nil)
            SettingsCell(feature: features.reportAnIssue, value: nil)
            SettingsCell(feature: features.debugLogs, value: nil)
        }
    }

    private var improveProtonSection: some View {
        section(named: Localizable.settingsSectionTitleImproveProton) {
            SettingsCell(feature: features.censorship, value: nil)
            SettingsCell(feature: features.rateProtonVPN, value: nil)
        }
    }

    private var restoreDefaultsSection: some View {
        section {
            SettingsCell(feature: features.restoreDefault, value: nil)
        }
    }

    private var signOutSection: some View {
        section {
            SettingsCell(feature: features.signOut, value: nil)
        }
    }

    public var body: some View {
        NavigationView {
            VStack {
                List {
                    accountSection
                    featuresSection
                    connectionSection
                    generalSection
                    supportSection
                    improveProtonSection
                    restoreDefaultsSection
                    signOutSection
                    Section(footer: footerView) { EmptyView() }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationBarTitleDisplayMode(.large)
            .navigationTitle(Localizable.settingsTitle)
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func section(named name: String? = nil, @ViewBuilder content: @escaping () -> some View) -> some View {
        if let name {
            Section(content: content, header: { sectionHeader(named: name) })
        } else {
            Section(content: content)
        }
    }

    private func sectionHeader(named name: String) -> some View {
        Text(name)
            .font(.body2())
            .foregroundColor(Color(.text, .weak))
            .textCase(nil) // Disable upper-casing section titles (on by default)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: .themeSpacing8, trailing: 0)) // Unindent section title
    }

    @ViewBuilder
    private var footerView: some View {
        WithViewStore(store, observe: { $0.appVersion }) { viewStore in
            HStack {
                Spacer()
                Text(Localizable.settingsAppVersion(viewStore.state))
                    .themeFont(.caption())
                    .foregroundColor(Color(.text, .weak))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: .themeSpacing32, trailing: 0))
        }
    }

    private var footerSection: some View {
        Section(footer: footerView) { EmptyView() }
    }
}

extension SettingsCell {
    init(feature: SettingsView.ChildFeature, value: LocalizedStringConvertible?) {
        self.init(
            icon: feature.icon,
            content: .standard(title: feature.title, value: value?.localizedDescription),
            accessory: Accessory(style: feature.accessory)
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(store: Store(
            initialState: SettingsFeature.State(destination: .none, netShield: .on, killSwitch: .off, theme: .light),
            reducer: SettingsFeature()
        ))
    }
}
