//
//  ContentView.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import SwiftUI
import AppKit
import Foundation

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.playback.lidOpen {
                OpenLidView()
            } else {
                ClosedLidView()
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color(red: 0.04, green: 0.05, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

private struct ClosedLidView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 32) {
                VStack(spacing: 8) {
                    ArtworkView(base64: displayedArtwork)
                        .frame(maxWidth: 640, maxHeight: 640)
            }
            .frame(maxWidth: 680)

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Sherwood CDC-2010R")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        Button("Open Lid") {
                            appState.toggleLid()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("DISC SELECT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        HStack(spacing: 16) {
                            ForEach(appState.discSlots) { slot in
                                DiscSelectButton(
                                    discNumber: slot.slotIndex
                                ) {
                                    appState.playDisc(slotIndex: slot.slotIndex)
                                }
                            }
                        }
                    }

                    LEDDisplayView(
                        trackNumber: appState.nowPlayingTrackNumber,
                        elapsedSeconds: appState.nowPlayingElapsedSeconds,
                        fontName: appState.ledFontName,
                        discSlots: appState.discSlots,
                        playingDiscIndex: appState.nowPlayingDiscIndex
                    )
                    .frame(maxWidth: 260)

                    HStack(spacing: 24) {
                        Button {
                            appState.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                        }

                        Button {
                            appState.playPause()
                        } label: {
                            Image(systemName: "playpause.fill")
                                .font(.title2)
                        }

                        Button {
                            appState.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                        }
                    }

                    if let status = appState.statusMessage {
                        Text(status)
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
    }

    private var displayedDiscIndex: Int {
        appState.nowPlayingDiscIndex ?? appState.playback.activeDiscIndex
    }

    private var displayedArtwork: String? {
        displayedSlot?.artworkPNGBase64
    }

    private var displayedAlbumTitle: String? {
        displayedSlot?.albumTitle
    }

    private var displayedArtistName: String? {
        displayedSlot?.artistName
    }

    private var displayedSlot: DiscSlot? {
        appState.discSlots.first { $0.slotIndex == displayedDiscIndex }
    }
}

private struct OpenLidView: View {
    @EnvironmentObject private var appState: AppState

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Preparation Mode")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                Button("Close Lid") {
                    appState.toggleLid()
                }
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.discSlots) { slot in
                    DiscSlotCard(
                        slot: slot,
                        isActive: slot.slotIndex == appState.playback.activeDiscIndex
                    ) {
                        appState.loadDisc(slotIndex: slot.slotIndex)
                    } onRemove: {
                        appState.removeDisc(slotIndex: slot.slotIndex)
                    } onPasteArtwork: {
                        appState.pasteArtwork(slotIndex: slot.slotIndex)
                    }
                }
            }

            if let status = appState.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }
}

private struct DiscSelectButton: View {
    let discNumber: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [
                                Color.white.opacity(1),
                                Color.black.opacity(1)
                            ],
                            center: UnitPoint(x: 0.5, y: 0.2),
                            startRadius: 1,
                            endRadius: 10
                        ).opacity(0.8))
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(1), lineWidth: 3.0)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                .padding(1.2)
                        )
                        .shadow(color: Color.white.opacity(0.2), radius: 0, x: 0, y: 1)
                }
                .frame(width: 18, height: 18)
                Text("\(discNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DiscSlotCard: View {
    @EnvironmentObject private var appState: AppState

    let slot: DiscSlot
    let isActive: Bool
    let onLoad: () -> Void
    let onRemove: () -> Void
    let onPasteArtwork: () -> Void
    @State private var albumQuery = ""
    @State private var albumSuggestions: [AlbumSuggestion] = []
    @State private var isSearching = false
    @State private var searchWorkItem: DispatchWorkItem?
    @State private var showSuggestions = false
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                ArtworkView(base64: slot.artworkPNGBase64)
                if isActive {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(Color.white.opacity(0.7))
                } else if !slot.isLoaded {
                    Text("Empty")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(height: 160)
            .contextMenu {
                Button("Paste Artwork") {
                    onPasteArtwork()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Disc \(slot.slotIndex)")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.9))

                    Button(slot.isLoaded ? "Remove Disc" : "Load from Music") {
                        if slot.isLoaded {
                            onRemove()
                        } else {
                            onLoad()
                        }
                    }
                    .disabled(isActive)
                }

                if !slot.isLoaded {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Load by album")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        TextField("Start typing an album name", text: $albumQuery)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isActive)
                            .focused($isQueryFocused)
                            .onChange(of: albumQuery) { newValue in
                                scheduleSearch(for: newValue)
                            }
                            .onChange(of: isQueryFocused) { focused in
                                if !focused {
                                    showSuggestions = false
                                }
                            }
                            .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(albumSuggestions.prefix(6))) { album in
                                        Button {
                                            select(album)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(album.albumTitle)
                                                    .font(.callout.weight(.semibold))
                                                    .foregroundStyle(Color.primary)
                                                Text(album.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(Color.secondary)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(12)
                                .frame(minWidth: 240, maxWidth: 320)
                            }
                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }

        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isActive ? Color(red: 0.7, green: 0.8, blue: 0.95) : Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func scheduleSearch(for query: String) {
        searchWorkItem?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            albumSuggestions = []
            isSearching = false
            showSuggestions = false
            return
        }
        let workItem = DispatchWorkItem {
            isSearching = true
            appState.searchAlbums(matching: trimmed) { results in
                if albumQuery.trimmingCharacters(in: .whitespacesAndNewlines) != trimmed {
                    return
                }
                albumSuggestions = results
                isSearching = false
                showSuggestions = isQueryFocused && !results.isEmpty
            }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func select(_ album: AlbumSuggestion) {
        albumQuery = ""
        albumSuggestions = []
        isSearching = false
        showSuggestions = false
        appState.loadAlbum(slotIndex: slot.slotIndex, album: album)
    }
}

private struct ArtworkView: View {
    let base64: String?

    var body: some View {
        if let image = decodeImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.12))
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                )
        }
    }

    private func decodeImage() -> NSImage? {
        guard let base64, let data = Data(base64Encoded: base64) else {
            return nil
        }
        return NSImage(data: data)
    }
}
