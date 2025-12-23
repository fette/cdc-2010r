//
//  ContentView.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import SwiftUI
import AppKit

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
        .frame(minWidth: 760, minHeight: 560)
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
            HStack {
                Text("Sherwood CDC-2010R")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
                Spacer()
                Button("Open Lid") {
                    appState.toggleLid()
                }
            }

            HStack(spacing: 12) {
                ForEach(appState.discSlots) { slot in
                    DiscButton(
                        title: "DISC \(slot.slotIndex)",
                        isActive: slot.slotIndex == displayedDiscIndex
                    ) {
                        appState.playDisc(slotIndex: slot.slotIndex)
                    }
                }
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    VStack(spacing: 8) {
                        ArtworkView(base64: displayedArtwork)
                            .frame(maxWidth: 220, maxHeight: 220)
                        Text(displayedDiscTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                        if let albumTitle = displayedAlbumTitle {
                            Text(albumTitle)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        if let artistName = displayedArtistName {
                            Text(artistName)
                                .font(.callout)
                                .foregroundStyle(Color.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        LEDDisplayView(
                            trackNumber: appState.nowPlayingTrackNumber,
                            elapsedSeconds: appState.nowPlayingElapsedSeconds,
                            fontName: appState.ledFontName
                        )
                        .frame(maxWidth: 260)
                    }
                )
                .frame(maxWidth: 360, maxHeight: 360)

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

            Text("Mode: \(appState.playback.mode.displayName)")
                .font(.callout)
                .foregroundStyle(Color.white.opacity(0.6))

            if let status = appState.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    private var displayedDiscIndex: Int {
        appState.nowPlayingDiscIndex ?? appState.playback.activeDiscIndex
    }

    private var displayedDiscTitle: String {
        guard let slot = displayedSlot else { return "No Disc Playing" }
        return slot.isLoaded ? "Disc \(slot.slotIndex)" : "Empty Disc"
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

private struct DiscButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.85))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color(red: 0.7, green: 0.8, blue: 0.95) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct DiscSlotCard: View {
    let slot: DiscSlot
    let isActive: Bool
    let onLoad: () -> Void

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

            Text("Disc \(slot.slotIndex)")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.9))

            Button("Load from Music") {
                onLoad()
            }
            .disabled(isActive)

            if slot.isLoaded {
                DiscDetailView(slot: slot)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isActive ? Color(red: 0.7, green: 0.8, blue: 0.95) : Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct DiscDetailView: View {
    let slot: DiscSlot

    var body: some View {
        VStack(spacing: 4) {
            if let albumTitle = slot.albumTitle {
                Text(albumTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            if let artistName = slot.artistName {
                Text(artistName)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
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
