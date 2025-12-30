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
    var artworkPNGBase64: String?
    var trackIDs: [String]?
    var trackNumbersByID: [String: Int]?

    var id: Int { slotIndex }
    var isLoaded: Bool { playlistPersistentID != nil }

    init(
        slotIndex: Int,
        sourceType: String? = nil,
        playlistPersistentID: String? = nil,
        albumTitle: String? = nil,
        artistName: String? = nil,
        artworkPNGBase64: String? = nil,
        trackIDs: [String]? = nil,
        trackNumbersByID: [String: Int]? = nil
    ) {
        self.slotIndex = slotIndex
        self.sourceType = sourceType
        self.playlistPersistentID = playlistPersistentID
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.artworkPNGBase64 = artworkPNGBase64
        self.trackIDs = trackIDs
        self.trackNumbersByID = trackNumbersByID
    }

    static func emptySlots() -> [DiscSlot] {
        (1...5).map { DiscSlot(slotIndex: $0) }
    }
}

struct AlbumSuggestion: Identifiable, Hashable {
    let albumTitle: String
    let artistName: String?

    var id: String {
        let artist = artistName?.lowercased() ?? ""
        return "\(albumTitle.lowercased())|\(artist)"
    }

    var subtitle: String {
        artistName?.isEmpty == false ? artistName! : "Unknown Artist"
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
