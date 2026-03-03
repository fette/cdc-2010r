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
    private var lastPlaybackTrackKey: String?
    private let cdcLogURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("source/promptuary/cdc-log.jsonl")
    }()

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
                    self.logEvent("loaded", slot: slotIndex, album: loaded.albumTitle, artist: loaded.artistName)
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

    func loadAlbum(slotIndex: Int, album: MusicSuggestion) {
        statusMessage = "Loading \(album.title)..."
        _ = MusicController.shared.requestAutomationPermission()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.loadAlbum(albumTitle: album.title, artistName: album.artistName)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.updateSlot(slotIndex: slotIndex, with: loaded)
                    self.logEvent("loaded", slot: slotIndex, album: loaded.albumTitle, artist: loaded.artistName)
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

    func loadPlaylist(slotIndex: Int, playlistID: String, playlistName: String) {
        statusMessage = "Loading \(playlistName)..."
        _ = MusicController.shared.requestAutomationPermission()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.loadPlaylist(persistentID: playlistID)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let loaded):
                    self.updateSlot(slotIndex: slotIndex, with: loaded)
                    self.logEvent("loaded", slot: slotIndex, album: loaded.albumTitle, artist: loaded.artistName)
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

    func searchLibrary(matching query: String, completion: @escaping ([MusicSuggestion]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            completion([])
            return
        }
        _ = MusicController.shared.requestAutomationPermission()
        DispatchQueue.global(qos: .userInitiated).async {
            let albumResult = MusicController.shared.searchAlbums(matching: trimmed, limit: 8)
            let playlistResult = MusicController.shared.searchPlaylists(matching: trimmed, limit: 6)
            DispatchQueue.main.async { [weak self] in
                var suggestions: [MusicSuggestion] = []
                switch playlistResult {
                case .success(let playlists):
                    suggestions.append(contentsOf: playlists)
                case .failure(let error):
                    self?.statusMessage = error.errorDescription
                }
                switch albumResult {
                case .success(let albums):
                    suggestions.append(contentsOf: albums)
                case .failure(let error):
                    self?.statusMessage = error.errorDescription
                }
                completion(suggestions)
            }
        }
    }

    func fetchYouTubeMetadata(url: String, completion: @escaping (MusicSuggestion?) -> Void) {
        guard let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oembedURL = URL(string: "https://www.youtube.com/oembed?url=\(encodedURL)&format=json") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: oembedURL) { data, _, error in
            DispatchQueue.main.async {
                guard let data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let title = json["title"] as? String,
                      let authorName = json["author_name"] as? String else {
                    completion(nil)
                    return
                }
                let thumbnailURL = json["thumbnail_url"] as? String
                let suggestion = MusicSuggestion(
                    kind: .youtube,
                    title: title,
                    subtitle: authorName,
                    albumTitle: title,
                    artistName: authorName,
                    youtubeURL: url,
                    thumbnailURL: thumbnailURL
                )
                completion(suggestion)
            }
        }.resume()
    }

    func loadYouTube(slotIndex: Int, url: String, title: String, channelName: String, thumbnailURL: String?) {
        guard let slotPosition = discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        statusMessage = "Loading YouTube..."
        var slot = discSlots[slotPosition]
        slot.sourceType = "youtube"
        slot.albumTitle = title
        slot.artistName = channelName
        slot.youtubeURL = url
        slot.playlistPersistentID = nil
        slot.trackIDs = nil
        slot.trackNumbersByID = nil
        discSlots[slotPosition] = slot

        if let thumbnailURL, let thumbURL = URL(string: thumbnailURL) {
            URLSession.shared.dataTask(with: thumbURL) { [weak self] data, _, _ in
                DispatchQueue.main.async {
                    guard let self, let data, !data.isEmpty else { return }
                    guard let slotPos = self.discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else { return }
                    var updated = self.discSlots[slotPos]
                    updated.artworkPNGBase64 = data.base64EncodedString()
                    self.discSlots[slotPos] = updated
                }
            }.resume()
        }

        logEvent("loaded", slot: slotIndex, album: title, artist: channelName, youtubeURL: url)
        statusMessage = "Loaded Disc \(slotIndex)."
    }

    func removeDisc(slotIndex: Int) {
        guard let slotPosition = discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        let old = discSlots[slotPosition]
        logEvent("removed", slot: slotIndex, album: old.albumTitle, artist: old.artistName)
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
        if slot.sourceType == "youtube", let urlString = slot.youtubeURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            logEvent("play", slot: slotIndex, album: slot.albumTitle, artist: slot.artistName, youtubeURL: urlString)
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
                    self.refreshArtworkIfNeeded(slotIndex: slotIndex)
                    self.logEvent("play", slot: slotIndex, album: slot.albumTitle, artist: slot.artistName)
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

    private func logEvent(_ event: String, slot: Int, album: String?, artist: String?, trackName: String? = nil, trackNumber: Int? = nil, youtubeURL: String? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        var entry: [String: Any?] = [
            "event": event,
            "slot": slot,
            "album": album,
            "artist": artist,
            "ts": formatter.string(from: Date())
        ]
        if let trackName {
            entry["trackName"] = trackName
        }
        if let trackNumber {
            entry["trackNumber"] = trackNumber
        }
        if let youtubeURL {
            entry["youtubeURL"] = youtubeURL
        }
        let compact = entry.compactMapValues { $0 }
        guard let data = try? JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if FileManager.default.fileExists(atPath: cdcLogURL.path) {
            guard let handle = try? FileHandle(forWritingTo: cdcLogURL) else { return }
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: cdcLogURL)
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
                    let trackKey = self.currentTrackKey(from: info, in: match)
                    if trackKey != self.lastPlaybackTrackKey {
                        if let slotIndex = self.nowPlayingDiscIndex {
                            self.refreshArtworkIfNeeded(slotIndex: slotIndex)
                        }
                        if let trackKey {
                            self.logEvent("track",
                                slot: self.nowPlayingDiscIndex ?? 0,
                                album: info.albumTitle,
                                artist: info.artistName,
                                trackName: info.trackName,
                                trackNumber: self.nowPlayingTrackNumber)
                        }
                        self.lastPlaybackTrackKey = trackKey
                    }
                case .failure:
                    self.nowPlayingDiscIndex = nil
                    self.nowPlayingTrackNumber = nil
                    self.nowPlayingElapsedSeconds = nil
                    self.lastPlaybackTrackKey = nil
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

    private func refreshArtworkIfNeeded(slotIndex: Int) {
        guard let slot = discSlots.first(where: { $0.slotIndex == slotIndex }) else {
            return
        }
        guard slot.artworkPNGBase64 == nil else {
            return
        }
        guard let trackIDs = slot.trackIDs, !trackIDs.isEmpty else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let result = MusicController.shared.fetchArtwork(trackIDs: trackIDs)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard case .success(let data) = result,
                      let data,
                      !data.isEmpty else {
                    return
                }
                guard let slotPosition = self.discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
                    return
                }
                var updatedSlot = self.discSlots[slotPosition]
                guard updatedSlot.artworkPNGBase64 == nil else {
                    return
                }
                updatedSlot.artworkPNGBase64 = data.base64EncodedString()
                self.discSlots[slotPosition] = updatedSlot
            }
        }
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

    private func currentTrackKey(from info: CurrentPlaybackInfo, in slot: DiscSlot?) -> String? {
        if let persistentID = info.trackPersistentID, !persistentID.isEmpty {
            return "id:\(persistentID)"
        }
        guard let slot, let trackNumber = resolvedTrackNumber(from: info, in: slot) else {
            return nil
        }
        return "slot:\(slot.slotIndex)|track:\(trackNumber)"
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
