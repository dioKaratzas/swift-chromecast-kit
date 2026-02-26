//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

actor CastYouTubeMDXWebSession {
    private enum Constants {
        static let youtubeBaseURL = URL(string: "https://www.youtube.com/")!
        static let bindURL = URL(string: "https://www.youtube.com/api/lounge/bc/bind")!
        static let loungeTokenBatchURL = URL(string: "https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch")!

        static let loungeTokenHeader = "X-YouTube-LoungeId-Token"

        static let sidRegex = #""c","(.*?)","#
        static let gsessionRegex = #""S","(.*?)"\]"#

        static let commonHeaders = [
            "Origin": "https://www.youtube.com/",
            "Content-Type": "application/x-www-form-urlencoded",
        ]

        static let bindData = [
            "device": "REMOTE_CONTROL",
            "id": "aaaaaaaaaaaaaaaaaaaaaaaaaa",
            "name": "ChromecastKit",
            "mdx-version": "3",
            "pairing_type": "cast",
            "app": "ios",
        ]
    }

    private let httpClient: any CastYouTubeHTTPClient
    private var timeout: TimeInterval

    private var screenID: String?
    private var loungeToken: String?
    private var gsessionID: String?
    private var sid: String?
    private var rid = 0
    private var requestCount = 0

    init(
        httpClient: any CastYouTubeHTTPClient,
        timeout: TimeInterval
    ) {
        self.httpClient = httpClient
        self.timeout = timeout
    }

    func setTimeout(_ newValue: TimeInterval) {
        timeout = newValue
    }

    func reset() {
        loungeToken = nil
        gsessionID = nil
        sid = nil
        rid = 0
        requestCount = 0
    }

    func setScreenID(_ newValue: String?) {
        guard screenID != newValue else {
            return
        }
        screenID = newValue
        reset()
    }

    func playVideo(
        videoID: String,
        playlistID: String?,
        startTimeSeconds: String
    ) async throws {
        try requireNonEmpty(videoID, name: "videoID")
        try await startSession()
        try await initializeQueue(
            videoID: videoID,
            playlistID: playlistID ?? "",
            startTimeSeconds: startTimeSeconds
        )
    }

    func addToQueue(videoID: String) async throws {
        try requireNonEmpty(videoID, name: "videoID")
        try await queueAction(videoID: videoID, action: "addVideo")
    }

    func playNext(videoID: String) async throws {
        try requireNonEmpty(videoID, name: "videoID")
        try await queueAction(videoID: videoID, action: "insertVideo")
    }

    func removeVideo(videoID: String) async throws {
        try requireNonEmpty(videoID, name: "videoID")
        try await queueAction(videoID: videoID, action: "removeVideo")
    }

    func clearPlaylist() async throws {
        try await queueAction(videoID: "", action: "clearPlaylist")
    }

    // MARK: Session Flow (casttube / pychromecast-style)

    private func startSession() async throws {
        try await getLoungeToken()
        try await bind()
    }

    private func getLoungeToken() async throws {
        let screenID = try requireScreenID()

        let response = try await doPost(
            .init(
                url: Constants.loungeTokenBatchURL,
                headers: Constants.commonHeaders,
                form: ["screen_ids": screenID]
            ),
            sessionRequest: false
        )

        struct LoungeTokenBatchResponse: Decodable, Sendable {
            struct Screen: Decodable, Sendable {
                let loungeToken: String
            }

            let screens: [Screen]
        }

        let decoded: LoungeTokenBatchResponse
        do {
            decoded = try JSONDecoder().decode(LoungeTokenBatchResponse.self, from: response.body)
        } catch {
            throw CastError.invalidResponse("Failed decoding YouTube lounge token batch response")
        }

        guard let loungeToken = decoded.screens.first?.loungeToken, loungeToken.isEmpty == false else {
            throw CastError.invalidResponse("YouTube lounge token batch response did not include a lounge token")
        }

        self.loungeToken = loungeToken
    }

    private func bind() async throws {
        let loungeToken = try requireLoungeToken()

        rid = 0
        requestCount = 0

        let response = try await doPost(
            .init(
                url: Constants.bindURL,
                query: [
                    .init(name: "RID", value: String(rid)),
                    .init(name: "VER", value: "8"),
                    .init(name: "CVER", value: "1"),
                ],
                headers: Constants.commonHeaders.merging(
                    [Constants.loungeTokenHeader: loungeToken],
                    uniquingKeysWith: { _, new in new }
                ),
                form: Constants.bindData
            ),
            sessionRequest: false
        )

        let content = String(decoding: response.body, as: UTF8.self)

        guard let sid = content.firstRegexCapture(Constants.sidRegex) else {
            throw CastError.invalidResponse("YouTube bind response did not include SID")
        }
        guard let gsessionID = content.firstRegexCapture(Constants.gsessionRegex) else {
            throw CastError.invalidResponse("YouTube bind response did not include gsessionid")
        }

        self.sid = sid
        self.gsessionID = gsessionID
    }

    private func initializeQueue(
        videoID: String,
        playlistID: String,
        startTimeSeconds: String
    ) async throws {
        let loungeToken = try requireLoungeToken()
        let sid = try requireSID()
        let gsessionID = try requireGSessionID()

        let requestData = formatSessionRequestForm([
            "_listId": playlistID,
            "__sc": "setPlaylist",
            "_currentTime": startTimeSeconds,
            "_currentIndex": "-1",
            "_audioOnly": "false",
            "_videoId": videoID,
            "count": "1",
        ])

        _ = try await doPost(
            .init(
                url: Constants.bindURL,
                query: [
                    .init(name: "SID", value: sid),
                    .init(name: "gsessionid", value: gsessionID),
                    .init(name: "RID", value: String(rid)),
                    .init(name: "VER", value: "8"),
                    .init(name: "CVER", value: "1"),
                ],
                headers: Constants.commonHeaders.merging(
                    [Constants.loungeTokenHeader: loungeToken],
                    uniquingKeysWith: { _, new in new }
                ),
                form: requestData
            ),
            sessionRequest: true
        )
    }

    private func queueAction(videoID: String, action: String) async throws {
        if inSession == false {
            try await startSession()
        } else {
            try await bind()
        }

        let loungeToken = try requireLoungeToken()
        let sid = try requireSID()
        let gsessionID = try requireGSessionID()

        let requestData = formatSessionRequestForm([
            "__sc": action,
            "_videoId": videoID,
            "count": "1",
        ])

        _ = try await doPost(
            .init(
                url: Constants.bindURL,
                query: [
                    .init(name: "SID", value: sid),
                    .init(name: "gsessionid", value: gsessionID),
                    .init(name: "RID", value: String(rid)),
                    .init(name: "VER", value: "8"),
                    .init(name: "CVER", value: "1"),
                ],
                headers: Constants.commonHeaders.merging(
                    [Constants.loungeTokenHeader: loungeToken],
                    uniquingKeysWith: { _, new in new }
                ),
                form: requestData
            ),
            sessionRequest: true
        )
    }

    // MARK: Helpers

    private var inSession: Bool {
        loungeToken != nil && gsessionID != nil && sid != nil
    }

    private func formatSessionRequestForm(_ form: [String: String]) -> [String: String] {
        let prefix = "req\(requestCount)"
        var result = [String: String]()
        result.reserveCapacity(form.count)

        for (key, value) in form {
            if key.hasPrefix("_") {
                result["\(prefix)\(key)"] = value
            } else {
                result[key] = value
            }
        }

        return result
    }

    private func doPost(
        _ request: CastYouTubeHTTPRequest,
        sessionRequest: Bool
    ) async throws -> CastYouTubeHTTPResponse {
        let response = try await httpClient.post(request, timeout: timeout)

        if sessionRequest, response.statusCode == 400 || response.statusCode == 404 {
            try await bind()
        }

        guard (200 ... 299).contains(response.statusCode) else {
            let message = String(decoding: response.body.prefix(512), as: UTF8.self)
            throw CastError.requestFailed(
                code: response.statusCode,
                message: message.isEmpty ? "YouTube MDX request failed" : message
            )
        }

        if sessionRequest {
            requestCount += 1
        }
        rid += 1

        return response
    }

    private func requireScreenID() throws -> String {
        guard let screenID, screenID.isEmpty == false else {
            throw CastError.invalidArgument("YouTube screen ID is unavailable")
        }
        return screenID
    }

    private func requireLoungeToken() throws -> String {
        guard let loungeToken, loungeToken.isEmpty == false else {
            throw CastError.invalidResponse("YouTube lounge token is unavailable")
        }
        return loungeToken
    }

    private func requireSID() throws -> String {
        guard let sid, sid.isEmpty == false else {
            throw CastError.invalidResponse("YouTube SID is unavailable")
        }
        return sid
    }

    private func requireGSessionID() throws -> String {
        guard let gsessionID, gsessionID.isEmpty == false else {
            throw CastError.invalidResponse("YouTube gsessionid is unavailable")
        }
        return gsessionID
    }

    private func requireNonEmpty(_ value: String, name: String) throws {
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw CastError.invalidArgument("\(name) must not be empty")
        }
    }
}

private extension String {
    func firstRegexCapture(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[captureRange])
    }
}
