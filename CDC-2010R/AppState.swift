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

    private var cancellables = Set<AnyCancellable>()
    private let stateURL: URL

    init() {
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
        if let data = loaded.artworkData {
            slot.artworkPNGBase64 = data.base64EncodedString()
        }
        slot.trackIDs = loaded.trackIDs
        discSlots[slotPosition] = slot
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
