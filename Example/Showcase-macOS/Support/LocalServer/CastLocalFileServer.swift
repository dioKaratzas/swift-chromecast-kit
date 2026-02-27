//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

@preconcurrency import Swifter
import Foundation
import ChromecastKit

/// A lightweight local HTTP server for demo/testing flows that need to expose local media files to Chromecast devices.
///
/// Chromecast devices fetch media and subtitle URLs directly, so local files must be hosted on a reachable LAN URL.
/// This helper is primarily intended for examples and developer tooling.
public actor CastLocalFileServer {
    /// URLs for the currently hosted local media assets.
    public struct HostedMedia: Sendable, Hashable {
        public let baseURL: URL
        public let videoURL: URL
        public let subtitleURL: URL?

        public init(baseURL: URL, videoURL: URL, subtitleURL: URL?) {
            self.baseURL = baseURL
            self.videoURL = videoURL
            self.subtitleURL = subtitleURL
        }
    }

    private enum HostedName {
        static let videoPrefix = "video"
        static let subtitlePrefix = "subtitle"
    }

    private var server: HttpServer?
    private var rootDirectoryURL: URL?
    private var assetsDirectoryURL: URL?
    private var baseURL: URL?
    private var currentHostedMedia: HostedMedia?

    public init() {}

    /// Starts the HTTP server.
    ///
    /// - Parameters:
    ///   - publicHost: Host/IP address reachable by the Chromecast (for example your Mac's LAN IP).
    ///   - port: HTTP port to bind.
    ///   - bindHostIPv4: Local bind address (`0.0.0.0` is typical for LAN access).
    /// - Returns: The base URL for hosted files.
    @discardableResult
    public func start(
        publicHost: String,
        port: UInt16 = 8081,
        bindHostIPv4: String = "0.0.0.0"
    ) throws -> URL {
        let host = publicHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard host.isEmpty == false else {
            throw CastError.invalidArgument("Local server public host is required")
        }

        if let currentBaseURL = baseURL,
           let currentServer = server,
           currentServer.operating,
           currentBaseURL.host == host,
           currentBaseURL.port == Int(port) {
            return currentBaseURL
        }

        stop()

        let directoryURL = try createHostingDirectory()
        let assetsDirectoryURL = directoryURL.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assetsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let assetsDirectoryPath = assetsDirectoryURL.path

        let httpServer = HttpServer()
        httpServer.listenAddressIPv4 = bindHostIPv4
        httpServer.middleware.append { request in
            guard request.method.uppercased() == "OPTIONS" else {
                return nil
            }
            return .raw(204, "No Content", Self.corsHeaders(), nil)
        }

        httpServer["/assets/:path"] = { request in
            Self.makeStaticAssetResponse(request: request, assetsDirectoryPath: assetsDirectoryPath)
        }

        try httpServer.start(in_port_t(port), forceIPv4: true)

        let resolvedPort = try httpServer.port()
        let serverBaseURL = URL(string: "http://\(host):\(resolvedPort)")!

        server = httpServer
        rootDirectoryURL = directoryURL
        self.assetsDirectoryURL = assetsDirectoryURL
        baseURL = serverBaseURL
        currentHostedMedia = nil
        return serverBaseURL
    }

    /// Stops the HTTP server and clears transient hosted files.
    public func stop() {
        server?.stop()
        server = nil
        currentHostedMedia = nil
        baseURL = nil
        assetsDirectoryURL = nil
        if let rootDirectoryURL {
            try? FileManager.default.removeItem(at: rootDirectoryURL)
        }
        rootDirectoryURL = nil
    }

    /// Returns whether the server is currently running.
    public func isRunning() -> Bool {
        server?.operating == true
    }

    /// The currently hosted URLs, if files were published after startup.
    public func hostedMedia() -> HostedMedia? {
        currentHostedMedia
    }

    /// Publishes local files and returns LAN-reachable URLs for Chromecast playback.
    ///
    /// The server must already be started.
    public func host(
        videoFileURL: URL,
        subtitleFileURL: URL? = nil
    ) throws -> HostedMedia {
        guard let baseURL, let assetsDirectoryURL else {
            throw CastError.disconnected
        }

        guard videoFileURL.isFileURL else {
            throw CastError.invalidArgument("Video URL must be a local file URL")
        }
        let videoName = makeHostedName(prefix: HostedName.videoPrefix, sourceURL: videoFileURL, fallbackExtension: "mp4")
        try removeFiles(in: assetsDirectoryURL, matchingPrefix: HostedName.videoPrefix)
        let hostedVideoURL = assetsDirectoryURL.appendingPathComponent(videoName)
        try linkOrCopyFile(from: videoFileURL, to: hostedVideoURL)

        let publicSubtitleURL = try publishSubtitleFile(
            subtitleFileURL,
            assetsDirectoryURL: assetsDirectoryURL,
            baseURL: baseURL
        )

        let media = HostedMedia(
            baseURL: baseURL,
            videoURL: baseURL.appendingPathComponent("assets").appendingPathComponent(videoName),
            subtitleURL: publicSubtitleURL
        )
        currentHostedMedia = media
        return media
    }

    /// Updates or removes the hosted subtitle file while keeping the server running and the current video URL intact.
    ///
    /// - Parameter subtitleFileURL: New local subtitle file URL, or `nil` to remove the hosted subtitle.
    /// - Returns: Updated hosted media URLs.
    @discardableResult
    public func updateSubtitleFile(_ subtitleFileURL: URL?) throws -> HostedMedia {
        guard let baseURL, let assetsDirectoryURL, var currentHostedMedia else {
            throw CastError.disconnected
        }

        let publicSubtitleURL = try publishSubtitleFile(
            subtitleFileURL,
            assetsDirectoryURL: assetsDirectoryURL,
            baseURL: baseURL
        )
        currentHostedMedia = HostedMedia(
            baseURL: currentHostedMedia.baseURL,
            videoURL: currentHostedMedia.videoURL,
            subtitleURL: publicSubtitleURL
        )
        self.currentHostedMedia = currentHostedMedia
        return currentHostedMedia
    }

    private func createHostingDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChromecastKit-LocalFileServer", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        return root
    }

    private func makeHostedName(prefix: String, sourceURL: URL, fallbackExtension: String) -> String {
        let pathExtension = sourceURL.pathExtension.isEmpty ? fallbackExtension : sourceURL.pathExtension
        return "\(prefix).\(pathExtension)"
    }

    private func linkOrCopyFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
        } catch {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func publishSubtitleFile(
        _ subtitleFileURL: URL?,
        assetsDirectoryURL: URL,
        baseURL: URL
    ) throws -> URL? {
        try removeFiles(in: assetsDirectoryURL, matchingPrefix: HostedName.subtitlePrefix)

        guard let subtitleFileURL else {
            return nil
        }

        guard subtitleFileURL.isFileURL else {
            throw CastError.invalidArgument("Subtitle URL must be a local file URL")
        }

        let subtitleName = makeHostedName(
            prefix: HostedName.subtitlePrefix,
            sourceURL: subtitleFileURL,
            fallbackExtension: "vtt"
        )
        let hostedSubtitleURL = assetsDirectoryURL.appendingPathComponent(subtitleName)
        try linkOrCopyFile(from: subtitleFileURL, to: hostedSubtitleURL)
        return baseURL.appendingPathComponent("assets").appendingPathComponent(subtitleName)
    }

    private func removeFiles(in directoryURL: URL, matchingPrefix prefix: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }
        let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in contents where url.lastPathComponent.hasPrefix("\(prefix).") {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func corsHeaders() -> [String: String] {
        [
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
            "Access-Control-Allow-Headers": "Origin, Accept, Content-Type, Range",
            "Access-Control-Expose-Headers": "Content-Length, Content-Type, Content-Range, Accept-Ranges",
        ]
    }

    private static func makeStaticAssetResponse(request: HttpRequest, assetsDirectoryPath: String) -> HttpResponse {
        let method = request.method.uppercased()
        guard method == "GET" || method == "HEAD" else {
            return .raw(
                405,
                "Method Not Allowed",
                corsHeaders().merging(["Allow": "GET, HEAD, OPTIONS"]) { _, new in new },
                nil
            )
        }

        guard let requestedPath = request.params[":path"], requestedPath.isEmpty == false else {
            return .notFound.addingHeaders(corsHeaders())
        }

        let fileName = URL(fileURLWithPath: requestedPath).lastPathComponent
        guard fileName.isEmpty == false else {
            return .notFound.addingHeaders(corsHeaders())
        }

        let fileURL = URL(fileURLWithPath: assetsDirectoryPath, isDirectory: true).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .notFound.addingHeaders(corsHeaders())
        }

        let resolvedFileURL = fileURL.resolvingSymlinksInPath()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedFileURL.path),
              let fileSize = attributes[.size] as? UInt64 else {
            return .internalServerError.addingHeaders(corsHeaders())
        }

        let mimeType = mimeType(for: fileURL)
        let rangeHeader = request.headers["range"]

        if let rangeHeader, fileSize > 0 {
            switch parseSingleRangeHeader(rangeHeader, fileSize: fileSize) {
            case let .success(byteRange):
                return rangedFileResponse(
                    fileURL: resolvedFileURL,
                    fileSize: fileSize,
                    byteRange: byteRange,
                    mimeType: mimeType,
                    includeBody: method == "GET"
                )
            case .unsatisfiable:
                var headers = corsHeaders()
                headers["Content-Range"] = "bytes */\(fileSize)"
                headers["Accept-Ranges"] = "bytes"
                headers["Content-Type"] = mimeType
                headers["Content-Length"] = "0"
                return .raw(416, "Range Not Satisfiable", headers, nil)
            case .unsupported:
                break
            }
        }

        return fullFileResponse(
            fileURL: resolvedFileURL,
            fileSize: fileSize,
            mimeType: mimeType,
            includeBody: method == "GET"
        )
    }

    private static func fullFileResponse(
        fileURL: URL,
        fileSize: UInt64,
        mimeType: String,
        includeBody: Bool
    ) -> HttpResponse {
        var headers = corsHeaders()
        headers["Content-Type"] = mimeType
        headers["Content-Length"] = String(fileSize)
        headers["Accept-Ranges"] = "bytes"

        guard includeBody else {
            return .raw(200, "OK", headers, nil)
        }

        return .raw(200, "OK", headers) { writer in
            try writeFile(fileURL: fileURL, offset: 0, length: fileSize, to: writer)
        }
    }

    private static func rangedFileResponse(
        fileURL: URL,
        fileSize: UInt64,
        byteRange: ClosedRange<UInt64>,
        mimeType: String,
        includeBody: Bool
    ) -> HttpResponse {
        let length = byteRange.upperBound - byteRange.lowerBound + 1
        var headers = corsHeaders()
        headers["Content-Type"] = mimeType
        headers["Accept-Ranges"] = "bytes"
        headers["Content-Length"] = String(length)
        headers["Content-Range"] = "bytes \(byteRange.lowerBound)-\(byteRange.upperBound)/\(fileSize)"

        guard includeBody else {
            return .raw(206, "Partial Content", headers, nil)
        }

        return .raw(206, "Partial Content", headers) { writer in
            try writeFile(fileURL: fileURL, offset: byteRange.lowerBound, length: length, to: writer)
        }
    }

    private static func writeFile(
        fileURL: URL,
        offset: UInt64,
        length: UInt64,
        to writer: HttpResponseBodyWriter
    ) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        var remaining = length
        let chunkSize = 64 * 1024
        while remaining > 0 {
            let readCount = Int(min(remaining, UInt64(chunkSize)))
            let data = handle.readData(ofLength: readCount)
            if data.isEmpty {
                break
            }
            try writer.write(data)
            remaining -= UInt64(data.count)
        }
    }

    private enum ParsedRangeHeader {
        case success(ClosedRange<UInt64>)
        case unsatisfiable
        case unsupported
    }

    private static func parseSingleRangeHeader(_ header: String, fileSize: UInt64) -> ParsedRangeHeader {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes=") else {
            return .unsupported
        }
        let spec = String(trimmed.dropFirst("bytes=".count))
        guard spec.contains(",") == false else {
            return .unsupported
        } // single-range only for demo

        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return .unsupported
        }

        let lowerPart = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let upperPart = String(parts[1]).trimmingCharacters(in: .whitespaces)

        if lowerPart.isEmpty {
            // suffix-byte-range-spec: bytes=-500
            guard let suffixLength = UInt64(upperPart), suffixLength > 0 else {
                return .unsupported
            }
            guard fileSize > 0 else {
                return .unsatisfiable
            }
            let actualLength = min(suffixLength, fileSize)
            let start = fileSize - actualLength
            let end = fileSize - 1
            return .success(start ... end)
        }

        guard let start = UInt64(lowerPart) else {
            return .unsupported
        }
        guard start < fileSize else {
            return .unsatisfiable
        }

        let end: UInt64
        if upperPart.isEmpty {
            end = fileSize - 1
        } else if let parsedEnd = UInt64(upperPart) {
            end = min(parsedEnd, fileSize - 1)
        } else {
            return .unsupported
        }

        guard start <= end else {
            return .unsatisfiable
        }
        return .success(start ... end)
    }

    private static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "vtt":
            "text/vtt; charset=utf-8"
        case "mp4", "m4v":
            "video/mp4"
        case "webm":
            "video/webm"
        case "mov":
            "video/quicktime"
        case "mp3":
            "audio/mpeg"
        case "m4a":
            "audio/mp4"
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        default:
            "application/octet-stream"
        }
    }
}

private extension HttpResponse {
    func addingHeaders(_ extraHeaders: [String: String]) -> HttpResponse {
        switch self {
        case let .raw(statusCode, reasonPhrase, headers, body):
            var mergedHeaders = headers ?? [:]
            for (key, value) in extraHeaders {
                mergedHeaders[key] = value
            }
            return .raw(statusCode, reasonPhrase, mergedHeaders, body)
        default:
            return self
        }
    }
}
