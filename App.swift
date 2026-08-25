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

func sendKey(_ key: SlideKey) {
    guard let src = CGEventSource(stateID: .hidSystemState) else {
        NSLog("PPTRemote: could not create event source")
        return
    }
    let down = CGEvent(keyboardEventSource: src, virtualKey: key.virtualKey, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: key.virtualKey, keyDown: false)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
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

    func applicationDidFinishLaunching(_ note: Notification) {
        requestAccessibilityIfNeeded()
        setUpStatusItem()
        setUpRemoteCommands()
        becomeNowPlayingClient()
        NSLog("PPTRemote: ready")
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

        // Play/pause arrive as separate commands depending on the headset's
        // view of playback state, so handle all three.
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handle(.next, source: "togglePlayPause") ?? .commandFailed
        }
        cc.playCommand.addTarget { [weak self] _ in
            self?.handle(.next, source: "play") ?? .commandFailed
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.handle(.next, source: "pause") ?? .commandFailed
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.handle(.next, source: "nextTrack") ?? .commandFailed
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.handle(.previous, source: "previousTrack") ?? .commandFailed
        }

        for cmd in [cc.togglePlayPauseCommand, cc.playCommand, cc.pauseCommand,
                    cc.nextTrackCommand, cc.previousTrackCommand] {
            cmd.isEnabled = true
        }
    }

    private func handle(_ key: SlideKey, source: String) -> MPRemoteCommandHandlerStatus {
        NSLog("PPTRemote: received \(source)")

        guard enabled else { return .commandFailed }

        if powerPointOnly {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            guard powerPointBundleIDs.contains(front) else {
                NSLog("PPTRemote: ignoring, frontmost is \(front)")
                return .commandFailed
            }
        }

        sendKey(key)

        // Keep the system believing we are still playing, otherwise the next
        // button press may not be routed to us.
        MPNowPlayingInfoCenter.default().playbackState = .playing
        return .success
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "▶︎"

        let menu = NSMenu()
        menu.addItem(item("Enabled", #selector(toggleEnabled), enabled))
        menu.addItem(item("Only in PowerPoint / Keynote", #selector(togglePPTOnly), powerPointOnly))
        menu.addItem(item("Silent audio keep-alive", #selector(toggleSilence), silenceEnabled))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
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
    }

    @objc private func togglePPTOnly(_ sender: NSMenuItem) {
        powerPointOnly.toggle()
        sender.state = powerPointOnly ? .on : .off
    }

    @objc private func toggleSilence(_ sender: NSMenuItem) {
        silenceEnabled.toggle()
        sender.state = silenceEnabled ? .on : .off
        silenceEnabled ? silence.start() : silence.stop()
    }
}
