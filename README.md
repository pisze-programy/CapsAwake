<p align="center">
  <img src="assets/logo.png" width="110" alt="CapsAwake logo">
</p>

<h1 align="center">CapsAwake</h1>

<p align="center">
  <strong>Caps Lock · keep awake · even with the lid closed</strong>
</p>

<br>

<p align="center">
  Turn Caps Lock on. Your Mac stays awake.<br>
  Turn it off. Normal sleep returns.
</p>

---

## What it does

macOS puts a MacBook to sleep when you close the lid. That stops agents, builds, downloads, and SSH sessions.

CapsAwake makes Caps Lock the switch for that sleep:

- **Caps Lock ON** — the Mac does not sleep. The lid can be closed. Work continues.
- **Caps Lock OFF** — normal sleep behavior.

The menu-bar dot shows the state:

- Green — sleep is disabled. The Mac stays awake.
- Grey — normal sleep.
- Red — something is wrong. Move the cursor over the dot for the reason.

## How it works

CapsAwake has two parts:

1. **CapsAwake.app** — a small menu-bar app. It reads Caps Lock and the system sleep flag.
2. **CapsAwakeHelper** — a small root process. It runs one command: `pmset -a disablesleep 1|0`. This is the only way to keep a closed-lid MacBook awake.

The helper runs a watchdog. The app pings it every 30 seconds. If the app dies, the helper restores normal sleep within 90 seconds.

## Why it is not on the App Store

The Mac App Store requires a sandbox. A sandboxed app cannot run a root helper or disable system sleep. Apple does not allow this mechanism in the App Store or TestFlight. So CapsAwake ships as a signed and notarized app, outside the App Store.

## Install

```sh
./scripts/install.sh
```

What happens:

1. The script builds and signs the app.
2. It installs the app to `/Applications`.
3. It asks for your password once.
4. It opens the app.

On first launch, macOS may ask you to allow the helper. Open **System Settings → General → Login Items & Extensions** and allow CapsAwake.

CapsAwake starts at login. This is the default.

## Requirements

- Apple silicon MacBook
- macOS 14 or later
- Xcode (to build)
- An Apple Development certificate in your keychain

## Use

- Turn Caps Lock on to keep the Mac awake.
- Turn Caps Lock off to restore normal sleep.
- Right-click the dot to quit.

The green dot appears only when the system confirms sleep is disabled.

### Safety

A Mac that stays awake gets hot and drains the battery. CapsAwake turns itself off when:

- the battery drops to 15% while unplugged, or
- the Mac is under critical thermal pressure.

Turn Caps Lock off, then on, to retry.

## Uninstall

```sh
./scripts/uninstall.sh
```

This stops the app, unloads the helper, clears the sleep flag, and removes the app.

## Logs

- App log: `~/Library/Logs/CapsAwake/capsawake.log`
- Check the flag:

```sh
pmset -g | grep SleepDisabled
```

If the flag shows `1`, sleep is disabled. If the app was force-quit, the helper clears the flag within about 90 seconds.

## Build from source

```sh
xcodegen generate
./scripts/build-app.sh        # builds and signs CapsAwake.app
```

Run the tests:

```sh
xcodebuild -project CapsAwake.xcodeproj -scheme CapsAwake test
```

## Release

Build a notarized DMG:

```sh
./scripts/release.sh 0.1.0
```

Prerequisites:

- A Developer ID Application certificate in the keychain.
- Notary credentials: `xcrun notarytool store-credentials CAPSAWAKE_NOTARY ...`

## License

[MIT](LICENSE)
