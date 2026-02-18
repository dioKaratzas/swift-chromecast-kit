//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

extension CastWire {
    enum Multizone {}
}

extension CastWire.Multizone {
    struct GetStatusRequest: Sendable, Hashable, Codable {
        let type: CastMultizoneMessageType

        init(type: CastMultizoneMessageType = .getStatus) {
            self.type = type
        }
    }

    struct GetCastingGroupsRequest: Sendable, Hashable, Codable {
        let type: CastMultizoneMessageType

        init(type: CastMultizoneMessageType = .getCastingGroups) {
            self.type = type
        }
    }
}

extension CastWire.Multizone {
    struct Device: Sendable, Hashable, Codable {
        let deviceId: CastDeviceID
        let name: String?

        init(deviceId: CastDeviceID, name: String? = nil) {
            self.deviceId = deviceId
            self.name = name
        }
    }

    struct StatusPayload: Sendable, Hashable, Codable {
        let devices: [Device]?

        init(devices: [Device]? = nil) {
            self.devices = devices
        }
    }

    struct StatusResponse: Sendable, Hashable, Codable {
        let type: CastMultizoneMessageType
        let status: StatusPayload

        init(type: CastMultizoneMessageType = .multizoneStatus, status: StatusPayload) {
            self.type = type
            self.status = status
        }
    }
}

extension CastWire.Multizone {
    struct DeviceDeltaResponse: Sendable, Hashable, Codable {
        let type: CastMultizoneMessageType
        let device: Device?
        let deviceId: CastDeviceID?

        init(type: CastMultizoneMessageType, device: Device? = nil, deviceId: CastDeviceID? = nil) {
            self.type = type
            self.device = device
            self.deviceId = deviceId
        }
    }
}

extension CastWire.Multizone {
    struct CastingGroupsResponse: Sendable, Hashable, Codable {
        struct Group: Sendable, Hashable, Codable {
            let deviceId: CastDeviceID?
            let name: String?

            init(deviceId: CastDeviceID? = nil, name: String? = nil) {
                self.deviceId = deviceId
                self.name = name
            }
        }

        struct GroupsStatus: Sendable, Hashable, Codable {
            let groups: [Group]?

            init(groups: [Group]? = nil) {
                self.groups = groups
            }
        }

        let type: CastMultizoneMessageType
        let groups: [Group]?
        let status: GroupsStatus?

        init(
            type: CastMultizoneMessageType = .castingGroups,
            groups: [Group]? = nil,
            status: GroupsStatus? = nil
        ) {
            self.type = type
            self.groups = groups
            self.status = status
        }
    }
}
