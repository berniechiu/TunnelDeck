# CLAUDE.md

macOS menu bar app that manages SSH local port forwards by running `/usr/bin/ssh`. User-facing documentation is in README.md.

## Commands

```bash
swift test                  # all tests; fake ssh scripts only, LiveTunnelTests skipped
scripts/build-app.sh        # release build, assembles and ad-hoc signs build/TunnelDeck.app
```

## Releasing

Publish a GitHub Release with a `vX.Y.Z` tag. `.github/workflows/release.yml` then tests, builds with that version, uploads `TunnelDeck-vX.Y.Z.dmg` and its `.sha256`, and pushes the updated cask to `ff2248/homebrew-tunneldeck` (`Casks/tunneldeck.rb`) through the `HOMEBREW_TAP_DEPLOY_KEY` secret. A prerelease gets the DMG but leaves the cask alone. The version in `Resources/Info.plist` is only the default for local builds, and `scripts/build-app.sh` always builds a universal (arm64 and x86_64) binary.

## Modules

| Target | Role |
|---|---|
| `TunnelCore` | Validation, ssh arguments, stderr classifier, reconnect state machine, settings file, libproc socket inspector, `TunnelSession` and `TunnelStore`, UI strings. No SwiftUI. |
| `TunnelDeck` | Menu bar extra, Settings window, notifications, network and wake events |

`TunnelStateMachine.reduce` is pure: every reconnect rule lives there, and `TunnelSession` only performs its effects.

## Hard constraints

- Host key checking is never weakened: no `StrictHostKeyChecking`, no `UserKnownHostsFile`, no free-form ssh option field, and no message that suggests bypassing a host key error.
- Forwards bind `127.0.0.1` only, and the UI exposes the local port alone.
- The app stores no secrets. `tunnels.json` stays mode 0600 and holds names, hosts, ports and key paths only.
- No network access besides the ssh processes, and no third-party dependencies.
- Host, user and remote host are validated so they can never be read as ssh options, and the destination follows `--`.
- Every ssh runs with `BatchMode=yes`, `ControlMaster=no` and `ForkAfterAuthentication=no`, so the app owns the process it monitors and terminates. Quitting must leave no ssh process behind.
- Every user-visible string lives in `Strings` (`Sources/TunnelCore/Localization.swift`). English is the default. To add a language, add an `AppLanguage` case and a full `Strings` value; a missing string fails to compile.

## Tests

- Session and store tests replace ssh with generated bash scripts (`FakeSSH` in `TunnelSessionTests.swift`) that listen with perl or print real OpenSSH error lines.
- Classifier samples must be real OpenSSH output. Fixtures use made-up hosts only.
