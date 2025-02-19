//
//  AppSessionRefreshTimer.swift
//  vpncore - Created on 2020-09-01.
//
//  Copyright (c) 2019 Proton Technologies AG
//
//  This file is part of LegacyCommon.
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
//  along with LegacyCommon.  If not, see <https://www.gnu.org/licenses/>.
//

import Foundation
import Timer

public protocol AppSessionRefreshTimerFactory {
    func makeAppSessionRefreshTimer() -> AppSessionRefreshTimer
}

public protocol AppSessionRefreshTimerDelegate: AnyObject {
    func shouldRefreshFull() -> Bool
    func shouldRefreshLoads() -> Bool
    func shouldRefreshAccount() -> Bool
    func shouldRefreshStreaming() -> Bool
    func shouldRefreshPartners() -> Bool
}

public extension AppSessionRefreshTimerDelegate {
    func shouldRefreshFull() -> Bool { return true }
    func shouldRefreshLoads() -> Bool { return true }
    func shouldRefreshAccount() -> Bool { return true }
    func shouldRefreshStreaming() -> Bool { return true }
    func shouldRefreshPartners() -> Bool { return true }
}

public protocol AppSessionRefreshTimer {
    /// Start app session refresh timers
    ///
    /// Renamed from just start() to make it easier to search for usages in code.
    func startTimers()

    /// Stop app session refresh timers
    ///
    /// Renamed from just stop() to make it easier to search for usages in code.
    func stopTimers()
}

public class AppSessionRefreshTimerImplementation: AppSessionRefreshTimer {
    // swiftlint:disable:next large_tuple
    public typealias RefreshIntervals = (
        full: TimeInterval,
        loads: TimeInterval,
        account: TimeInterval,
        streaming: TimeInterval,
        partners: TimeInterval
    )

    private let refreshIntervals: RefreshIntervals

    public typealias Factory = AppSessionRefresherFactory & VpnKeychainFactory & TimerFactoryCreator
    private let factory: Factory
    private let timerFactory: TimerFactory

    private var timerFullRefresh: BackgroundTimer?
    private var timerLoadsRefresh: BackgroundTimer?
    private var timerAccountRefresh: BackgroundTimer?
    private var timerStreamingRefresh: BackgroundTimer?
    
    private var appSessionRefresher: AppSessionRefresher {
        return factory.makeAppSessionRefresher() // Do not retain it
    }

    private weak var delegate: AppSessionRefreshTimerDelegate?

    public init(
        factory: Factory,
        refreshIntervals: RefreshIntervals,
        delegate: AppSessionRefreshTimerDelegate?
    ) {
        self.factory = factory
        self.timerFactory = factory.makeTimerFactory()
        self.refreshIntervals = refreshIntervals
        self.delegate = delegate
    }
    
    public func startTimers() {
        let refreshes = [
            (\AppSessionRefreshTimerImplementation.timerAccountRefresh, refreshAccount, refreshIntervals.account),
            (\AppSessionRefreshTimerImplementation.timerFullRefresh, refreshFull, refreshIntervals.full),
            (\AppSessionRefreshTimerImplementation.timerLoadsRefresh, refreshLoads, refreshIntervals.loads),
            (\AppSessionRefreshTimerImplementation.timerStreamingRefresh, refreshStreaming, refreshIntervals.streaming)
        ]

        for (timerPath, timerFunction, refreshInterval) in refreshes {
            let timer = self[keyPath: timerPath]

            if timer == nil || !timer!.isValid {
                self[keyPath: timerPath] = timerFactory.scheduledTimer(
                    timeInterval: refreshInterval,
                    repeats: true,
                    queue: .main,
                    timerFunction
                )
            }
        }
    }
    
    public func stopTimers() {
        timerFullRefresh?.invalidate()
        timerLoadsRefresh?.invalidate()
        timerAccountRefresh?.invalidate()
        timerStreamingRefresh?.invalidate()

        timerFullRefresh = nil
        timerLoadsRefresh = nil
        timerAccountRefresh = nil
        timerStreamingRefresh = nil
    }
    
    private func refreshFull() {
        guard let delegate, delegate.shouldRefreshFull() else { return }
        appSessionRefresher.refreshData()
    }
    
    private func refreshLoads() {
        guard let delegate, delegate.shouldRefreshLoads() else { return }
        appSessionRefresher.refreshServerLoads()
    }
    
    private func refreshAccount() {
        guard let delegate, delegate.shouldRefreshAccount() else { return }
        appSessionRefresher.refreshAccount()
    }

    private func refreshStreaming() {
        guard let delegate, delegate.shouldRefreshStreaming() else { return }
        appSessionRefresher.refreshStreamingServices()
    }
}
