//
//  SmartProtocol.swift
//  vpncore - Created on 08.03.2021.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of vpncore.
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
//  along with vpncore.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation

typealias SmartProtocolCompletion = (VpnProtocol, [Int]) -> Void

protocol SmartProtocol {
    func determineBestProtocol(server: ServerIp, completion: @escaping SmartProtocolCompletion)
}

final class SmartProtocolImplementation: SmartProtocol {
    private let checkers: [SmartProtocolProtocol: SmartProtocolAvailabilityChecker]

    init(openVpnConfig: OpenVpnConfig, wireguardConfig: WireguardConfig) {
        checkers = [
            .ikev2: IKEv2AvailabilityChecker(),
            .openVpnUdp: OpenVPNUDPAvailabilityChecker(config: openVpnConfig),
            .openVpnTcp: OpenVPNTCPAvailabilityChecker(config: openVpnConfig),
            .wireguard: WireguardAvailabilityChecker(config: wireguardConfig)
        ]
    }

    func determineBestProtocol(server: ServerIp, completion: @escaping SmartProtocolCompletion) {
        let group = DispatchGroup()
        let lockQueue = DispatchQueue(label: "SmartProtocolQueue")
        var availablePorts: [SmartProtocolProtocol: [Int]] = [:]

        PMLog.D("Determining best protocol for \(server.entryIp)")

        for (proto, checker) in checkers {
            group.enter()
            checker.checkAvailability(server: server) { result in
                lockQueue.async {
                    switch result {
                    case .unavailable:
                        break
                    case let .available(ports: ports):
                        availablePorts[proto] = ports
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .global()) {
            let sorted = availablePorts.keys.sorted(by: { lhs, rhs in lhs.priority < rhs.priority })

            guard let best = sorted.first, let ports = availablePorts[best], !ports.isEmpty else {
                PMLog.D("No best protocol determined, fallback to Wireguard")
                completion(VpnProtocol.wireGuard, [51820])
                return
            }

            PMLog.D("Best protocol for \(server.entryIp) is \(best.vpnProtocol) with ports \(ports)")
            completion(best.vpnProtocol, ports)
        }
    }
}
