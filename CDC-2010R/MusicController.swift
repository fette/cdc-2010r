//
//  MusicController.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import Foundation
import Security
import AppKit
import ApplicationServices

struct LoadedDisc {
    let sourceType: String
    let sourceIdentifier: String
    let artworkData: Data?
    let trackIDs: [String]
}

enum MusicControllerError: LocalizedError {
    case musicNotRunning
    case notAuthorized
    case noCurrentTrack
    case noAlbumFound
    case noPlaylistFound
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .musicNotRunning:
            return "Open Music to use the changer."
        case .notAuthorized:
            return "Allow CDC-2010R to control Music in System Settings > Privacy & Security > Automation."
        case .noCurrentTrack:
            return "Play a track in Music to load an album."
        case .noAlbumFound:
            return "Could not find album tracks in your library."
        case .noPlaylistFound:
            return "No current playlist found."
        case .scriptFailed(let message):
            return "Music scripting error: \(message)"
        }
    }
}

final class MusicController {
    static let shared = MusicController()

    private init() {}

    func loadCurrentAlbumOrPlaylist() -> Result<LoadedDisc, MusicControllerError> {
        guard ensureMusicRunning() else {
            return .failure(.musicNotRunning)
        }
        switch loadCurrentAlbum() {
        case .success(let disc):
            return .success(disc)
        case .failure(let error):
            switch error {
            case .noCurrentTrack, .noAlbumFound:
                return loadCurrentPlaylist()
            default:
                return .failure(error)
            }
        }
    }

    func diagnostics() -> String {
        let musicRunning = isMusicRunning()
        let entitlement = hasAppleEventsEntitlement()
        let usageDescription = hasAppleEventsUsageDescription()
        return "Diagnostics: musicRunning=\(musicRunning), appleEventsEntitlement=\(entitlement), usageDescription=\(usageDescription)"
    }

    @MainActor
    func requestAutomationPermission() -> Result<Void, MusicControllerError> {
        var targetDesc = AEAddressDesc()
        let bundleID = "com.apple.Music"
        let statusCreate = bundleID.withCString { ptr in
            AECreateDesc(DescType(typeApplicationBundleID), ptr, bundleID.utf8.count, &targetDesc)
        }
        guard statusCreate == noErr else {
            return .failure(.musicNotRunning)
        }
        let status = AEDeterminePermissionToAutomateTarget(
            &targetDesc,
            typeWildCard,
            typeWildCard,
            true
        )
        AEDisposeDesc(&targetDesc)
        if status == noErr {
            return .success(())
        }
        return .failure(.notAuthorized)
    }

    private func loadCurrentAlbum() -> Result<LoadedDisc, MusicControllerError> {
        let script = """
        tell application id "com.apple.Music"
            set t to current track
            if t is missing value then return {"ERROR","NO_CURRENT_TRACK"}
            set albumName to album of t
            set artistName to artist of t
            if albumName is missing value then return {"ERROR","NO_ALBUM"}
            set albumTracks to (every track of library playlist 1 whose album is albumName and artist is artistName)
            if (count of albumTracks) is 0 then return {"ERROR","NO_ALBUM"}
            set trackInfoList to {}
            repeat with tr in albumTracks
                set end of trackInfoList to {persistent ID of tr as text, track number of tr, disc number of tr}
            end repeat
            set artData to ""
            if (count of artworks of t) > 0 then set artData to (data of artwork 1 of t)
            return {"ALBUM", albumName, artistName, artData, trackInfoList}
        end tell
        """

        return parseAlbumResult(run(script: script))
    }

    private func loadCurrentPlaylist() -> Result<LoadedDisc, MusicControllerError> {
        let script = """
        tell application id "com.apple.Music"
            set pl to current playlist
            if pl is missing value then return {"ERROR","NO_PLAYLIST"}
            set pid to persistent ID of pl as text
            set trackInfoList to {}
            repeat with tr in tracks of pl
                set end of trackInfoList to {persistent ID of tr as text, track number of tr, disc number of tr}
            end repeat
            set artData to ""
            if (count of tracks of pl) > 0 then
                set t to item 1 of tracks of pl
                if (count of artworks of t) > 0 then set artData to (data of artwork 1 of t)
            end if
            return {"PLAYLIST", pid, artData, trackInfoList}
        end tell
        """

        return parsePlaylistResult(run(script: script))
    }

