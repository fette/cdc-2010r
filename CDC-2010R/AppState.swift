//
//  AppState.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

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
        discSlots[slotPosition] = slot
    }

    private func refreshNowPlayingDisc() {
        DispatchQueue.global(qos: .utility).async {
            let result = MusicController.shared.currentTrackPersistentID()
            let trackResult = MusicController.shared.currentTrackNumber()
            let positionResult = MusicController.shared.currentPlayerPosition()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let persistentID):
                    if let match = self.discSlots.first(where: { $0.trackIDs?.contains(persistentID) == true }) {
                        self.nowPlayingDiscIndex = match.slotIndex
                        if self.playback.activeDiscIndex != match.slotIndex {
                            self.playback.activeDiscIndex = match.slotIndex
                        }
                    } else {
                        self.nowPlayingDiscIndex = nil
                    }
                case .failure:
                    self.nowPlayingDiscIndex = nil
                }
                switch trackResult {
                case .success(let number):
                    self.nowPlayingTrackNumber = number > 0 ? number : nil
                case .failure:
                    self.nowPlayingTrackNumber = nil
                }
                switch positionResult {
                case .success(let position):
                    self.nowPlayingElapsedSeconds = position > 0 ? position : nil
                case .failure:
                    self.nowPlayingElapsedSeconds = nil
                }
            }
        }
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
