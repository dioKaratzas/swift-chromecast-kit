//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Decodes inbound Cast status messages and applies them to session runtime state.
///
/// This processor is transport-agnostic: callers provide `CastInboundMessage` values
/// after protobuf framing is decoded. Known status messages update the state store and
/// synchronize routing/session IDs in commanding controllers.
actor CastStatusMessageProcessor {
    private let stateStore: CastSessionStateStore
    private let dispatcher: CastCommandDispatcher
    private let mediaController: CastMediaController

    init(
        stateStore: CastSessionStateStore,
        dispatcher: CastCommandDispatcher,
        mediaController: CastMediaController
    ) {
        self.stateStore = stateStore
        self.dispatcher = dispatcher
        self.mediaController = mediaController
    }

    /// Applies a supported inbound status message.
    ///
    /// Returns `true` if the message was recognized and applied, otherwise `false`.
    @discardableResult
    func apply(_ message: CastInboundMessage) async throws -> Bool {
        let messageType = try decodeMessageType(from: message.payloadUTF8)

        switch (message.route.namespace, messageType) {
        case (.receiver, CastReceiverMessageType.receiverStatus.rawValue):
            let response = try CastMessageJSONCodec.decodePayload(CastWire.Receiver.StatusResponse.self, from: message)
            let status = mapReceiverStatus(response.status)
            await stateStore.setReceiverStatus(status)
            await dispatcher.setCurrentApplicationTransportID(status?.app?.transportID)
            return true

        case (.media, CastMediaMessageType.mediaStatus.rawValue):
            let response = try CastMessageJSONCodec.decodePayload(CastWire.Media.StatusResponse.self, from: message)
            let status = response.status.first.map(mapMediaStatus(_:))
            await stateStore.setMediaStatus(status)
            await mediaController.setMediaSessionID(status?.mediaSessionID)
            return true

        default:
            return false
        }
    }

    private func decodeMessageType(from payloadUTF8: String) throws -> String {
        let object = try CastMessageJSONCodec.decodePayload([String: JSONValue].self, from: payloadUTF8)
        guard case let .string(type)? = object["type"] else {
            throw CastError.invalidResponse("Missing message type in Cast payload")
        }
        return type
    }
}

private func mapReceiverStatus(_ status: CastWire.Receiver.Status) -> CastReceiverStatus? {
    guard let level = status.volume.level else {
        return nil
    }

    let app = status.applications?.first.map { application in
        CastRunningApp(
            appID: application.appId,
            displayName: application.displayName,
            sessionID: application.sessionId,
            transportID: application.transportId,
            statusText: application.statusText,
            namespaces: application.namespaces?.map(\.name) ?? []
        )
    }

    return CastReceiverStatus(
        volume: .init(level: level, muted: status.volume.muted ?? false),
        app: app,
        isStandBy: status.isStandBy,
        isActiveInput: status.isActiveInput
    )
}

private func mapMediaStatus(_ status: CastWire.Media.Status) -> CastMediaStatus {
    let media = status.media
    let metadata = media?.metadata.flatMap(mapMediaMetadata(_:))
    let tracks = media?.tracks?.compactMap(mapTextTrack(_:)) ?? []

    return CastMediaStatus(
        currentTime: status.currentTime ?? 0,
        duration: media?.duration,
        playbackRate: status.playbackRate ?? 1,
        playerState: status.playerState ?? .unknown,
        idleReason: status.idleReason,
        streamType: media?.streamType ?? .unknown,
        mediaSessionID: status.mediaSessionId,
        contentURL: media?.contentId.flatMap(URL.init(string:)),
        contentType: media?.contentType,
        metadata: metadata,
        textTracks: tracks,
        activeTextTrackIDs: status.activeTrackIds ?? [],
        queueCurrentItemID: status.currentItemId,
        queueLoadingItemID: status.loadingItemId,
        queueRepeatMode: status.repeatMode,
        volume: .init(level: status.volume?.level ?? 1, muted: status.volume?.muted ?? false),
        supportedCommands: .init(rawValue: status.supportedMediaCommands ?? 0),
        lastUpdated: Date()
    )
}

private func mapMediaMetadata(_ metadata: CastWire.Media.Metadata) -> CastMediaMetadata? {
    let images = metadata.images?.compactMap { image -> CastImage? in
        guard let url = URL(string: image.url) else {
            return nil
        }
        return .init(url: url, width: image.width, height: image.height)
    } ?? []

    switch metadata.metadataType {
    case 0:
        return .generic(.init(title: metadata.title, subtitle: metadata.subtitle, images: images))
    case 1:
        return .movie(
            .init(
                title: metadata.title,
                subtitle: metadata.subtitle,
                studio: metadata.studio,
                releaseDate: metadata.releaseDate.flatMap(parseISO8601Date(_:)),
                images: images
            )
        )
    case 2:
        return .tvShow(
            .init(
                title: metadata.title,
                seriesTitle: metadata.seriesTitle,
                season: metadata.season,
                episode: metadata.episode,
                images: images
            )
        )
    case 3:
        return .musicTrack(
            .init(
                title: metadata.title,
                artist: metadata.artist,
                albumName: metadata.albumName,
                albumArtist: metadata.albumArtist,
                trackNumber: metadata.track,
                images: images
            )
        )
    case 4:
        return .photo(.init(title: metadata.title, location: metadata.location, images: images))
    default:
        return nil
    }
}

private func mapTextTrack(_ track: CastWire.Media.Track) -> CastTextTrack? {
    guard let url = URL(string: track.trackContentId) else {
        return nil
    }

    return .init(
        id: track.trackId,
        kind: track.type,
        subtype: track.subtype,
        name: track.name,
        languageCode: track.language,
        contentURL: url,
        contentType: track.trackContentType
    )
}

private func parseISO8601Date(_ value: String) -> Date? {
    ISO8601DateFormatter().date(from: value)
}