    private func run(script: String) -> Result<NSAppleEventDescriptor, MusicControllerError> {
        guard let appleScript = NSAppleScript(source: script) else {
            return .failure(.scriptFailed("Invalid script."))
        }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error."
            if message.localizedCaseInsensitiveContains("application isn") &&
                message.localizedCaseInsensitiveContains("running") {
                return isMusicRunning() ? .failure(.notAuthorized) : .failure(.musicNotRunning)
            }
            if message.localizedCaseInsensitiveContains("not authorized") ||
                message.localizedCaseInsensitiveContains("not permitted") {
                return .failure(.notAuthorized)
            }
            return .failure(.scriptFailed(message))
        }
        return .success(result)
    }

    private func parseAlbumResult(_ result: Result<NSAppleEventDescriptor, MusicControllerError>) -> Result<LoadedDisc, MusicControllerError> {
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            if isErrorDescriptor(descriptor, code: "NO_CURRENT_TRACK") {
                return .failure(.noCurrentTrack)
            }
            if isErrorDescriptor(descriptor, code: "NO_ALBUM") {
                return .failure(.noAlbumFound)
            }
            guard descriptor.numberOfItems >= 5 else {
                return .failure(.scriptFailed("Unexpected album result."))
            }
            let albumName = descriptor.atIndex(2)?.stringValue ?? "Unknown Album"
            let artistName = descriptor.atIndex(3)?.stringValue ?? "Unknown Artist"
            let artData = descriptor.atIndex(4)?.data
            let trackInfoDescriptor = descriptor.atIndex(5)
            let trackInfos = parseTrackInfos(from: trackInfoDescriptor)
            let trackIDs = trackInfos.sorted {
                if $0.discNumber == $1.discNumber {
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.discNumber < $1.discNumber
            }.map { $0.persistentID }
            let identifier = "album:\(artistName)|\(albumName)"
            return .success(LoadedDisc(
                sourceType: "album",
                sourceIdentifier: identifier,
                artworkData: artData,
                trackIDs: trackIDs
            ))
        }
    }

    private func parsePlaylistResult(_ result: Result<NSAppleEventDescriptor, MusicControllerError>) -> Result<LoadedDisc, MusicControllerError> {
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            if isErrorDescriptor(descriptor, code: "NO_PLAYLIST") {
                return .failure(.noPlaylistFound)
            }
            guard descriptor.numberOfItems >= 4 else {
                return .failure(.scriptFailed("Unexpected playlist result."))
            }
            let playlistID = descriptor.atIndex(2)?.stringValue ?? "unknown-playlist"
            let artData = descriptor.atIndex(3)?.data
            let trackInfoDescriptor = descriptor.atIndex(4)
            let trackInfos = parseTrackInfos(from: trackInfoDescriptor)
            let trackIDs = trackInfos.sorted {
                if $0.discNumber == $1.discNumber {
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.discNumber < $1.discNumber
            }.map { $0.persistentID }
            return .success(LoadedDisc(
                sourceType: "playlist",
                sourceIdentifier: playlistID,
                artworkData: artData,
                trackIDs: trackIDs
            ))
        }
    }

    private func isErrorDescriptor(_ descriptor: NSAppleEventDescriptor, code: String) -> Bool {
        guard descriptor.numberOfItems >= 2 else { return false }
        let tag = descriptor.atIndex(1)?.stringValue
        let value = descriptor.atIndex(2)?.stringValue
        return tag == "ERROR" && value == code
    }

    private func parseTrackInfos(from descriptor: NSAppleEventDescriptor?) -> [TrackInfo] {
        guard let descriptor else { return [] }
        var infos: [TrackInfo] = []
        for index in 1...descriptor.numberOfItems {
            guard let item = descriptor.atIndex(index),
                  item.numberOfItems >= 3 else { continue }
            let persistentID = item.atIndex(1)?.stringValue ?? ""
            let trackNumber = item.atIndex(2)?.int32Value ?? 0
            let discNumber = item.atIndex(3)?.int32Value ?? 0
            if !persistentID.isEmpty {
                infos.append(TrackInfo(
                    persistentID: persistentID,
                    trackNumber: Int(trackNumber),
                    discNumber: Int(discNumber)
                ))
            }
        }
        return infos
    }

    private func ensureMusicRunning() -> Bool {
        if isMusicRunning() {
            return true
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return false
        }
        do {
            try NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            return false
        }
        for _ in 0..<10 {
            if isMusicRunning() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private func isMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            if let bundleID = app.bundleIdentifier, bundleID == "com.apple.Music" {
                return true
            }
            return app.localizedName == "Music"
        }
    }

    private func hasAppleEventsEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.automation.apple-events" as CFString, nil)
        return (value as? Bool) == true
    }

    private func hasAppleEventsUsageDescription() -> Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") != nil
    }
}

private struct TrackInfo {
    let persistentID: String
    let trackNumber: Int
    let discNumber: Int
}
