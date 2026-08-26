# PPTRemote

Advance your slides with the buttons on your Bluetooth headphones.

A tiny macOS menu bar app that turns headset media buttons into Page Down /
Page Up for PowerPoint and Keynote. No extra hardware, no clicker to forget at
home — if your earbuds are in your ears, you already have a presentation remote.

Roughly 300 lines of Swift, no dependencies, no network access.

## Why

Presentation clickers are one more thing to own, charge, and lose. Your
headphones are already paired to your Mac and already have buttons. This maps
those buttons onto the two keystrokes that actually matter when presenting.

## How it works

The app registers as a Now Playing client via `MPRemoteCommandCenter`, the same
mechanism Spotify or Music use to receive headset button presses. When a press
arrives, it synthesises a Page Down or Page Up key event and delivers it
straight to the PowerPoint or Keynote process.

That last part matters. Events are posted to the target process by pid rather
than to the global event tap, so they land in your slideshow even when another
window has keyboard focus — notably the floating share toolbar that Teams and
Zoom put on top of everything while you present.

## Requirements

- macOS 13 or later
- Xcode command line tools (`xcode-select --install`) for `swiftc`
- Bluetooth headphones with at least one media button

## Install

```sh
git clone https://github.com/githendrik/ppt-remote.git
cd ppt-remote
./build.sh
```

`build.sh` compiles the app, ad-hoc signs it, and copies it to `/Applications`.
Pass `--no-install` to build in place without touching `/Applications`.

Launch it, and grant **Accessibility** permission when prompted
(System Settings → Privacy & Security → Accessibility). Without it macOS blocks
synthetic key events and the app will appear to do nothing.

> Rebuilding changes the ad-hoc signature, which can invalidate the existing
> permission grant. If it stops working after a rebuild, remove the entry with
> `−` and re-add `/Applications/PPTRemote.app`.

## Usage

A `▶︎` icon appears in the menu bar. Open a presentation, start your slideshow,
and press a button on your headphones.

### Button mapping

Assign whichever buttons your headphones actually have under **Next slide** and
**Previous slide** in the menu:

| Option | Headset button |
| --- | --- |
| Play / Pause | single press on the main button |
| Skip Forward | next track |
| Skip Back | previous track |
| Unset | direction disabled |

Many earbuds report a single press on either bud as play/pause, so mapping
**Next slide → Play / Pause** and leaving **Previous slide** unset is a common
and perfectly usable setup — forward-only is most of what presenting needs.

A given button can only mean one thing. Assigning a button that is already used
by the other direction clears it from that other direction.

### Other options

- **Enabled** — master switch. The icon dims to `▷` when off.
- **Send only to PowerPoint / Keynote** — deliver keys to the presentation app
  whenever it is running, rather than to whatever is focused. On by default.
  Turn it off to control any app that responds to Page Up / Page Down.
- **Silent audio keep-alive** — plays inaudible silence to hold an A2DP stream
  open. Some headphones only emit media commands while audio is streaming. Try
  this if presses are ignored while nothing is playing.

Settings persist across restarts.

## Known limitation: Teams and Zoom meetings

**While you are in a meeting with your headset selected as the microphone, the
buttons will not work.** This is a Bluetooth-level constraint, not a bug that
can be fixed in this app.

Outside a call your headset runs the A2DP profile, where a button press is an
AVRCP media command that macOS routes to this app. The moment a meeting app
claims the microphone, the headset switches to the HFP (hands-free) profile and
that same button becomes a *call control* button. The press never enters the
media key path, so the app never sees it.

**Workaround:** use a different microphone. In Teams → Settings → Devices, set
**Microphone** to your Mac's built-in mic or a separate headset, leaving the
earbuds as **Speaker** only. They stay in A2DP for the whole meeting and the
buttons keep working.

## Troubleshooting

Watch the log while pressing a button:

```sh
log stream --predicate 'eventMessage CONTAINS "PPTRemote"' --info
```

| What you see | Meaning |
| --- | --- |
| `received <command>` then the slide moves | Working. |
| `received …` but `unmapped` | That button is not assigned in the menu. |
| `received …` but `no PowerPoint/Keynote running` | Start a presentation, or turn off "Send only to PowerPoint / Keynote". |
| `received …` but nothing happens | Accessibility permission is missing or stale. |
| Nothing at all | Another app owns the headset buttons — see the meetings section above. |

## Licence

MIT
