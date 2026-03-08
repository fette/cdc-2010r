//
//  Models.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import Foundation

struct DiscSlot: Codable, Identifiable, Equatable {
    let slotIndex: Int
    var sourceType: String?
    var playlistPersistentID: String?
    var albumTitle: String?
    var artistName: String?
    var playlistName: String?
    var artworkPNGBase64: String?
    var trackIDs: [String]?
    var trackNumbersByID: [String: Int]?
    var youtubeURL: String?

    var id: Int { slotIndex }
    var isLoaded: Bool { playlistPersistentID != nil || youtubeURL != nil }

    init(
        slotIndex: Int,
        sourceType: String? = nil,
        playlistPersistentID: String? = nil,
        albumTitle: String? = nil,
        artistName: String? = nil,
        playlistName: String? = nil,
        artworkPNGBase64: String? = nil,
        trackIDs: [String]? = nil,
        trackNumbersByID: [String: Int]? = nil,
        youtubeURL: String? = nil
    ) {
        self.slotIndex = slotIndex
        self.sourceType = sourceType
        self.playlistPersistentID = playlistPersistentID
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.playlistName = playlistName
        self.artworkPNGBase64 = artworkPNGBase64
        self.trackIDs = trackIDs
        self.trackNumbersByID = trackNumbersByID
        self.youtubeURL = youtubeURL
    }

    var youtubeVideoID: String? {
        guard let youtubeURL else { return nil }
        return Self.extractYouTubeVideoID(from: youtubeURL)
    }

    static func extractYouTubeVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        if let host = url.host, host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first
            return (id?.isEmpty == false) ? id : nil
        }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        if url.path.contains("/embed/") {
            let id = url.pathComponents.last
            return (id?.isEmpty == false && id != "embed") ? id : nil
        }
        return nil
    }

    static func emptySlots() -> [DiscSlot] {
        (1...5).map { DiscSlot(slotIndex: $0) }
    }
}

enum MusicSuggestionKind: String, Hashable {
    case album
    case playlist
    case youtube

    var label: String {
        switch self {
        case .album:
            return "Album"
        case .playlist:
            return "Playlist"
        case .youtube:
            return "YouTube"
        }
    }
}

struct MusicSuggestion: Identifiable, Hashable {
    let kind: MusicSuggestionKind
    let title: String
    let subtitle: String
    let albumTitle: String?
    let artistName: String?
    let playlistPersistentID: String?
    let youtubeURL: String?
    let thumbnailURL: String?

    var id: String {
        switch kind {
        case .album:
            let artist = artistName?.lowercased() ?? ""
            return "album|\(title.lowercased())|\(artist)"
        case .playlist:
            return "playlist|\(playlistPersistentID ?? title.lowercased())"
        case .youtube:
            return "youtube|\(youtubeURL ?? title.lowercased())"
        }
    }

    init(kind: MusicSuggestionKind, title: String, subtitle: String, albumTitle: String? = nil, artistName: String? = nil, playlistPersistentID: String? = nil, youtubeURL: String? = nil, thumbnailURL: String? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.playlistPersistentID = playlistPersistentID
        self.youtubeURL = youtubeURL
        self.thumbnailURL = thumbnailURL
    }
}

struct PlaybackState: Codable, Equatable {
    var activeDiscIndex: Int
    var mode: Mode
    var lidOpen: Bool
    var spiralPosition: SpiralPosition?
    var playAllCursor: PlayAllCursor?

    static func defaultState() -> PlaybackState {
        PlaybackState(
            activeDiscIndex: 1,
            mode: .normal,
            lidOpen: false,
            spiralPosition: nil,
            playAllCursor: nil
        )
    }
}

struct SpiralPosition: Codable, Equatable {
    var trackNumber: Int
    var discCursor: Int
}

struct PlayAllCursor: Codable, Equatable {
    var discIndex: Int
    var trackIndex: Int
}

enum Mode: String, Codable, CaseIterable {
    case normal
    case playAll
    case discRepeat
    case oneDiscShuffle
    case fiveDiscShuffle
    case spiral

    var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .playAll:
            return "Play All"
        case .discRepeat:
            return "Disc Repeat"
        case .oneDiscShuffle:
            return "One-Disc Shuffle"
        case .fiveDiscShuffle:
            return "5-Disc Shuffle"
        case .spiral:
            return "Spiral"
        }
    }
}
