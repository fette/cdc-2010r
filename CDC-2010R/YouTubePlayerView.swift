//
//  YouTubePlayerView.swift
//  CDC-2010R
//

import SwiftUI
import WebKit

/// WKWebView subclass that ensures clicks always reach the web content,
/// even when SwiftUI's focus system has another view focused.
class InteractiveWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct YouTubePlayerView: NSViewRepresentable {
    let videoID: String
    let appState: AppState

    private static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private static let hideUICSS = """
    html::-webkit-scrollbar { display: none !important; }
    html, body { overflow: hidden !important; }
    ytd-masthead, #masthead-container, #secondary, #below,
    #comments, #related, ytd-watch-metadata, #description,
    #info-contents, #meta, #actions, #menu, #top-row,
    #chips, #header, #page-manager > :not(ytd-watch-flexy),
    tp-yt-app-drawer, #guide, #guide-button, #back-button-container,
    ytd-mini-guide-renderer, ytd-popup-container,
    .ytp-chrome-top, .ytp-paid-content-overlay,
    .ytp-suggested-action, .ytp-endscreen-content,
    ytd-engagement-panel-section-list-renderer { display: none !important; }
    html, body, ytd-app, #content, ytd-page-manager,
    ytd-watch-flexy { background: #000 !important; }
    #player-container-outer, #player-container-inner,
    #player, #movie_player {
        position: fixed !important; top: 0 !important; left: 0 !important;
        width: 100vw !important; height: 100vh !important;
        max-width: none !important; max-height: none !important;
        margin: 0 !important; padding: 0 !important;
    }
    #player-container-outer { z-index: 9999 !important; }
    #primary { pointer-events: none !important; }
    #primary * { pointer-events: auto !important; }
    .html5-video-container, video {
        width: 100% !important; height: 100% !important;
    }
    video { object-fit: contain !important; }
    .ytp-ce-element, .html5-endscreen, .ytp-endscreen-content,
    .ytp-cards-teaser, .ytp-iv-player-content,
    .ytp-pause-overlay, .annotation,
    .ytp-ad-overlay-container, .ytp-player-content,
    .ytp-cued-thumbnail-overlay, .ytp-storyboard-framepreview {
        display: none !important;
    }
    """

    func makeNSView(context: Context) -> InteractiveWebView {
        let hideUIScript = WKUserScript(
            source: """
            var style = document.createElement('style');
            style.textContent = `\(Self.hideUICSS)`;
            document.head.appendChild(style);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(hideUIScript)
        let webView = InteractiveWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.underPageBackgroundColor = .black
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.currentVideoID = videoID
        appState.youtubeWebView = webView
        loadVideo(videoID, in: webView)
        return webView
    }

    func updateNSView(_ webView: InteractiveWebView, context: Context) {
        if context.coordinator.currentVideoID != videoID {
            context.coordinator.currentVideoID = videoID
            loadVideo(videoID, in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadVideo(_ videoID: String, in webView: WKWebView) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return }
        webView.load(URLRequest(url: url))
    }

    class Coordinator {
        var currentVideoID: String = ""
        weak var webView: WKWebView?
    }
}
