//
//  Created on 13/06/2024.
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

import class GoLibs.LocalAgentStatusMessage
import class GoLibs.LocalAgentConnectionDetails
import class GoLibs.LocalAgentStringToValueMap

import let ConnectionFoundations.log

final class LocalAgentClientImplementation: NSObject, LocalAgentClient {
    func onTlsSessionEnded() { }

    func onTlsSessionStarted() { }

    weak var delegate: LocalAgentClientDelegate?

    /// Logging callback required by `LocalAgentNativeClientProtocol` protocol
    func log(_ text: String?) {
        guard let text = text else {
            return
        }

        ConnectionFoundations.log.info("\(text)", category: .localAgent, event: .log)
    }

    func onError(_ code: Int, description: String?) {
        guard let error = LocalAgentError.from(code: code) else {
            ConnectionFoundations.log.error("Ignoring unknown local agent error", category: .localAgent, event: .error)
            return
        }
        delegate?.didReceive(event: .error(error))
    }

    func onState(_ state: String?) {
        guard let state = state else {
            ConnectionFoundations.log.error("Received empty state from local agent shared library", category: .localAgent, event: .stateChange)
            return
        }

        ConnectionFoundations.log.info("Local agent shared library state reported as changed to \(state)", category: .localAgent, event: .stateChange)
        delegate?.didReceive(event: .state(LocalAgentState.from(string: state)))
    }

    func onStatusUpdate(_ status: LocalAgentStatusMessage?) {
        if let details = status?.connectionDetails {
            didReceive(connectionDetails: details)
        }

        if let statistics = status?.featuresStatistics {
            didReceive(statistics: statistics)
        }
    }

    private func didReceive(connectionDetails: LocalAgentConnectionDetails) {
        let detailsMessage = ConnectionDetailsMessage(details: connectionDetails)
        ConnectionFoundations.log.info("Local agent shared library received connection details: \("\(detailsMessage)".maskIPs)", category: .localAgent, event: .connect)
        delegate?.didReceive(event: .connectionDetails(detailsMessage))
    }

    private func didReceive(statistics: LocalAgentStringToValueMap) {
        do {
            let stats = try FeatureStatisticsMessage(localAgentStatsDictionary: statistics)
            ConnectionFoundations.log.info("Local agent shared library received statistics: \(stats)", category: .localAgent, event: .stateChange)
            // delegate?.didReceive(event: .stats(stats))
        } catch {
            ConnectionFoundations.log.error("Failed to decode feature stats", category: .localAgent, event: .error, metadata: ["error": "\(error)"])
        }
    }
}
