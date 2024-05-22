//
//  Created on 05.04.24.
//
//  Copyright (c) 2024 Proton AG
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

import ComposableArchitecture
import SwiftUI
import Dependencies
import ProtonCoreLog
import CommonNetworking
import Persistence

@main
struct ProtonVPNApp: App {
    var store: StoreOf<AppFeature> = .init(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
                .onAppear { self.startup() }
        }
    }

    private func startup() {
        @Dependency(\.dohConfiguration) var doh
        if doh.defaultHost.contains("black") {
            PMLog.setEnvironment(environment: "black")
        } else {
            PMLog.setEnvironment(environment: "production")
        }

        store.send(.networking(.startAcquiringSession))
    }
}
