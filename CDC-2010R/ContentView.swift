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
                Spacer()
                Button("Open Lid") {
                    appState.toggleLid()
                }
            }

            HStack(spacing: 12) {
                ForEach(appState.discSlots) { slot in
                    DiscButton(
                        title: "DISC \(slot.slotIndex)",
                        isActive: slot.slotIndex == appState.playback.activeDiscIndex
                    ) {
                        appState.setActiveDisc(slot.slotIndex)
                    }
                }
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [.gray.opacity(0.2), .gray.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    VStack(spacing: 8) {
                        ArtworkView(base64: activeArtwork)
                            .frame(maxWidth: 220, maxHeight: 220)
                        Text(activeDiscTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let albumTitle = activeAlbumTitle {
                            Text(albumTitle)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let artistName = activeArtistName {
                            Text(artistName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                )
                .frame(maxWidth: 360, maxHeight: 360)

            HStack(spacing: 24) {
                Button {
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(true)

                Button {
                } label: {
                    Image(systemName: "playpause.fill")
                        .font(.title2)
                }
                .disabled(true)

                Button {
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(true)
            }

            Text("Mode: \(appState.playback.mode.displayName)")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let status = appState.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeDiscTitle: String {
        let slot = appState.discSlots.first { $0.slotIndex == appState.playback.activeDiscIndex }
        return slot?.isLoaded == true ? "Loaded Disc \(appState.playback.activeDiscIndex)" : "Empty Disc"
    }

    private var activeArtwork: String? {
        appState.discSlots.first { $0.slotIndex == appState.playback.activeDiscIndex }?.artworkPNGBase64
    }

    private var activeAlbumTitle: String? {
        appState.discSlots.first { $0.slotIndex == appState.playback.activeDiscIndex }?.albumTitle
    }

    private var activeArtistName: String? {
        appState.discSlots.first { $0.slotIndex == appState.playback.activeDiscIndex }?.artistName
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.accentColor : Color.gray.opacity(0.15))
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
                        colors: [.gray.opacity(0.2), .gray.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                ArtworkView(base64: slot.artworkPNGBase64)
                if isActive {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else if !slot.isLoaded {
                    Text("Empty")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 160)

            Text("Disc \(slot.slotIndex)")
                .font(.headline)

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
                .strokeBorder(isActive ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let artistName = slot.artistName {
                Text(artistName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
