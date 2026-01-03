//
//  AppState.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import AppKit
import Combine
import Foundation

final class AppState: ObservableObject {
    @Published var discSlots: [DiscSlot]
    @Published var playback: PlaybackState
    @Published var statusMessage: String?
    @Published var nowPlayingDiscIndex: Int?
    @Published var nowPlayingTrackNumber: Int?
    @Published var nowPlayingElapsedSeconds: TimeInterval?
    let ledFontName: String

    private var cancellables = Set<AnyCancellable>()
    private let stateURL: URL
    private var nowPlayingTimer: AnyCancellable?

    init(ledFontName: String = "16SegmentsBasic") {
        self.ledFontName = ledFontName
        self.stateURL = AppState.defaultStateURL()
        if let loaded = AppState.loadState(from: stateURL) {
            self.discSlots = AppState.normalizedSlots(from: loaded.discSlots)
            self.playback = AppState.normalizedPlayback(from: loaded.playback)
        } else {
            self.discSlots = DiscSlot.emptySlots()
            self.playback = PlaybackState.defaultState()
        }

        Publishers.CombineLatest($discSlots, $playback)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveState()
            }
            .store(in: &cancellables)

        nowPlayingTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshNowPlayingDisc()
            }
    }

    func setActiveDisc(_ index: Int) {
        playback.activeDiscIndex = index
    }

    func toggleLid() {
        playback.lidOpen.toggle()
    }

    func loadDisc(slotIndex: Int) {
        statusMessage = "Loading from Music..."
        _ = MusicController.shared.requestAutomationPermission()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.loadCurrentAlbumOrPlaylist()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.updateSlot(slotIndex: slotIndex, with: loaded)
                    self.statusMessage = "Loaded Disc \(slotIndex)."
                case .failure(let error):
                    #if DEBUG
                    self.statusMessage = [error.errorDescription, MusicController.shared.diagnostics()]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    #else
                    self.statusMessage = error.errorDescription
                    #endif
                }
            }
        }
    }

    func loadAlbum(slotIndex: Int, album: AlbumSuggestion) {
        statusMessage = "Loading \(album.albumTitle)..."
        _ = MusicController.shared.requestAutomationPermission()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.loadAlbum(albumTitle: album.albumTitle, artistName: album.artistName)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.updateSlot(slotIndex: slotIndex, with: loaded)
                    self.statusMessage = "Loaded Disc \(slotIndex)."
                case .failure(let error):
                    #if DEBUG
                    self.statusMessage = [error.errorDescription, MusicController.shared.diagnostics()]
                        .compactMap { $0 }
                        .joined(separator: " ")
                    #else
                    self.statusMessage = error.errorDescription
                    #endif
                }
            }
        }
    }

    func searchAlbums(matching query: String, completion: @escaping ([AlbumSuggestion]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completion([])
            return
        }
        _ = MusicController.shared.requestAutomationPermission()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.searchAlbums(matching: trimmed, limit: 12)
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(let suggestions):
                    completion(suggestions)
                case .failure(let error):
                    self?.statusMessage = error.errorDescription
                    completion([])
                }
            }
        }
    }

    func removeDisc(slotIndex: Int) {
        guard let slotPosition = discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        discSlots[slotPosition] = DiscSlot(slotIndex: slotIndex)
        if nowPlayingDiscIndex == slotIndex {
            nowPlayingDiscIndex = nil
        }
        statusMessage = "Removed Disc \(slotIndex)."
    }

    func pasteArtwork(slotIndex: Int) {
        guard let slotPosition = discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
              let data = image.pngData() else {
            statusMessage = "Clipboard has no image."
            return
        }
        var slot = discSlots[slotPosition]
        slot.artworkPNGBase64 = data.base64EncodedString()
        discSlots[slotPosition] = slot
        statusMessage = "Pasted artwork for Disc \(slotIndex)."
    }

    func playDisc(slotIndex: Int) {
        guard let slot = discSlots.first(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        guard let trackIDs = slot.trackIDs, !trackIDs.isEmpty else {
            statusMessage = "Load a disc before playing."
            return
        }
        statusMessage = "Starting Disc \(slotIndex)..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.playDisc(trackIDs: trackIDs, discIndex: slotIndex)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.playback.activeDiscIndex = slotIndex
                case .failure(let error):
                    self.statusMessage = error.errorDescription
                }
            }
        }
    }

    func playAllDiscsShuffled() {
        let allTrackIDs = discSlots.compactMap { $0.trackIDs }.flatMap { $0 }
        guard !allTrackIDs.isEmpty else {
            statusMessage = "Load discs before shuffling."
            return
        }
        statusMessage = "Shuffling all discs..."
        let shuffled = allTrackIDs.shuffled()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.playTrackList(
                trackIDs: shuffled,
                playlistName: "CDC-2010R All-Disc Shuffle"
            )
            DispatchQueue.main.async { [weak self] in
                if case .failure(let error) = result {
                    self?.statusMessage = error.errorDescription
                }
            }
        }
    }

    func playPause() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.playPause()
            DispatchQueue.main.async { [weak self] in
                if case .failure(let error) = result {
                    self?.statusMessage = error.errorDescription
                }
            }
        }
    }

    func nextTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.nextTrack()
            DispatchQueue.main.async { [weak self] in
                if case .failure(let error) = result {
                    self?.statusMessage = error.errorDescription
                }
            }
        }
    }

    func previousTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.previousTrack()
            DispatchQueue.main.async { [weak self] in
                if case .failure(let error) = result {
                    self?.statusMessage = error.errorDescription
                }
            }
        }
    }

    private func saveState() {
        let payload = PersistedState(discSlots: discSlots, playback: playback)
        do {
            let data = try JSONEncoder().encode(payload)
            let folderURL = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Failed to save state: \(error)")
            #endif
        }
    }

    private static func loadState(from url: URL) -> PersistedState? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            return nil
        }
    }

    private static func normalizedSlots(from slots: [DiscSlot]) -> [DiscSlot] {
        let byIndex = Dictionary(uniqueKeysWithValues: slots.map { ($0.slotIndex, $0) })
        return (1...5).map { index in
            byIndex[index] ?? DiscSlot(slotIndex: index)
        }
    }

    private static func normalizedPlayback(from playback: PlaybackState) -> PlaybackState {
        var normalized = playback
        if !(1...5).contains(normalized.activeDiscIndex) {
            normalized.activeDiscIndex = 1
        }
        return normalized
    }

    private func updateSlot(slotIndex: Int, with loaded: LoadedDisc) {
        guard let slotPosition = discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        var slot = discSlots[slotPosition]
        slot.sourceType = loaded.sourceType
        slot.playlistPersistentID = loaded.sourceIdentifier
        slot.albumTitle = loaded.albumTitle
        slot.artistName = loaded.artistName
        if let data = loaded.artworkData, !data.isEmpty {
            slot.artworkPNGBase64 = data.base64EncodedString()
        }
        slot.trackIDs = loaded.trackIDs
        slot.trackNumbersByID = loaded.trackNumbersByID
        discSlots[slotPosition] = slot
    }

    private func refreshNowPlayingDisc() {
        DispatchQueue.global(qos: .utility).async {
            let result = MusicController.shared.currentPlaybackInfo()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let info):
                    let match = self.matchingSlot(
                        trackPersistentID: info.trackPersistentID,
                        playlistPersistentID: info.playlistPersistentID,
                        albumTitle: info.albumTitle,
                        artistName: info.artistName
                    )
                    if let match {
                        self.nowPlayingDiscIndex = match.slotIndex
                        if self.playback.activeDiscIndex != match.slotIndex {
                            self.playback.activeDiscIndex = match.slotIndex
                        }
                    } else {
                        self.nowPlayingDiscIndex = nil
                    }
                    self.nowPlayingTrackNumber = self.resolvedTrackNumber(
                        from: info,
                        in: match
                    )
                    self.nowPlayingElapsedSeconds = info.playerPosition
                case .failure:
                    self.nowPlayingDiscIndex = nil
                    self.nowPlayingTrackNumber = nil
                    self.nowPlayingElapsedSeconds = nil
                }
            }
        }
    }

    private func matchingSlot(
        trackPersistentID: String?,
        playlistPersistentID: String?,
        albumTitle: String?,
        artistName: String?
    ) -> DiscSlot? {
        if let trackPersistentID, !trackPersistentID.isEmpty,
           let match = discSlots.first(where: { $0.trackIDs?.contains(trackPersistentID) == true }) {
            return match
        }
        if let playlistPersistentID, !playlistPersistentID.isEmpty,
           let match = discSlots.first(where: { $0.playlistPersistentID == playlistPersistentID }) {
            return match
        }
        if let albumKey = normalize(albumTitle) {
            let artistKey = normalize(artistName)
            return discSlots.first { slot in
                guard let slotAlbum = normalize(slot.albumTitle), slotAlbum == albumKey else {
                    return false
                }
                if let artistKey {
                    guard let slotArtist = normalize(slot.artistName) else { return false }
                    return slotArtist == artistKey
                }
                return true
            }
        }
        return nil
    }

    private func resolvedTrackNumber(
        from info: CurrentPlaybackInfo,
        in slot: DiscSlot?
    ) -> Int? {
        if let number = info.trackNumber, number > 0 {
            return number
        }
        guard let slot, let trackID = info.trackPersistentID else {
            return nil
        }
        if let mapped = slot.trackNumbersByID?[trackID], mapped > 0 {
            return mapped
        }
        if let ids = slot.trackIDs,
           let index = ids.firstIndex(of: trackID) {
            return index + 1
        }
        return nil
    }

    private func normalize(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    private static func defaultStateURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("CDC-2010R", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }
}

private struct PersistedState: Codable {
    let discSlots: [DiscSlot]
    let playback: PlaybackState
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
