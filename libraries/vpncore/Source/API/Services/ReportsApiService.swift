//
//  ReportsApiService.swift
//  vpncore - Created on 01/07/2019.
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

import Foundation

public protocol ReportsApiServiceFactory {
    func makeReportsApiService() -> ReportsApiService
}

public class ReportsApiService {
    
    private let networking: Networking
    
    public init(networking: Networking) {
        self.networking = networking
    }
    
    public func report(bug: ReportBug, success: @escaping SuccessCallback, failure: @escaping ErrorCallback) {
        
        var i = 0
        var files = [String: URL]()
        for file in bug.files.reachable() {
            files["File\(i)"] = file
            i += 1
        }
        
        let request = ReportsBugRequest(bug)
        #warning("FIX ME")
        failure(NSError(code: 0, localizedDescription: "Waiting for Core upload implementation"))
    }
}
