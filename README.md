<div align="center">

# 🎤 PPTRemote

### Your $300 headphones are also a presentation clicker. You just didn't know it yet.

**Stop buying dongles. Start clicking with your ears.** 👂✨

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-300%20lines-orange?logo=swift)
![Dependencies](https://img.shields.io/badge/dependencies-absolutely%20zero-brightgreen)
![Cloud](https://img.shields.io/badge/cloud-none%2C%20ever-blue)

</div>

---

## 😱 The Problem

You're about to present. You reach into your bag.

**The clicker is not in your bag.**

It's on your desk. At home. Battery dead anyway. So now you're doing *The Presenter's Shuffle* — walking back to the laptop, tapping the spacebar, walking away again. Forty-five times. Your audience counts every trip. Somebody starts a tally on the whiteboard. 📊

**There has to be a better way.**

## 🤯 The Solution

There is. It's been in your ears this whole time.

PPTRemote turns the buttons on your Bluetooth headphones into slide controls. That's it. That's the whole app.

- 🎧 **Your earbuds are already paired.** Already charged. Already on your head.
- 🚫 **Nothing new to buy.** Nothing new to lose. Nothing new to forget.
- 🪶 **~300 lines of Swift.** No frameworks. No Electron. No 400 MB of `node_modules`.
- 🔒 **Zero network access.** This app could not phone home if you begged it to.
- 🆓 **Free forever.** There is no Pro tier. There is no newsletter. There is no Discord.

> *"I used to walk to my laptop like an animal."*
> — a person, probably

---

## ⚡ Sixty Second Setup

```sh
brew tap githendrik/tap
brew trust githendrik/tap
brew install ppt-remote

ln -sfn "$(brew --prefix)/opt/ppt-remote/PPTRemote.app" /Applications/PPTRemote.app
open /Applications/PPTRemote.app
```

<details>
<summary>🤨 Why <code>brew trust</code>?</summary>

Homebrew 6 refuses to run code from third-party taps until you say so — a good
default, since a formula is just Ruby that executes on your machine. You'll get
`Refusing to load formula ... from untrusted tap` without it. Read
[the formula](https://github.com/githendrik/homebrew-tap/blob/main/Formula/ppt-remote.rb)
first if you like; it's 40 lines and it calls `build.sh`.

</details>

<details>
<summary>🙅 Prefer to clone it yourself?</summary>

```sh
git clone https://github.com/githendrik/ppt-remote.git
cd ppt-remote
./build.sh
```

</details>

Homebrew compiles it **on your machine**, which is the entire trick: locally
built binaries are never quarantined, so there's no "unidentified developer"
dialog, no `xattr` incantation, and no $99/year Apple tax. 🎩

Upgrades are the usual `brew upgrade ppt-remote`. ⚠️ Each upgrade rebuilds and
re-signs the app, which **invalidates the Accessibility grant** — see below.

Launch it. Grant **Accessibility** when macOS asks (System Settings → Privacy & Security → Accessibility). Without that, macOS blocks synthetic key events and the app sits there looking innocent while doing absolutely nothing. 🙈

Look for `▶︎` in your menu bar. **Congratulations. You are now a cyborg.** 🤖

<details>
<summary>🛠 Requirements (boring but necessary)</summary>

- macOS 13 or later
- Xcode command line tools — `xcode-select --install`
- Bluetooth headphones with at least one button

`build.sh` compiles, ad-hoc signs, and installs to `/Applications`. Use `--no-install` to build in place. Set `PPTREMOTE_ARCHS="arm64 x86_64"` for a universal bundle.

⚠️ Rebuilding (or upgrading via brew) changes the ad-hoc signature, which invalidates the Accessibility grant. If it mysteriously stops working afterwards, remove the entry with `−` and re-add `/Applications/PPTRemote.app`.

</details>

---

## 🎛 Map Your Buttons Like A Pro

Menu bar → **Next slide** / **Previous slide** → pick your poison:

| Option | What you press | Vibe |
| --- | --- | --- |
| ▶️ Play / Pause | single press, main button | the classic |
| ⏭ Skip Forward | next track | for the multi-button elite |
| ⏮ Skip Back | previous track | going backwards, bravely |
| 🚫 Unset | nothing | disabled |

**Only got one usable button?** Extremely common — most earbuds report a single press on either bud as play/pause. Map **Next slide → Play / Pause**, leave **Previous slide → Unset**, and get on with your life. Forward-only covers 95% of presenting. 🏃

One button = one meaning. Assign a button that's already taken and it gets yanked from the other direction. No ambiguity, no surprises. ✂️

<details>
<summary>⚙️ The other switches</summary>

- **Enabled** — master kill switch. Icon dims to `▷` when off.
- **Send only to PowerPoint / Keynote** — routes keys to the presentation app whenever it's running, instead of whatever's focused. On by default. Turn it off to drive anything that responds to Page Up / Page Down.
- **Silent audio keep-alive** — plays inaudible silence to hold an A2DP stream open. Some headphones only emit media commands while audio is streaming. Try it if presses vanish into the void.

Everything persists across restarts, because it's not 2009.

</details>

---

## 🧠 How It Actually Works

<details>
<summary>Click if you enjoy knowing things</summary>

PPTRemote registers as a Now Playing client via `MPRemoteCommandCenter` — the same door Spotify and Music use to catch headset button presses. A press arrives, the app synthesises a Page Down or Page Up, and delivers it **straight to the PowerPoint or Keynote process by pid**.

That last detail is the good part. 🎯

Most apps post to the global event tap, which delivers to whatever holds keyboard focus. But the moment you share your screen, Teams and Zoom slap a floating toolbar on top of everything and *take that focus*. Global-tap events land in the toolbar. Your slides don't move. You look unprepared in front of forty people.

Posting by pid sidesteps focus entirely. The slideshow gets the keystroke whether or not it's frontmost. 💪

</details>

---

## 😤 The One Thing It Can't Do

**In a Teams or Zoom meeting with your headset as the microphone, the buttons won't work.**

Not a bug. Not fixable in this app. Not fixable in *any* app. Here's the honest reason:

Outside a call your headset runs the **A2DP** profile, where a button press is an AVRCP media command that macOS hands to this app. The instant a meeting app claims your microphone, the headset flips to the **HFP** (hands-free) profile — and that same button becomes a *call control* button. The press never enters the media key path at all. This app is never told it happened. 📵

### ✅ The Fix Is Ten Seconds Long

**Use a different microphone.** Teams → Settings → Devices → set **Microphone** to your Mac's built-in mic or any other headset. Leave the earbuds as **Speaker** only.

Your earbuds stay in A2DP for the entire meeting. The buttons keep working. You keep your dignity. 🎉

---

## 🔧 When Things Go Sideways

Watch the app think:

```sh
log stream --predicate 'eventMessage CONTAINS "PPTRemote"' --info
```

| What you see | What it means |
| --- | --- |
| ✅ `received <command>` + slide moves | It works. Go present. |
| 🤷 `received …` then `unmapped` | Button isn't assigned. Check the menu. |
| 📄 `received …` then `no PowerPoint/Keynote running` | Open a presentation, or disable "Send only to PowerPoint / Keynote". |
| 🔒 `received …` and nothing happens | Accessibility permission missing or stale after a rebuild. |
| 👻 Absolutely nothing | Another app owns your headset buttons. See the section above. |

<details>
<summary>🫥 "The menu bar icon is gone!"</summary>

Your menu bar is probably full — a notch plus too many extras means macOS creates the status item and then parks it off-screen where you can't reach it.

The log tells you outright:

```
PPTRemote: status item frame = {{-4232, 1084}, {31, 33}}
```

A large negative x means off-screen. Quit a few menu bar apps, or grab a menu bar manager like [Ice](https://github.com/jordanbaird/Ice) (free) or Bartender.

</details>

---

<div align="center">

### ⭐ Star this repo if you've ever done The Presenter's Shuffle

**MIT licensed. Go wild.**

*Built because buying a clicker felt like admitting defeat.* 🏳️

</div>
