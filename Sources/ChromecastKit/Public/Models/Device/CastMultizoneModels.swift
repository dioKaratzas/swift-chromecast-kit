//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// A speaker or device member reported by the Cast multizone namespace.
public struct CastMultizoneMember: Sendable, Hashable, Codable, Identifiable {
    public let id: CastDeviceID
    public let name: String

    public init(id: CastDeviceID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A casting group entry reported by the Cast multizone namespace.
public struct CastCastingGroup: Sendable, Hashable, Codable, Identifiable {
    public let id: CastDeviceID
    public let name: String

    public init(id: CastDeviceID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Latest multizone/group state known for a Cast session.
public struct CastMultizoneStatus: Sendable, Hashable, Codable {
    public let members: [CastMultizoneMember]
    public let castingGroups: [CastCastingGroup]
    public let lastUpdated: Date

    public init(
        members: [CastMultizoneMember] = [],
        castingGroups: [CastCastingGroup] = [],
        lastUpdated: Date = .init()
    ) {
        self.members = members
        self.castingGroups = castingGroups
        self.lastUpdated = lastUpdated
    }
}
