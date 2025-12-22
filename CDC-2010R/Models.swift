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
    var artworkPNGBase64: String?
    var trackIDs: [String]?

    var id: Int { slotIndex }
    var isLoaded: Bool { playlistPersistentID != nil }

    init(
        slotIndex: Int,
        sourceType: String? = nil,
        playlistPersistentID: String? = nil,
        artworkPNGBase64: String? = nil,
        trackIDs: [String]? = nil
    ) {
        self.slotIndex = slotIndex
        self.sourceType = sourceType
        self.playlistPersistentID = playlistPersistentID
        self.artworkPNGBase64 = artworkPNGBase64
        self.trackIDs = trackIDs
    }

    static func emptySlots() -> [DiscSlot] {
        (1...5).map { DiscSlot(slotIndex: $0) }
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
