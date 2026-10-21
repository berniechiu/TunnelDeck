# TunnelDeck

macOS 選單列上的 SSH tunnel 管理工具，只做本機 port forward（`ssh -L`）。連線一律交給系統的 `/usr/bin/ssh`，app 不儲存密碼或金鑰，也不提供關閉 host key 驗證的方法。

## Build

需要 macOS 26 以上與 Xcode 26。

```sh
scripts/build-app.sh
open build/TunnelDeck.app
```

測試：`swift test`

## 第一次連新主機

app 以 `BatchMode=yes` 執行 ssh，不會跳出任何確認。第一次連某台主機前，先在終端機手動 `ssh <host>` 一次，確認主機指紋並加入 `~/.ssh/known_hosts`。有 passphrase 的金鑰要先加入 ssh-agent 或 macOS Keychain。
