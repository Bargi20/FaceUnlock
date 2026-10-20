//
//  NotchUnlockApp.swift
//  NotchUnlock
//
//  Menu bar app: settings window with the Apple-style enrollment, and a
//  transparent window over the notch from which the Face ID square drops
//  when the Mac is locked.
//

import AppKit
import Combine
import SkyLightWindow
import SwiftUI

@main
struct NotchUnlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NotchUnlock", systemImage: "faceid") {
            Button("Settings…") { appDelegate.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit NotchUnlock") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var notchWindow: NotchSquareWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if DemoRenderer.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NotchUnlockManager.shared.start()
        notchWindow = NotchSquareWindow()
        // Ask for every permission up front instead of when each is first needed.
        if !NotchUnlockManager.shared.allPermissionsGranted {
            NotchUnlockManager.shared.requestAllPermissions()
        }

        // First run: nothing enrolled yet, open the settings with the setup flow.
        if !NotchUnlockManager.shared.hasEnrollment {
            showSettings()
        }
    }

    /// Opening the app again (Finder, Spotlight) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "NotchUnlock"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: NotchUnlockSettings().frame(minWidth: 480, minHeight: 520))
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Back to a menu-bar-only app when the settings close.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - Notch window

/// Borderless, transparent panel at the top-center of the built-in screen.
/// Click-through until the Face ID square is showing; lifted above the lock
/// screen with SkyLight while the session is locked.
@MainActor
final class NotchSquareWindow {
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var skyLightEnabled = false
    private static let size = NSSize(width: 420, height: 240)

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .init(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let screen = Self.notchScreen
        let notchHeight = max(screen?.safeAreaInsets.top ?? 0, 32)
        panel.contentView = NSHostingView(rootView: NotchSquareRoot(notchHeight: notchHeight))
        position()
        panel.orderFrontRegardless()

        // Only catch the mouse while the square is visible.
        NotchUnlockManager.shared.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.panel.ignoresMouseEvents = phase == .hidden }
            .store(in: &cancellables)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSkyLight(true) }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setSkyLight(false) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    /// The built-in display (the one with the notch), else the main one.
    private static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func position() {
        guard let screen = Self.notchScreen else { return }
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.maxY - Self.size.height))
    }

    private func setSkyLight(_ enabled: Bool) {
        guard enabled != skyLightEnabled else { return }
        skyLightEnabled = enabled
        if enabled {
            SkyLightOperator.shared.delegateWindow(panel)
        }
        panel.orderFrontRegardless()
    }
}

private struct NotchSquareRoot: View {
    @ObservedObject var manager = NotchUnlockManager.shared
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if manager.phase != .hidden {
                FaceIDSquare(notchHeight: notchHeight)
                    .transition(
                        .scale(scale: 0.25, anchor: .top)
                            .combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opens with a soft spring, closes quickly.
        .animation(manager.phase == .hidden ? .smooth(duration: 0.22) : .spring(response: 0.5, dampingFraction: 0.78),
                   value: manager.phase == .hidden)
    }
}
