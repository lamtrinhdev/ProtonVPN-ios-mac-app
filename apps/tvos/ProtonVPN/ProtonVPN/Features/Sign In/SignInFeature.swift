//
//  Created on 25/04/2024.
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

@Reducer
struct SignInFeature {
    @ObservableState
    enum State: Equatable {
        case loadingSignInCode
        case waitingForAuthentication(code: SignInCode, remainingAttempts: Int)
    }

    enum Action: Equatable {
        case pollServer
        case fetchSignInCode
        case codeFetchingFinished(TaskResult<SignInCode>)
        case authenticationFinished(TaskResult<SessionAuthResult>)
        case signInFinished(TaskResult<AuthCredentials>)
    }

    @Dependency(NetworkClient.self) var networkClient
    @Dependency(\.continuousClock) var clock

    private enum CancelID { case timer }

    enum SignInFailureReason: Error {
        /// We ran out of authentication polls before the code was entered
        case authenticationAttemptsExhausted
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .fetchSignInCode:
                return .run { send in await send(.codeFetchingFinished(TaskResult { try await networkClient.fetchSignInCode() })) }

            case .pollServer:
                guard case .waitingForAuthentication(let code, let remainingAttempts) = state else {
                    return .cancel(id: CancelID.timer)
                }
                if remainingAttempts <= 0 {
                    return .merge(
                        .cancel(id: CancelID.timer),
                        .run { send in await send(.signInFinished(.failure(SignInFailureReason.authenticationAttemptsExhausted)))}
                    )
                }

                state = .waitingForAuthentication(code: code, remainingAttempts: remainingAttempts - 1)
                return .run { send in await send(.authenticationFinished(TaskResult { try await networkClient.forkedSession(code.selector) })) }

            case .codeFetchingFinished(.success(let response)):
                @Dependency(ServerPollConfiguration.self) var pollConfiguration
                state = .waitingForAuthentication(code: response, remainingAttempts: pollConfiguration.failAfterAttempts)
                return .run { send in
                    try? await clock.sleep(for: pollConfiguration.delayBeforePollingStarts)
                    await send(.pollServer)
                }
                .cancellable(id: CancelID.timer, cancelInFlight: true)

            case .codeFetchingFinished(.failure(let error)):
                // handle non-retryable error
                return .none

            case .authenticationFinished(.success(.authenticated(let response))):
                let credentials: AuthCredentials = .init(uID: response.uid, accessToken: response.accessToken, refreshToken: response.refreshToken)
                return .run { send in await send(.signInFinished(.success(credentials))) }

            case .authenticationFinished(.success(.invalidSelector)):
                // Parent session has not yet authenticated this selector
                // a.k.a. user has not typed in code in browser
                @Dependency(ServerPollConfiguration.self) var pollConfiguration
                return .run { send in
                    try? await clock.sleep(for: pollConfiguration.period)
                    await send(.pollServer)
                }

            case .authenticationFinished(.failure):
                // handle non-retryable error
                return .none

            case .signInFinished:
                // Handled by parent reducer
                return .none
            }
        }
    }
}
