//
//  VpnCredentials.swift
//  vpncore - Created on 26.06.19.
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

public class VpnCredentials: NSObject, NSCoding {
    public let status: Int
    public let expirationTime: Date
    public let accountPlan: AccountPlan
    public let planName: String?
    public let maxConnect: Int
    public let maxTier: Int
    public let services: Int
    public let groupId: String
    public let name: String
    public let password: String
    public let delinquent: Int
    public let credit: Int
    public let currency: String
    public let hasPaymentMethod: Bool
    
    override public var description: String {
        return
            "Status: \(status)\n" +
            "Expiration time: \(String(describing: expirationTime))\n" +
            "Account plan: \(accountPlan.description) (\(planName)\n" +
            "Max connect: \(maxConnect)\n" +
            "Max tier: \(maxTier)\n" +
            "Services: \(services)\n" +
            "Group ID: \(groupId)\n" +
            "Name: \(name)\n" +
            "Password: \(password)\n" +
            "Delinquent: \(delinquent)\n" +
            "Has Payment Method: \(hasPaymentMethod)"
    }

    public init(status: Int, expirationTime: Date, accountPlan: AccountPlan, maxConnect: Int, maxTier: Int, services: Int, groupId: String, name: String, password: String, delinquent: Int, credit: Int, currency: String, hasPaymentMethod: Bool, planName: String?) {
        self.status = status
        self.expirationTime = expirationTime
        self.accountPlan = accountPlan
        self.maxConnect = maxConnect
        self.maxTier = maxTier
        self.services = services
        self.groupId = groupId
        self.name = name
        self.password = password
        self.delinquent = delinquent
        self.credit = credit
        self.currency = currency
        self.hasPaymentMethod = hasPaymentMethod
        self.planName = planName // Saving original string we got from API, because we need to know if it was null
        super.init()
    }
    
    init(dic: JSONDictionary) throws {
        let vpnDic = try dic.jsonDictionaryOrThrow(key: "VPN")
                
        if let planName = vpnDic.string("PlanName") {
            accountPlan = AccountPlan(planName: planName)
            self.planName = planName
        } else {
            accountPlan = AccountPlan.free
            self.planName = nil
        }
        
        status = try vpnDic.intOrThrow(key: "Status")
        expirationTime = try vpnDic.unixTimestampOrThrow(key: "ExpirationTime")
        maxConnect = try vpnDic.intOrThrow(key: "MaxConnect")
        maxTier = vpnDic.int(key: "MaxTier") ?? 0
        services = try dic.intOrThrow(key: "Services")
        groupId = try vpnDic.stringOrThrow(key: "GroupID")
        name = try vpnDic.stringOrThrow(key: "Name")
        password = try vpnDic.stringOrThrow(key: "Password")
        delinquent = try dic.intOrThrow(key: "Delinquent")
        credit = try dic.intOrThrow(key: "Credit")
        currency = try dic.stringOrThrow(key: "Currency")
        hasPaymentMethod = try dic.boolOrThrow(key: "HasPaymentMethod")
        super.init()
    }
    
    // MARK: - NSCoding
    private struct CoderKey {
        static let status = "status"
        static let expirationTime = "expirationTime"
        static let accountPlan = "accountPlan"
        static let planName = "planName"
        static let maxConnect = "maxConnect"
        static let maxTier = "maxTier"
        static let services = "services"
        static let groupId = "groupId"
        static let name = "name"
        static let password = "password"
        static let delinquent = "delinquent"
        static let credit = "credit"
        static let currency = "currency"
        static let hasPaymentMethod = "hasPaymentMethod"
    }
    
    public required convenience init(coder aDecoder: NSCoder) {
        let plan = AccountPlan(coder: aDecoder)
        self.init(status: aDecoder.decodeInteger(forKey: CoderKey.status),
                  expirationTime: aDecoder.decodeObject(forKey: CoderKey.expirationTime) as! Date,
                  accountPlan: plan,
                  maxConnect: aDecoder.decodeInteger(forKey: CoderKey.maxConnect),
                  maxTier: aDecoder.decodeInteger(forKey: CoderKey.maxTier),
                  services: aDecoder.decodeInteger(forKey: CoderKey.services),
                  groupId: aDecoder.decodeObject(forKey: CoderKey.groupId) as! String,
                  name: aDecoder.decodeObject(forKey: CoderKey.name) as! String,
                  password: aDecoder.decodeObject(forKey: CoderKey.password) as! String,
                  delinquent: aDecoder.decodeInteger(forKey: CoderKey.delinquent),
                  credit: aDecoder.decodeInteger(forKey: CoderKey.credit),
                  currency: aDecoder.decodeObject(forKey: CoderKey.currency) as? String ?? "",
                  hasPaymentMethod: aDecoder.decodeBool(forKey: CoderKey.hasPaymentMethod),
                  planName: aDecoder.decodeObject(forKey: CoderKey.planName) as? String
        )
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(status, forKey: CoderKey.status)
        aCoder.encode(expirationTime, forKey: CoderKey.expirationTime)
        accountPlan.encode(with: aCoder)
        aCoder.encode(maxConnect, forKey: CoderKey.maxConnect)
        aCoder.encode(maxTier, forKey: CoderKey.maxTier)
        aCoder.encode(services, forKey: CoderKey.services)
        aCoder.encode(groupId, forKey: CoderKey.groupId)
        aCoder.encode(name, forKey: CoderKey.name)
        aCoder.encode(password, forKey: CoderKey.password)
        aCoder.encode(delinquent, forKey: CoderKey.delinquent)
        aCoder.encode(credit, forKey: CoderKey.credit)
        aCoder.encode(currency, forKey: CoderKey.currency)
        aCoder.encode(hasPaymentMethod, forKey: CoderKey.hasPaymentMethod)
        aCoder.encode(planName, forKey: CoderKey.planName)
    }
}

extension VpnCredentials {
    public var isDelinquent: Bool {
        return delinquent > 2
    }
}

/// Contains everything that VpnCredentials has, minus the username, password, and group ID.
/// This lets us avoid querying the keychain unnecessarily, since every query results in a synchronous
/// roundtrip to securityd.
public struct CachedVpnCredentials {
    public let status: Int
    public let expirationTime: Date
    public let accountPlan: AccountPlan
    public let planName: String?
    public let maxConnect: Int
    public let maxTier: Int
    public let services: Int
    public let delinquent: Int
    public let credit: Int
    public let currency: String
    public let hasPaymentMethod: Bool
}

extension CachedVpnCredentials {
    init(credentials: VpnCredentials) {
        self.init(status: credentials.status,
                  expirationTime: credentials.expirationTime,
                  accountPlan: credentials.accountPlan,
                  planName: credentials.planName,
                  maxConnect: credentials.maxConnect,
                  maxTier: credentials.maxTier,
                  services: credentials.services,
                  delinquent: credentials.delinquent,
                  credit: credentials.credit,
                  currency: credentials.currency,
                  hasPaymentMethod: credentials.hasPaymentMethod)
    }
}

// MARK: - Checks performed on CachedVpnCredentials
extension CachedVpnCredentials {
    public var hasExpired: Bool {
        return Date().compare(expirationTime) != .orderedAscending
    }

    public var isDelinquent: Bool {
        return delinquent > 2
    }

    public var isSubuserWithoutSessions: Bool {
        return planName == nil && maxConnect <= 1
    }

    public var serviceName: String {
        var name = LocalizedString.unavailable
        if services & 0b001 != 0 {
            name = "ProtonMail"
        } else if services & 0b100 != 0 {
            name = "ProtonVPN"
        }
        return name
    }
}
