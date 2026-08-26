import AppKit
import AVFoundation
import MediaPlayer

// MARK: - Key injection

enum SlideKey {
    case next
    case previous

    var virtualKey: CGKeyCode {
        switch self {
        case .next: return 121      // Page Down
        case .previous: return 116  // Page Up
        }
    }
}

/// A physical button on the headset, as macOS reports it.
enum RemoteButton: String, CaseIterable {
    case playPause
    case nextTrack
    case previousTrack

    var title: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Skip Forward"
        case .previousTrack: return "Skip Back"
        }
    }
}

/// Deliver the key stroke.
///
/// When a Teams screen share is running, its floating control bar takes
/// keyboard focus, so an event posted to the global HID tap lands in Teams
/// instead of the slideshow. Posting straight to the target process bypasses
/// focus entirely, which keeps the remote working while sharing.
func sendKey(_ key: SlideKey, toPid pid: pid_t?) {
    guard let src = CGEventSource(stateID: .hidSystemState) else {
        NSLog("PPTRemote: could not create event source")
        return
    }
    let down = CGEvent(keyboardEventSource: src, virtualKey: key.virtualKey, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: key.virtualKey, keyDown: false)

    if let pid {
        down?.postToPid(pid)
        up?.postToPid(pid)
    } else {
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - Silent audio keep-alive
//
// Optional. Some headphones only emit AVRCP transport commands while an A2DP
// stream is active. This plays inaudible silence to keep that stream up.

final class SilenceKeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    func start() {
        guard !started else { return }
        let fmt = engine.outputNode.inputFormat(forBus: 0)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096) else { return }
        buf.frameLength = 4096
        for ch in 0..<Int(fmt.channelCount) {
            if let data = buf.floatChannelData?[ch] {
                for i in 0..<Int(buf.frameLength) { data[i] = 0 }
            }
        }
        engine.attach(player)
        engine.connect(player, to: engine.outputNode, format: fmt)
        do {
            try engine.start()
            player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
            player.play()
            started = true
            NSLog("PPTRemote: silence keep-alive started")
        } catch {
            NSLog("PPTRemote: silence keep-alive failed: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        started = false
        NSLog("PPTRemote: silence keep-alive stopped")
    }
}

// MARK: - App

let powerPointBundleIDs: Set<String> = [
    "com.microsoft.Powerpoint",
    "com.apple.iWork.Keynote",
]

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: NSStatusItem!
    private let silence = SilenceKeepAlive()

    private var enabled = true
    private var powerPointOnly = true
    private var silenceEnabled = false

    /// Which headset button drives each direction. `nil` means unassigned.
    ///
    /// Both directions may point at the same button, in which case the older
    /// assignment is cleared - one button cannot mean two things.
    private var forwardButton: RemoteButton? = .playPause
    private var backwardButton: RemoteButton? = .previousTrack

    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ note: Notification) {
        loadSettings()
        requestAccessibilityIfNeeded()
        setUpStatusItem()
        setUpRemoteCommands()
        becomeNowPlayingClient()
        NSLog("PPTRemote: ready (forward=\(forwardButton?.rawValue ?? "unset"), "
              + "backward=\(backwardButton?.rawValue ?? "unset"))")
    }

    // MARK: Settings

    private func loadSettings() {
        if defaults.object(forKey: "enabled") != nil {
            enabled = defaults.bool(forKey: "enabled")
            powerPointOnly = defaults.bool(forKey: "powerPointOnly")
            silenceEnabled = defaults.bool(forKey: "silenceEnabled")
            forwardButton = RemoteButton(rawValue: defaults.string(forKey: "forwardButton") ?? "")
            backwardButton = RemoteButton(rawValue: defaults.string(forKey: "backwardButton") ?? "")
        }
        if silenceEnabled { silence.start() }
    }

    private func saveSettings() {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(powerPointOnly, forKey: "powerPointOnly")
        defaults.set(silenceEnabled, forKey: "silenceEnabled")
        defaults.set(forwardButton?.rawValue, forKey: "forwardButton")
        defaults.set(backwardButton?.rawValue, forKey: "backwardButton")
    }

    // MARK: Permissions

    private func requestAccessibilityIfNeeded() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        if !trusted {
            NSLog("PPTRemote: waiting on Accessibility permission")
        }
    }

    // MARK: Now playing

    private func becomeNowPlayingClient() {
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "PowerPoint Remote",
            MPMediaItemPropertyArtist: "Headphone slide control",
            MPMediaItemPropertyPlaybackDuration: NSNumber(value: 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: NSNumber(value: 0),
            MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: 1.0),
        ]
        info.playbackState = .playing
    }

    private func setUpRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        // Play/pause arrives as any of three commands depending on the
        // headset's view of playback state, so treat all three as one button.
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handle(.playPause, source: "togglePlayPause") ?? .commandFailed
        }
        cc.playCommand.addTarget { [weak self] _ in
            self?.handle(.playPause, source: "play") ?? .commandFailed
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.handle(.playPause, source: "pause") ?? .commandFailed
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.handle(.nextTrack, source: "nextTrack") ?? .commandFailed
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.handle(.previousTrack, source: "previousTrack") ?? .commandFailed
        }

        // Every command stays enabled regardless of mapping: an unmapped
        // button must still be claimed by us, otherwise macOS may hand the
        // whole Now Playing slot to another app.
        for cmd in [cc.togglePlayPauseCommand, cc.playCommand, cc.pauseCommand,
                    cc.nextTrackCommand, cc.previousTrackCommand] {
            cmd.isEnabled = true
        }
    }

    /// The running PowerPoint / Keynote process, if any.
    ///
    /// Deliberately *not* `frontmostApplication`: while sharing in Teams the
    /// frontmost app is Teams' share toolbar, not the slideshow.
    private func presentationApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            guard let id = $0.bundleIdentifier else { return false }
            return powerPointBundleIDs.contains(id)
        }
    }

    private func handle(_ button: RemoteButton, source: String) -> MPRemoteCommandHandlerStatus {
        NSLog("PPTRemote: received \(source)")

        // Even when we ignore a press we report success. Returning
        // .commandFailed makes macOS treat us as a dead Now Playing client and
        // hand the headset buttons to whoever else is playing audio - during a
        // Teams call, that is Teams.
        guard enabled else { return .success }

        let key: SlideKey
        if button == forwardButton {
            key = .next
        } else if button == backwardButton {
            key = .previous
        } else {
            NSLog("PPTRemote: ignoring, \(button.rawValue) is unmapped")
            return .success
        }

        var targetPid: pid_t?

        if powerPointOnly {
            guard let app = presentationApp() else {
                NSLog("PPTRemote: ignoring, no PowerPoint/Keynote running")
                return .success
            }
            targetPid = app.processIdentifier
        }

        sendKey(key, toPid: targetPid)

        // Keep the system believing we are still playing, otherwise the next
        // button press may not be routed to us.
        MPNowPlayingInfoCenter.default().playbackState = .playing
        return .success
    }

    // MARK: Menu

    private var forwardMenu: NSMenu!
    private var backwardMenu: NSMenu!

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = enabled ? "▶︎" : "▷"

        forwardMenu = buttonMenu(#selector(setForwardButton(_:)))
        backwardMenu = buttonMenu(#selector(setBackwardButton(_:)))

        let menu = NSMenu()
        menu.addItem(item("Enabled", #selector(toggleEnabled), enabled))
        menu.addItem(item("Send only to PowerPoint / Keynote", #selector(togglePPTOnly), powerPointOnly))
        menu.addItem(item("Silent audio keep-alive", #selector(toggleSilence), silenceEnabled))
        menu.addItem(.separator())

        let fwd = NSMenuItem(title: "Next slide", action: nil, keyEquivalent: "")
        fwd.submenu = forwardMenu
        menu.addItem(fwd)

        let back = NSMenuItem(title: "Previous slide", action: nil, keyEquivalent: "")
        back.submenu = backwardMenu
        menu.addItem(back)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        refreshButtonMenus()

        // A crowded menu bar (especially on notched displays) can push a new
        // status item off-screen, where it exists but is unreachable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            let frame = self?.statusItem.button?.window?.frame
            NSLog("PPTRemote: status item frame = \(frame.map(NSStringFromRect) ?? "nil")")
        }
    }

    /// One radio-style menu listing every button, plus "Unset".
    private func buttonMenu(_ action: Selector) -> NSMenu {
        let menu = NSMenu()
        for button in RemoteButton.allCases {
            let mi = NSMenuItem(title: button.title, action: action, keyEquivalent: "")
            mi.target = self
            mi.representedObject = button.rawValue
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let none = NSMenuItem(title: "Unset", action: action, keyEquivalent: "")
        none.target = self
        none.representedObject = nil
        menu.addItem(none)
        return menu
    }

    private func refreshButtonMenus() {
        for (menu, selected) in [(forwardMenu!, forwardButton), (backwardMenu!, backwardButton)] {
            for mi in menu.items where !mi.isSeparatorItem {
                let raw = mi.representedObject as? String
                mi.state = (raw == selected?.rawValue) ? .on : .off
            }
        }
    }

    /// Assign `button` to one direction, clearing it from the other so a
    /// single physical button never maps to both.
    private func assign(_ button: RemoteButton?, forward: Bool) {
        if forward {
            if button != nil, button == backwardButton { backwardButton = nil }
            forwardButton = button
        } else {
            if button != nil, button == forwardButton { forwardButton = nil }
            backwardButton = button
        }
        refreshButtonMenus()
        saveSettings()
    }

    @objc private func setForwardButton(_ sender: NSMenuItem) {
        assign(RemoteButton(rawValue: sender.representedObject as? String ?? ""), forward: true)
    }

    @objc private func setBackwardButton(_ sender: NSMenuItem) {
        assign(RemoteButton(rawValue: sender.representedObject as? String ?? ""), forward: false)
    }

    private func item(_ title: String, _ action: Selector, _ on: Bool) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.state = on ? .on : .off
        return mi
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        sender.state = enabled ? .on : .off
        statusItem.button?.title = enabled ? "▶︎" : "▷"
        saveSettings()
    }

    @objc private func togglePPTOnly(_ sender: NSMenuItem) {
        powerPointOnly.toggle()
        sender.state = powerPointOnly ? .on : .off
        saveSettings()
    }

    @objc private func toggleSilence(_ sender: NSMenuItem) {
        silenceEnabled.toggle()
        sender.state = silenceEnabled ? .on : .off
        silenceEnabled ? silence.start() : silence.stop()
        saveSettings()
    }
}
