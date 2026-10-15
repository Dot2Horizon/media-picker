# MediaPicker

**Hold F8 to choose what plays.** A macOS menu bar app that stops a paused YouTube tab from stealing your play key, and lets you pick the media you want — with one hand, without leaving the function row.

[한국어](README.ko.md)

## Keys

| Key | Picker closed | Picker open |
|---|---|---|
| F8 tap | Pause what's playing / resume the last one | Move to the next item |
| F8 hold | Open the picker | Play/pause the highlighted item and close |
| F7 / F9 | Previous / next for what's playing | Previous / next for the highlighted item |
| F10 / F11 / F12 | System mute / volume | Mute / volume for the highlighted item only |

## What it controls

- Spotify, Music, TV, VLC
- Tabs in Chrome, Edge, Brave, Arc (with the browser extension)
- Safari tabs (with "Allow JavaScript from Apple Events", or the Safari extension if you build from source)
- Any other app making sound, via the system media key

## Install

1. Download `MediaPicker-x.y.z.dmg` from [Releases](../../releases) and drag MediaPicker to Applications.
2. **First launch:** this build is not notarized by Apple, so macOS blocks it the first time.
   Open it once, then go to **System Settings › Privacy & Security** and click **Open Anyway**.
   (Or run `xattr -dr com.apple.quarantine /Applications/MediaPicker.app` in Terminal.)
3. Grant **Accessibility** permission when asked — MediaPicker needs it to intercept the media keys.
   Updates are signed with the same certificate, so you only do this once.
4. Browser tabs: menu bar icon › **Install Browser Extension…** and follow the steps.

Requires macOS 14 or later. Apple Silicon and Intel.

## Build from source

```sh
./build.sh --install   # build and install to /Applications
./release.sh           # make dist/ (DMG, zip, extension zip, checksums)
```

The Safari extension ships inside the app but, without an Apple Developer ID, Safari only shows it after
**Safari › Settings › Developer › Allow unsigned extensions** (resets when Safari quits).

## Privacy

Everything stays on your Mac. The browser extension talks only to the app on `127.0.0.1:17872`,
and the app accepts connections only from browser extensions. No analytics, no network requests.

## License

MIT
