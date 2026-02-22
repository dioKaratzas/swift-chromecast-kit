//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
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
