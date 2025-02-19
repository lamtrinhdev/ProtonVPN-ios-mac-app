//
//  Created on 09/08/2023.
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

import Foundation
import struct VPNShared.DefaultsProvider
import enum VPNShared.VPNAuthenticationStorageConfigKey
import Dependencies

// MARK: Live implementations of dependencies required by the iOS app AND its extensions

extension DefaultsProvider: DependencyKey {
    public static var liveValue: DefaultsProvider = DefaultsProvider(
        getDefaults: {
            // Use shared defaults
            UserDefaults(suiteName: AppConstants.AppGroups.main)!
        }
    )
}

extension VPNAuthenticationStorageConfigKey: DependencyKey {
    public static let liveValue: String = {
        let accessGroup = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String
        return "\(accessGroup)prt.ProtonVPN"
    }()
}
