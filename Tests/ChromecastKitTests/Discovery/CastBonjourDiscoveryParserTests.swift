//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
@preconcurrency import Network
import Foundation
@testable import ChromecastKit

@Suite("Bonjour Discovery Parser")
struct CastBonjourDiscoveryParserTests {
    @Test("extracts service identity from bonjour service endpoint")
    func serviceIdentity() {
        let endpoint = NWEndpoint.service(
            name: "Living Room",
            type: "_googlecast._tcp",
            domain: "local",
            interface: nil
        )

        let identity = CastBonjourDiscoveryParser.serviceIdentity(from: endpoint)

        #expect(identity == .init(name: "Living Room", type: "_googlecast._tcp", domain: "local"))
    }

    @Test("maps TXT metadata to device descriptor and capabilities")
    func deviceDescriptorFromTXT() {
        let descriptor = CastBonjourDiscoveryParser.deviceDescriptor(
            serviceName: "Living Room",
            resolvedEndpoint: .init(host: "Living-Room.local.", port: 8009),
            txt: [
                "id": "abcd1234",
                "fn": "Living Room TV",
                "md": "Chromecast Ultra",
                "ca": "5",
            ]
        )

        #expect(descriptor.id == "abcd1234")
        #expect(descriptor.friendlyName == "Living Room TV")
        #expect(descriptor.host == "Living-Room.local")
        #expect(descriptor.port == 8009)
        #expect(descriptor.modelName == "Chromecast Ultra")
        #expect(descriptor.capabilities.contains(.video))
        #expect(descriptor.capabilities.contains(.audio))
        #expect(!descriptor.capabilities.contains(.group))
    }

    @Test("group devices are inferred and can be filtered")
    func groupFiltering() {
        let descriptor = CastBonjourDiscoveryParser.deviceDescriptor(
            serviceName: "Whole Home",
            resolvedEndpoint: .init(host: "whole-home.local", port: 8009),
            txt: [
                "fn": "Whole Home Group",
                "md": "Google Cast Group",
                "ca": "32",
            ]
        )

        #expect(descriptor.capabilities.contains(.group))
        #expect(descriptor.capabilities.contains(.multizone))
        #expect(!CastBonjourDiscoveryParser.shouldInclude(descriptor, includeGroups: false))
        #expect(CastBonjourDiscoveryParser.shouldInclude(descriptor, includeGroups: true))
    }

    @Test("reads TXT dictionary from NWBrowser bonjour metadata")
    func txtDictionaryFromMetadata() {
        let metadata = NWBrowser.Result.Metadata.bonjour(
            NWTXTRecord(["id": "device-1", "fn": "Kitchen"])
        )

        let txt = CastBonjourDiscoveryParser.txtDictionary(from: metadata)

        #expect(txt["id"] == "device-1")
        #expect(txt["fn"] == "Kitchen")
    }
}
