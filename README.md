<div align="center">

<img src="docs/images/icon.png" width="128" height="128" alt="TunnelDeck icon">

<h1>TunnelDeck</h1>

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black) ![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange) ![License: MIT](https://img.shields.io/badge/License-MIT-blue)

**A menu bar app for SSH local port forwards that hands every connection to the ssh already on your Mac.**

Keep a list of tunnels, such as a bastion host forwarding local ports to databases, and turn each one on or off from the menu bar. TunnelDeck reconnects dropped tunnels, tells you which program holds a busy port, and never stores a password or key.

</div>

## Who is this for?

People who reach private databases or services through an SSH bastion and are tired of starting `ssh -L` by hand, or of keeping an unmaintained tunnel manager around. TunnelDeck runs `/usr/bin/ssh` for every tunnel, so your `~/.ssh/config`, `known_hosts`, ssh-agent and Keychain keep working exactly as they do in Terminal.

## Features

- **One switch per tunnel**: start and stop each tunnel from the menu. A tunnel can forward several local ports through the same SSH connection.
- **Status at a glance**: the menu bar icon gets a green, orange or red badge when a tunnel is connected, connecting or failed, and stays plain when everything is stopped.
- **Details in the menu**: each tunnel shows its destination, every forward's remote target, whether the local port is listening, how long it has been up and how often it reconnected.
- **Who is connected**: under each forward, the programs using it right now, such as your database client or a Rails console, with their app icon and PID.
- **Automatic reconnect**: a tunnel that drops after running for 30 seconds or more reconnects right away. After that, or when it drops sooner, it waits between attempts, starting at 2 to 4 seconds and doubling up to every 30 seconds. Waking from sleep or getting a network back retries right away.
- **Clear failures**: errors that retrying can't fix, such as a rejected key, a changed host key or a broken `~/.ssh/config`, stop the tunnel and say what to do. A busy local port names the program holding it, with its PID.
- **Notifications** when an automatic reconnect fails or a tunnel stops on its own.
- **Inspection**: per-tunnel ssh log and the equivalent `ssh` command, ready to paste into Terminal.
- **English and Traditional Chinese** interface, switchable in Preferences.
- **Safe defaults**: see [Security](#security).

## Usage

1. Click the TunnelDeck icon in the menu bar, then **Settings**.
2. Click **+** and fill in the tunnel:

   | Field | Value |
   |---|---|
   | **Name** | Any label |
   | **Host** | Host name or IP address of the SSH server, or a `Host` from `~/.ssh/config`. Letters, digits, dots and hyphens only, so an alias with an underscore is rejected. |
   | **User** | Optional. Leave empty to use `~/.ssh/config` or your login name. |
   | **SSH port** | Optional, 22 by default |
   | **Identity file** | Optional. Leave as **ssh default** to let ssh pick the key. |
   | **Forwards** | One row per forward: local port, remote host and remote port. The local side always listens on `127.0.0.1`. |

3. Click **Add**, then turn the tunnel on from the menu.

Before the first connection to a new server, run `ssh <host>` once in Terminal and confirm its fingerprint. TunnelDeck runs ssh without prompts, so it can't accept an unknown host key, and a key with a passphrase must already be in ssh-agent or your Keychain.

Click a tunnel in the menu to open it in Settings, where **Overview**, **Configuration** and **Log** show its details. Saving a running tunnel reconnects it.

**Preferences…** at the bottom of the Settings sidebar switches the language between English (default) and 繁體中文.

## Install

### Homebrew (recommended)

```bash
brew tap ff2248/tunneldeck
brew install --cask tunneldeck
```

On first launch, see [Approve first launch](#approve-first-launch).

### Direct download

Download the latest `TunnelDeck-vX.Y.Z.dmg` from [Releases](https://github.com/ff2248/TunnelDeck/releases/latest), open it, and drag **TunnelDeck.app** to **Applications**.

On first launch, see [Approve first launch](#approve-first-launch).

### Build from source

Requires macOS 26 or later and Xcode 26 or later.

```bash
git clone https://github.com/ff2248/TunnelDeck.git
cd TunnelDeck
scripts/build-app.sh                        # builds build/TunnelDeck.app
cp -R build/TunnelDeck.app /Applications/
```

A locally built app never carries the quarantine flag, so it opens without the approval step.

### Approve first launch

TunnelDeck is signed ad hoc and is not notarized by Apple. When macOS downloads the DMG, through Homebrew or a browser, it marks the app as quarantined and blocks the first launch. Right-clicking the app and choosing **Open** no longer bypasses this, so use one of these:

- **System Settings**: open **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway**, and confirm with your password.
- **Terminal**: `xattr -dr com.apple.quarantine /Applications/TunnelDeck.app`

You need to do this once for each new version.

To start TunnelDeck when you log in, add it under **System Settings → General → Login Items**. Tunnels always start stopped.

### Upgrade

| Method | Command |
|---|---|
| Homebrew | `brew upgrade --cask tunneldeck` |
| DMG | Download the new DMG and replace `/Applications/TunnelDeck.app` |
| Source | `git pull && scripts/build-app.sh && rm -rf /Applications/TunnelDeck.app && cp -R build/TunnelDeck.app /Applications/` |

### Uninstall

| Method | Command |
|---|---|
| Homebrew | `brew uninstall --cask --zap tunneldeck` |
| DMG or source | `rm -rf /Applications/TunnelDeck.app` |

Your tunnels are saved in `~/Library/Application Support/TunnelDeck/tunnels.json` and the language in `~/Library/Preferences/io.github.ff2248.tunneldeck.plist`. `--zap` removes both. Without Homebrew, delete them yourself if you like.

## Security

- **ssh does the work**: every tunnel is a separate `/usr/bin/ssh -N` process started with `BatchMode=yes`, so ssh never waits for a prompt. Keys and passphrases stay with ssh, ssh-agent and the Keychain. TunnelDeck stores no secrets.
- **Host keys are always checked**: TunnelDeck never passes `StrictHostKeyChecking` or `UserKnownHostsFile`, has no option to skip the check, and treats a changed host key as a possible man-in-the-middle attack. Your own `~/.ssh/config` still applies.
- **Loopback only**: forwards always listen on `127.0.0.1`, so other machines on your network can't reach them.
- **No option injection**: host, user and remote host must be valid host names, IP addresses or user names, and the destination is passed after `--`.
- **No other traffic**: apart from the ssh processes, the app makes no network requests. It checks ports through local system calls only.
- **Private settings file**: `tunnels.json` holds names, hosts, ports and key paths only, and is readable by your user only (mode 0600).
- **No dependencies**: the app uses Apple frameworks only.

The app is not sandboxed, because the ssh processes it starts must read `~/.ssh` and reach ssh-agent. It runs with the hardened runtime.

## How it works

The project is a Swift package with two modules. `TunnelCore` holds everything that can be tested without a window: validation, the ssh arguments, the classifier that turns ssh's error output into a failure, the state machine that decides when to reconnect, the settings file, the libproc-based socket inspector, and the session that runs one ssh process per tunnel. `TunnelDeck` is the SwiftUI menu bar extra and the Settings window.

A tunnel counts as connected once its ssh process is listening on every local port, which the session checks once a second through the process's own sockets instead of connecting to the forwarded port. When ssh exits, its output after authentication decides whether to retry. Each ssh starts with `ServerAliveInterval=15` and `ServerAliveCountMax=3`, so a silent dead connection is noticed within about 45 seconds. Quitting the app ends every ssh process it started.

## Contributing

```bash
swift test               # unit tests, using local fake ssh scripts
scripts/build-app.sh     # build the app bundle
```

`LiveTunnelTests` runs a real tunnel when you provide one, and is skipped otherwise:

```bash
TUNNELDECK_LIVE_HOST=bastion.example.com TUNNELDECK_LIVE_USER=deploy \
TUNNELDECK_LIVE_FORWARD=3310:db.internal:3306 swift test --filter LiveTunnelTests
```

`TUNNELDECK_LIVE_PORT` sets a non-default SSH port. Every interface string lives in `Strings` (`Sources/TunnelCore/Localization.swift`), and a language that misses one fails to compile. `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.

## License

[MIT](LICENSE)
