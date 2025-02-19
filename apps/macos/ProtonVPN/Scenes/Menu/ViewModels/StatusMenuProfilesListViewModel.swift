//
//  StatusMenuProfilesListViewModel.swift
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
import LegacyCommon

class StatusMenuProfilesListViewModel {

    private let vpnGateway: VpnGatewayProtocol
    private let profileManager: ProfileManager
    
    var contentChanged: (() -> Void)?
    
    var cellHeight: CGFloat {
        return 44
    }
    
    var cellCount: Int {
        return profileManager.allProfiles.count
    }
    
    private var userTier: Int {
        do {
            return try vpnGateway.userTier()
        } catch {
            return .freeTier
        }
    }
    
    init(vpnGateway: VpnGatewayProtocol, profileManager: ProfileManager) {
        self.vpnGateway = vpnGateway
        self.profileManager = profileManager

        NotificationCenter.default.addObserver(self, selector: #selector(profilesChanged),
                                               name: profileManager.contentChanged, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func cellModel(forIndex index: Int) -> StatusMenuProfileItemViewModel {
        return StatusMenuProfileItemViewModel(profile: profileManager.allProfiles[index], vpnGateway: vpnGateway, userTier: userTier)
    }
    
    @objc private func profilesChanged() {
        contentChanged?()
    }
}
