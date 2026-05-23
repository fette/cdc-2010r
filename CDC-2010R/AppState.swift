//
//  AppState.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import AppKit
import Combine
import Foundation
import MusicKit
import WebKit

final class AppState: ObservableObject {
    @Published var discSlots: [DiscSlot]
    @Published var playback: PlaybackState
    @Published var statusMessage: String?
    @Published var nowPlayingDiscIndex: Int?
    @Published var nowPlayingTrackNumber: Int?
    @Published var nowPlayingElapsedSeconds: TimeInterval?
    @Published var activeYouTubeVideoID: String?
    /// Strong reference keeps the WKWebView alive across lid open/close.
    var youtubeWebView: WKWebView?
    let ledFontName: String

    private var cancellables = Set<AnyCancellable>()
    private let stateURL: URL
    private var nowPlayingTimer: AnyCancellable?
    private var lastPlaybackTrackKey: String?
    private var lastYouTubeChapter: String?
    private var pendingTrackInfo: (slot: Int, album: String?, artist: String?,
                                   trackName: String?, trackNumber: Int?,
                                   startTime: Date)?
    private var pendingChapterInfo: (slot: Int, album: String?, artist: String?,
                                     chapterName: String?, chapterNumber: Int?,
                                     youtubeURL: String?, startTime: Date)?
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
            activeYouTubeVideoID = nil
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
        if slot.sourceType == "youtube", let videoID = slot.youtubeVideoID {
            activeYouTubeVideoID = videoID
            lastYouTubeChapter = nil
            playback.activeDiscIndex = slotIndex
            nowPlayingDiscIndex = slotIndex
            return
        }
        guard let trackIDs = slot.trackIDs, !trackIDs.isEmpty else {
            statusMessage = "Load a disc before playing."
            return
        }
        statusMessage = "Starting Disc \(slotIndex)..."
        activeYouTubeVideoID = nil
        lastYouTubeChapter = nil
        youtubeWebView = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MusicController.shared.playDisc(trackIDs: trackIDs, discIndex: slotIndex)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.playback.activeDiscIndex = slotIndex
                    self.refreshArtworkIfNeeded(slotIndex: slotIndex)
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
        if activeYouTubeVideoID != nil {
            Task { await youtubeJS("(function(){var v=document.querySelector('video');if(v){v.paused?v.play():v.pause()}})()") }
            return
        }
        if let slot = discSlots.first(where: { $0.slotIndex == playback.activeDiscIndex }),
           slot.sourceType == "youtube" {
            playDisc(slotIndex: playback.activeDiscIndex)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let info = MusicController.shared.currentPlaybackInfo()
            DispatchQueue.main.async {
                guard let self else { return }
                if case .success(let playbackInfo) = info,
                   self.matchingSlot(
                       trackPersistentID: playbackInfo.trackPersistentID,
                       playlistPersistentID: playbackInfo.playlistPersistentID,
                       albumTitle: playbackInfo.albumTitle,
                       artistName: playbackInfo.artistName
                   ) != nil {
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = MusicController.shared.playPause()
                        DispatchQueue.main.async {
                            if case .failure(let error) = result {
                                self.statusMessage = error.errorDescription
                            }
                        }
                    }
                } else {
                    self.playDisc(slotIndex: self.playback.activeDiscIndex)
                }
            }
        }
    }

    func nextTrack() {
        if activeYouTubeVideoID != nil {
            Task {
                await youtubeJS("""
                (function(){
                    \(Self.chapterExtractJS)
                    var v=document.querySelector('video');if(!v)return;
                    var chs=window.__cdcChapters;
                    if(!chs||!chs.length){v.currentTime=Math.min(v.currentTime+30,v.duration);return;}
                    var t=v.currentTime;
                    for(var i=0;i<chs.length;i++){if(chs[i].s>t+1){v.currentTime=chs[i].s;return;}}
                })()
                """)
            }
            return
        }
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
        if activeYouTubeVideoID != nil {
            Task {
                await youtubeJS("""
                (function(){
                    \(Self.chapterExtractJS)
                    var v=document.querySelector('video');if(!v)return;
                    var chs=window.__cdcChapters;
                    if(!chs||!chs.length){v.currentTime=Math.max(v.currentTime-30,0);return;}
                    var t=v.currentTime;
                    for(var i=chs.length-1;i>=0;i--){if(chs[i].s<t-3){v.currentTime=chs[i].s;return;}}
                    v.currentTime=0;
                })()
                """)
            }
            return
        }
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
        slot.playlistName = loaded.playlistName
        if let data = loaded.artworkData, !data.isEmpty {
            slot.artworkPNGBase64 = data.base64EncodedString()
        }
        slot.trackIDs = loaded.trackIDs
        slot.trackNumbersByID = loaded.trackNumbersByID
        discSlots[slotPosition] = slot

        if slot.artworkPNGBase64 == nil {
            if loaded.sourceType == "playlist", let name = loaded.playlistName, !name.isEmpty {
                fetchPlaylistArtworkViaMusicKit(slotIndex: slotIndex, playlistName: name)
            } else {
                fetchArtworkFromiTunesAPI(slotIndex: slotIndex, album: loaded.albumTitle, artist: loaded.artistName)
            }
        }
    }

    private func refreshNowPlayingDisc() {
        if activeYouTubeVideoID != nil {
            refreshYouTubeNowPlaying()
            return
        }
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
                        // Log the previous track if it played ≥ 30 seconds
                        if let pending = self.pendingTrackInfo,
                           Date().timeIntervalSince(pending.startTime) >= 30 {
                            self.logEvent("track",
                                slot: pending.slot,
                                album: pending.album,
                                artist: pending.artist,
                                trackName: pending.trackName,
                                trackNumber: pending.trackNumber)
                        }
                        // Store the new track as pending (or nil if nothing playing)
                        if let trackKey {
                            self.pendingTrackInfo = (
                                slot: self.nowPlayingDiscIndex ?? 0,
                                album: info.albumTitle,
                                artist: info.artistName,
                                trackName: info.trackName,
                                trackNumber: self.nowPlayingTrackNumber,
                                startTime: Date()
                            )
                        } else {
                            self.pendingTrackInfo = nil
                        }
                        self.lastPlaybackTrackKey = trackKey
                    }
                case .failure:
                    if let pending = self.pendingTrackInfo,
                       Date().timeIntervalSince(pending.startTime) >= 30 {
                        self.logEvent("track",
                            slot: pending.slot,
                            album: pending.album,
                            artist: pending.artist,
                            trackName: pending.trackName,
                            trackNumber: pending.trackNumber)
                    }
                    self.pendingTrackInfo = nil
                    self.nowPlayingDiscIndex = nil
                    self.nowPlayingTrackNumber = nil
                    self.nowPlayingElapsedSeconds = nil
                    self.lastPlaybackTrackKey = nil
                }
            }
        }
    }

    @discardableResult
    private func youtubeJS(_ js: String) async -> Any? {
        guard let webView = youtubeWebView else { return nil }
        return try? await webView.evaluateJavaScript(js)
    }

    /// Shared JS snippet that lazily extracts YouTube chapter timestamps.
    /// Tries ytInitialData first, then falls back to DOM scraping of the chapter list.
    /// Only caches when chapters are actually found; retries on failure.
    private static let chapterExtractJS = """
    if(!window.__cdcChapters){
        try{
            var c=window.ytInitialData.playerOverlays.playerOverlayRenderer
                .decoratedPlayerBarRenderer.decoratedPlayerBarRenderer.playerBar
                .multiMarkersPlayerBarRenderer.markersMap[0].value.chapters;
            if(c&&c.length)window.__cdcChapters=c.map(function(x){return{
                title:x.chapterRenderer.title.simpleText,
                s:x.chapterRenderer.timeRangeStartMillis/1000};});
        }catch(e){}
        if(!window.__cdcChapters){try{
            var links=document.querySelectorAll('ytd-macro-markers-list-item-renderer a');
            if(links.length){var r=[];links.forEach(function(a){
                var te=a.querySelector('#time'),ti=a.querySelector('#details h4');
                if(te&&ti){var p=te.innerText.replace(/\\./g,':').split(':').map(Number);
                    var s=p.length===3?p[0]*3600+p[1]*60+p[2]:p[0]*60+p[1];
                    r.push({title:ti.innerText.trim(),s:s});}
            });if(r.length)window.__cdcChapters=r;}
        }catch(e){}}
    }
    """

    private func refreshYouTubeNowPlaying() {
        Task {
            if let seconds = await youtubeJS("document.querySelector('video')?.currentTime") as? Double {
                nowPlayingElapsedSeconds = seconds
            }
            // Get current chapter index (1-based) from cached chapter list + current time
            if let idx = await youtubeJS("""
                (function(){
                    \(Self.chapterExtractJS)
                    var chs=window.__cdcChapters;if(!chs||!chs.length)return null;
                    var v=document.querySelector('video');if(!v)return null;
                    var t=v.currentTime,idx=0;
                    for(var i=chs.length-1;i>=0;i--){if(chs[i].s<=t+0.5){idx=i;break;}}
                    return idx+1;
                })()
                """) as? Int {
                nowPlayingTrackNumber = idx
            } else {
                nowPlayingTrackNumber = nil
            }
            if let chapter = await youtubeJS("document.querySelector('.ytp-chapter-title-content')?.textContent?.trim()") as? String, !chapter.isEmpty {
                if chapter != lastYouTubeChapter {
                    let slot = discSlots.first { $0.slotIndex == playback.activeDiscIndex }
                    // Log the previous chapter if it played ≥ 30 seconds
                    if let pending = pendingChapterInfo,
                       Date().timeIntervalSince(pending.startTime) >= 30 {
                        logEvent("chapter", slot: pending.slot, album: pending.album, artist: pending.artist, trackName: pending.chapterName, trackNumber: pending.chapterNumber, youtubeURL: pending.youtubeURL)
                    }
                    // Store the new chapter as pending
                    pendingChapterInfo = (
                        slot: playback.activeDiscIndex,
                        album: slot?.albumTitle,
                        artist: slot?.artistName,
                        chapterName: chapter,
                        chapterNumber: nowPlayingTrackNumber,
                        youtubeURL: slot?.youtubeURL,
                        startTime: Date()
                    )
                    lastYouTubeChapter = chapter
                }
            } else {
                if let pending = pendingChapterInfo,
                   Date().timeIntervalSince(pending.startTime) >= 30 {
                    logEvent("chapter", slot: pending.slot, album: pending.album, artist: pending.artist, trackName: pending.chapterName, trackNumber: pending.chapterNumber, youtubeURL: pending.youtubeURL)
                }
                pendingChapterInfo = nil
                lastYouTubeChapter = nil
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
                guard let slotPosition = self.discSlots.firstIndex(where: { $0.slotIndex == slotIndex }) else {
                    return
                }
                guard self.discSlots[slotPosition].artworkPNGBase64 == nil else {
                    return
                }
                if case .success(let data) = result, let data, !data.isEmpty {
                    var updatedSlot = self.discSlots[slotPosition]
                    updatedSlot.artworkPNGBase64 = data.base64EncodedString()
                    self.discSlots[slotPosition] = updatedSlot
                } else {
                    let currentSlot = self.discSlots[slotPosition]
                    if currentSlot.sourceType == "playlist", let name = currentSlot.playlistName, !name.isEmpty {
                        self.fetchPlaylistArtworkViaMusicKit(slotIndex: slotIndex, playlistName: name)
                    } else {
                        self.fetchArtworkFromiTunesAPI(slotIndex: slotIndex, album: currentSlot.albumTitle, artist: currentSlot.artistName)
                    }
                }
            }
        }
    }

    private func fetchArtworkFromiTunesAPI(slotIndex: Int, album: String?, artist: String?) {
        guard let album, !album.isEmpty else { return }
        var terms = album
        if let artist, !artist.isEmpty {
            terms += " \(artist)"
        }
        guard let encoded = terms.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=album&limit=1") else {
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artworkURLString = first["artworkUrl100"] as? String else {
                return
            }
            let hiRes = artworkURLString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            guard let imageURL = URL(string: hiRes) else { return }
            URLSession.shared.dataTask(with: imageURL) { [weak self] imgData, _, _ in
                DispatchQueue.main.async {
                    guard let self, let imgData, !imgData.isEmpty else { return }
                    guard let slotPosition = self.discSlots.firstIndex(where: { $0.slotIndex == slotIndex }),
                          self.discSlots[slotPosition].artworkPNGBase64 == nil else {
                        return
                    }
                    var slot = self.discSlots[slotPosition]
                    slot.artworkPNGBase64 = imgData.base64EncodedString()
                    self.discSlots[slotPosition] = slot
                }
            }.resume()
        }.resume()
    }

    private func fetchPlaylistArtworkViaMusicKit(slotIndex: Int, playlistName: String) {
        Task {
            let status = await MusicAuthorization.request()
            guard status == .authorized else {
                await MainActor.run {
                    // Fall back to iTunes API using the slot's album/artist info
                    if let slot = discSlots.first(where: { $0.slotIndex == slotIndex }) {
                        fetchArtworkFromiTunesAPI(slotIndex: slotIndex, album: slot.albumTitle, artist: slot.artistName)
                    }
                }
                return
            }
            do {
                var request = MusicLibraryRequest<Playlist>()
                request.filter(matching: \.name, equalTo: playlistName)
                let response = try await request.response()
                guard let playlist = response.items.first,
                      let artwork = playlist.artwork,
                      let artworkURL = artwork.url(width: 600, height: 600) else {
                    await MainActor.run {
                        if let slot = discSlots.first(where: { $0.slotIndex == slotIndex }) {
                            fetchArtworkFromiTunesAPI(slotIndex: slotIndex, album: slot.albumTitle, artist: slot.artistName)
                        }
                    }
                    return
                }
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                guard !data.isEmpty else { return }
                await MainActor.run {
                    guard let slotPosition = discSlots.firstIndex(where: { $0.slotIndex == slotIndex }),
                          discSlots[slotPosition].artworkPNGBase64 == nil else {
                        return
                    }
                    var slot = discSlots[slotPosition]
                    slot.artworkPNGBase64 = data.base64EncodedString()
                    discSlots[slotPosition] = slot
                }
            } catch {
                await MainActor.run {
                    if let slot = discSlots.first(where: { $0.slotIndex == slotIndex }) {
                        fetchArtworkFromiTunesAPI(slotIndex: slotIndex, album: slot.albumTitle, artist: slot.artistName)
                    }
                }
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
