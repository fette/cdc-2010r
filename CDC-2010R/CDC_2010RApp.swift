//
//  CDC_2010RApp.swift
//  CDC-2010R
//
//  Created by William Van Hecke on 2025/12/22.
//

import SwiftUI

@main
struct CDC_2010RApp: App {
    @StateObject private var appState: AppState

    init() {
        let fontName = FontRegistrar.register()
        _appState = StateObject(wrappedValue: AppState(ledFontName: fontName ?? "led16sgmnt2-Italic"))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
