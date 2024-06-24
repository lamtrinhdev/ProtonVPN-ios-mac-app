//
//  Created on 04/06/2024.
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

import Foundation
import protocol VPNShared.VpnAuthenticationStorageSync
import struct VPNShared.PrivateKey
import struct VPNShared.PublicKey
import struct VPNShared.VpnKeys

// Bridge between new key models with improved error handling and old keys from LegacyCommon

extension ConnectionFoundations.PrivateKey {
    init(fromLegacyKey legacyKey: VPNShared.PrivateKey) {
        self.init(
            rawRepresentation: legacyKey.rawRepresentation,
            derRepresentation: legacyKey.derRepresentation,
            base64X25519Representation: legacyKey.base64X25519Representation
        )
    }
}

extension ConnectionFoundations.PublicKey {
    init(fromLegacyKey legacyKey: VPNShared.PublicKey) {
        self.init(
            rawRepresentation: legacyKey.rawRepresentation,
            derRepresentation: legacyKey.derRepresentation
        )
    }
}

extension ConnectionFoundations.VPNKeys {
    init(fromLegacyKey legacyKeys: VPNShared.VpnKeys) {
        self.init(
            privateKey: .init(fromLegacyKey: legacyKeys.privateKey),
            publicKey: .init(fromLegacyKey: legacyKeys.publicKey)
        )
    }
}

extension VpnAuthenticationStorageSync {
    public func loadFullData() throws -> FullAuthenticationData {
        guard let keys = getStoredKeys(), let certificate = getStoredCertificate() else {
            throw AuthenticationStorageError.credentialsMissing
        }

        return FullAuthenticationData(
            keys: .init(fromLegacyKey: keys),
            certificate: certificate
        )
    }

    public func loadAuthenticationData() throws -> VPNAuthenticationData {
        guard let keys = getStoredKeys(), let certificate = getStoredCertificate() else {
            throw AuthenticationStorageError.credentialsMissing
        }

        return VPNAuthenticationData(
            clientKey: .init(fromLegacyKey: keys.privateKey),
            clientCertificate: certificate.certificate
        )
    }
}


public enum AuthenticationStorageError: Error {
    case credentialsMissing
    case credentialsExpired
}
