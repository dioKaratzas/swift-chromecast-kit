//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Testing
import Foundation
@testable import ChromecastKit

@Suite("SSDP Discovery Parser")
struct CastSSDPDiscoveryParserTests {
    @Test("parses DIAL SSDP search response headers")
    func parseSearchResponse() throws {
        let data = Data(#"""
        HTTP/1.1 200 OK
        CACHE-CONTROL: max-age=1800
        LOCATION: http://192.168.1.25:8008/ssdp/device-desc.xml
        ST: urn:dial-multiscreen-org:service:dial:1
        USN: uuid:12345678-1234-1234-1234-1234567890AB::urn:dial-multiscreen-org:service:dial:1

        """#.utf8)

        let response = try #require(CastSSDPDiscoveryParser.parseSearchResponse(data))
        #expect(response.locationURL.absoluteString == "http://192.168.1.25:8008/ssdp/device-desc.xml")
        #expect(CastSSDPDiscoveryParser.isDialResponse(response))
        #expect(response.cacheMaxAge == 1800)
    }

    @Test("parses cache-control max-age with additional directives")
    func parseSearchResponseCacheControlVariants() throws {
        let data = Data(#"""
        HTTP/1.1 200 OK
        CACHE-CONTROL: public, max-age=900, must-revalidate
        LOCATION: http://192.168.1.30:8008/ssdp/device-desc.xml
        ST: urn:dial-multiscreen-org:service:dial:1

        """#.utf8)

        let response = try #require(CastSSDPDiscoveryParser.parseSearchResponse(data))
        #expect(response.cacheMaxAge == 900)
    }

    @Test("DIAL XML parsing supports namespaced element names")
    func parseNamespacedDialXML() throws {
        let xml = Data(#"""
        <?xml version="1.0"?>
        <root xmlns:d="urn:schemas-upnp-org:device-1-0">
          <d:device>
            <d:friendlyName>Bedroom TV</d:friendlyName>
            <d:manufacturer>Google</d:manufacturer>
            <d:modelName>Chromecast</d:modelName>
            <d:UDN>uuid:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee</d:UDN>
          </d:device>
        </root>
        """#.utf8)

        let description = try #require(CastSSDPDiscoveryParser.parseDIALDeviceDescription(xml))
        #expect(description.friendlyName == "Bedroom TV")
        #expect(description.modelName == "Chromecast")
        #expect(description.uuid == UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    @Test("parses DIAL device description XML and maps descriptor")
    func parseDialXMLAndDescriptor() throws {
        let xml = Data(#"""
        <?xml version="1.0"?>
        <root>
          <device>
            <friendlyName>Kitchen speaker</friendlyName>
            <manufacturer>Google Inc.</manufacturer>
            <modelName>Google Cast Group</modelName>
            <UDN>uuid:12345678-1234-1234-1234-1234567890ab</UDN>
          </device>
        </root>
        """#.utf8)
        let response = try CastSSDPDiscoveryParser.Response(
            locationURL: #require(URL(string: "http://192.168.1.25:8008/ssdp/device-desc.xml")),
            usn: nil,
            searchTarget: CastSSDPDiscoveryParser.dialSearchTarget,
            cacheMaxAge: nil
        )
        let description = try #require(CastSSDPDiscoveryParser.parseDIALDeviceDescription(xml))
        let descriptor = try #require(
            CastSSDPDiscoveryParser.makeDescriptor(from: response, description: description, includeGroups: true)
        )

        #expect(descriptor.friendlyName == "Kitchen speaker")
        #expect(descriptor.host == "192.168.1.25")
        #expect(descriptor.port == 8008)
        #expect(descriptor.modelName == "Google Cast Group")
        #expect(descriptor.uuid == UUID(uuidString: "12345678-1234-1234-1234-1234567890ab"))
        #expect(descriptor.capabilities.contains(.group))
        #expect(descriptor.capabilities.contains(.multizone))
    }
}
