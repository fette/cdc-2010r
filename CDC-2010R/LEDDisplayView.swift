//
//  LEDDisplayView.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/23.
//

import SwiftUI

struct LEDDisplayView: View {
    let trackNumber: Int?
    let elapsedSeconds: TimeInterval?
    let fontName: String
    let discSlots: [DiscSlot]
    let playingDiscIndex: Int?

    var body: some View {
        VStack(spacing: 8) {
            DiscIndicatorRow(discSlots: discSlots, playingDiscIndex: playingDiscIndex)
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    labelGlowText("TRACK", size: 9)
                    ledGlowText(trackDigits, size: 30)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 16) {
                        labelGlowText("MIN", size: 9)
                        labelGlowText("SEC", size: 9)
                    }
                    HStack(spacing: 6) {
                        ledGlowText(minutesText, size: 30)
                        colonText(size: 26)
                        ledGlowText(secondsText, size: 30)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.18, blue: 0.08),
                        Color(red: 0.35, green: 0.25, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.65, green: 0.5, blue: 0.25).opacity(0.5), lineWidth: 1)
                )
        )
        .accessibilityLabel("Track \(trackDigits), elapsed \(timeText)")
    }

    private var trackDigits: String {
        if let trackNumber, trackNumber > 0 {
            return String(format: "%02d", trackNumber)
        }
        return "--"
    }

    private var timeText: String {
        guard let elapsedSeconds, elapsedSeconds > 0 else {
            return "--:--"
        }
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func ledGlowText(_ value: String, size: CGFloat) -> some View {
        ZStack {
            Text(value)
                .font(.custom(fontName, size: size))
                .foregroundStyle(Color(red: 0.25, green: 0.35, blue: 0.3).opacity(0.35))
            Text(value)
                .font(.custom(fontName, size: size))
                .foregroundStyle(Color(red: 0.78, green: 0.95, blue: 0.86))
                .shadow(color: Color(red: 0.45, green: 0.9, blue: 0.8).opacity(0.9), radius: 6, x: 0, y: 0)
                .shadow(color: Color(red: 0.35, green: 0.8, blue: 0.7).opacity(0.6), radius: 12, x: 0, y: 0)
        }
    }

    private func colonText(size: CGFloat) -> some View {
        Text(":")
            .font(.system(size: size, weight: .thin, design: .default))
            .italic()
            .foregroundStyle(Color(red: 0.78, green: 0.95, blue: 0.86))
            .shadow(color: Color(red: 0.45, green: 0.9, blue: 0.8).opacity(0.9), radius: 6, x: 0, y: 0)
            .shadow(color: Color(red: 0.35, green: 0.8, blue: 0.7).opacity(0.6), radius: 12, x: 0, y: 0)
            .offset(y: -4)
    }

    private func labelGlowText(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .semibold, design: .default))
            .foregroundStyle(Color(red: 0.78, green: 0.95, blue: 0.86))
            .shadow(color: Color(red: 0.45, green: 0.9, blue: 0.8).opacity(0.9), radius: 6, x: 0, y: 0)
            .shadow(color: Color(red: 0.35, green: 0.8, blue: 0.7).opacity(0.6), radius: 12, x: 0, y: 0)
    }

    private var minutesText: String {
        guard let elapsedSeconds, elapsedSeconds > 0 else {
            return "--"
        }
        let minutes = Int(elapsedSeconds) / 60
        return String(format: "%02d", minutes)
    }

    private var secondsText: String {
        guard let elapsedSeconds, elapsedSeconds > 0 else {
            return "--"
        }
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d", seconds)
    }
}

private struct DiscIndicatorRow: View {
    let discSlots: [DiscSlot]
    let playingDiscIndex: Int?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(discSlots) { slot in
                DiscIndicatorView(
                    discNumber: slot.slotIndex,
                    isLoaded: slot.isLoaded,
                    isPlaying: slot.slotIndex == playingDiscIndex
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiscIndicatorView: View {
    let discNumber: Int
    let isLoaded: Bool
    let isPlaying: Bool

    private let ringSize: CGFloat = 18
    private let ringLineWidth: CGFloat = 1.4

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(ringColor, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .opacity(isLoaded ? 1 : 0)
            glowLabelText(String(discNumber), size: 10)
                .offset(y: 0.5)
            if isPlaying {
                PlayTriangle()
                    .fill(ringColor)
                    .frame(width: 6, height: 6)
                    .offset(x: ringSize / 2)
            }
        }
        .frame(width: ringSize + 2, height: ringSize + 2)
        .accessibilityHidden(!isLoaded)
    }

    private var ringColor: Color {
        Color(red: 0.78, green: 0.95, blue: 0.86)
    }

    private func glowLabelText(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .semibold, design: .default))
            .foregroundStyle(ringColor)
            .shadow(color: Color(red: 0.45, green: 0.9, blue: 0.8).opacity(0.9), radius: 5, x: 0, y: 0)
            .shadow(color: Color(red: 0.35, green: 0.8, blue: 0.7).opacity(0.6), radius: 9, x: 0, y: 0)
    }
}

private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
