//
//  CDC_2010RTests.swift
//  CDC-2010RTests
//
//  Created by William Van Hecke on 2025/12/22.
//

import Testing
@testable import CDC_2010R

struct CDC_2010RTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}

// Searching the library must stay fast and bounded: every keystroke enqueues
// scripts on the shared serial script queue, so a full-library scan there
// stalls polling, playback, and later searches until the app looks frozen.
struct MusicSearchScriptTests {

    @Test func albumSearchUsesIndexedLookup() {
        let script = MusicController.albumSearchScript(query: "abbey", limit: 8)
        #expect(script.contains("only albums"))
        #expect(!script.contains("whose"))
    }

    @Test func albumSearchIsTimeoutBound() {
        let script = MusicController.albumSearchScript(query: "abbey", limit: 8)
        #expect(script.contains("with timeout of \(MusicController.searchScriptTimeoutSeconds) seconds"))
        #expect(script.contains("end timeout"))
        #expect(MusicController.searchScriptTimeoutSeconds >= 5)
        #expect(MusicController.searchScriptTimeoutSeconds <= 30)
    }

    @Test func albumSearchClampsLimit() {
        #expect(MusicController.albumSearchScript(query: "x", limit: 0).contains("limitCount to 1"))
        #expect(MusicController.albumSearchScript(query: "x", limit: 8).contains("limitCount to 8"))
        #expect(MusicController.albumSearchScript(query: "x", limit: 100).contains("limitCount to 25"))
    }

    @Test func albumSearchEscapesQuery() {
        let script = MusicController.albumSearchScript(query: "a\"b\\c", limit: 8)
        #expect(script.contains("a\\\"b\\\\c"))
        #expect(script.contains(#"return {"ALBUMS", results}"#))
    }

    @Test func playlistSearchIsTimeoutBound() {
        let script = MusicController.playlistSearchScript(query: "road", limit: 6)
        #expect(script.contains("with timeout of \(MusicController.searchScriptTimeoutSeconds) seconds"))
        #expect(script.contains("end timeout"))
        #expect(script.contains(#"return {"PLAYLISTS", results}"#))
    }

    @Test func playlistSearchClampsLimit() {
        #expect(MusicController.playlistSearchScript(query: "x", limit: 0).contains("limitCount to 1"))
        #expect(MusicController.playlistSearchScript(query: "x", limit: 6).contains("limitCount to 6"))
        #expect(MusicController.playlistSearchScript(query: "x", limit: 99).contains("limitCount to 25"))
    }

}
