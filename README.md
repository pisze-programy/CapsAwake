# CapsAwake

Caps Lock is the physical keep-awake switch for your MacBook.

Turn Caps Lock on and the Mac keeps working with the lid closed. Turn it off and normal sleep returns. The menu-bar dot shows the state: green means the Mac will not sleep, grey means normal sleep, red means something is wrong (hover the dot for the reason).

Made for AI agents, long builds, and remote sessions.

## How it works

Closing a MacBook lid normally sleeps the Mac. The only reliable override on Apple Silicon is the system `SleepDisabled` flag — what `sudo pmset -a disablesleep 1` sets. Ordinary keep-awake assertions (`caffeinate`) do not cover lid-close sleep.

CapsAwake cannot set that flag from a sandbox, so it is not on the Mac App Store. Instead the app ships with a small privileged helper:

- `CapsAwake.app` runs as a normal user. It reads Caps Lock (IOKit HID, no permissions) and the flag (`pmset -g`) every poll.
- `CapsAwakeHelper` is a root launchd daemon embedded in the app and registered through `SMAppService`. The only thing it does is run `pmset -a disablesleep 1|0`. The app talks to it over XPC; the daemon accepts calls only from this app, signed by this team.
- The daemon runs a watchdog. The app heartbeats every 30 seconds. If the app dies while the flag is on, the daemon restores normal sleep within 90 seconds. The watchdog reads the real flag, so it also survives a daemon restart.

Launch-at-login is enabled by default on first launch.

## Requirements

- Apple Silicon MacBook, macOS 14 or later.
- Xcode command line tools (to build).
- An Apple Development certificate in your keychain to sign the helper (team `3UKH2QRFKZ`). Open Xcode once to install it if signing fails.

## Install

```sh
./scripts/install.sh
```

This builds and signs the app, installs it to `/Applications`, and launches it once. The first launch registers the helper. macOS may ask you to approve it in **System Settings → General → Login Items & Extensions**; the app offers to open that page.

### Run from Xcode

Open `CapsAwake.xcodeproj` (or generate it with `xcodegen generate`). Pick the `CapsAwake` scheme and run. The helper registers only when the app runs from `/Applications`, so use the install script for a full test.

## Use

- Caps Lock **on** → the Mac stays awake, lid open or closed. Green dot.
- Caps Lock **off** → normal sleep. Grey dot.
- Right-click the dot → Quit.

The dot is green only when the system flag is confirmed on. If the helper is missing, not approved, or failing, the dot turns red and an alert explains what to do.

### Safety

A Mac left running in a bag gets hot and drains the battery. CapsAwake turns itself off automatically when:

- the battery drops below 15% while unplugged, or
- the Mac hits critical thermal pressure.

Turn Caps Lock off and on to retry once conditions are safe.

### Notes

- Sleep prevention is system-wide while active. A reboot always clears the flag.
- If a remote desktop client syncs Caps Lock to your Mac, it also turns the switch. Closing the lid does not change this.
- Quitting restores normal sleep. If the app is force-killed, the helper watchdog restores sleep within ~90 seconds.

## Logs

- App: `~/Library/Logs/CapsAwake/capsawake.log`
- Helper: `/Library/Logs/CapsAwake/helper-stderr.log`

Check the flag from a terminal:

```sh
pmset -g | grep SleepDisabled
```

## Uninstall

```sh
./scripts/uninstall.sh
```

This stops the app, unloads the helper, clears the flag, and removes the app.

## Layout

```
Sources/CapsAwake/        menu-bar app
  App/                    lifecycle, status item
  Core/                   decision engine
  Hardware/               Caps Lock + flag readers
  Services/               helper XPC client, login item
  Support/                config, logging
Sources/CapsAwakeHelper/  root daemon
Sources/CapsAwakeShared/  parsers, policies, protocol, identity
Tests/CapsAwakeTests/     unit tests
scripts/                  build, install, uninstall
```

## License

MIT. See [LICENSE](LICENSE).
