# Wake-on-LAN（Tailscale + SSH）

別端末から SSH 経由で Wake-on-LAN を送り、対象 PC を起動するスクリプトです。  
起動に失敗した場合はデスクトップ通知（および任意で ntfy）で知らせます。

## フォルダ構成

```
wol/
  config.example.env   … 設定テンプレート
  config.env           … 実際の設定（git 管理外・自分で作成）
  wake-relay.sh        … 中継ホストで実行（WOL 送信・起動確認）
  wake-pc.sh           … 操作端末で実行（SSH 経由で中継を呼び出し）
  Wake-PC.desktop      … ワンクリック用デスクトップランチャー
  install.sh           … セットアップ用スクリプト
```

## 構成図

```
[操作端末]  ──SSH(Tailscale)──>  [中継ホスト（常時起動）]  ──WOL──>  [スリープ中の PC]
     │                                    │
     └─ 起動失敗時に通知                    └─ ping で起動確認
```

| 役割 | 説明 |
|------|------|
| **操作端末** | `wake-pc.sh` またはデスクトップランチャーを実行する PC |
| **中継ホスト** | 常時起動のマシン（Raspberry Pi、NAS など）。対象 PC と同じ LAN |
| **対象 PC** | 起動したいマシン。BIOS で WOL を有効化し、有線 LAN 推奨 |

## 前提条件

### 対象 PC

1. BIOS/UEFI で **Wake on LAN** を有効化
2. OS の電源設定でネットワークからの起動を許可（例: `ethtool -s eth0 wol g`）
3. **Tailscale** をインストールし、起動後に MagicDNS 名で到達できるようにする
4. MAC アドレスを控える: `ip link show`

### 中継ホスト

1. **Tailscale** に参加（操作端末から SSH できること）
2. `wakeonlan` パッケージをインストール
3. 対象 PC と同じサブネットにいること（WOL は同一 LAN 内のブロードキャストが必要）
4. SSH でパスワード認証を使う場合、`sshd` で許可されていること

```bash
# /etc/ssh/sshd_config（変更後は sshd を再起動）
PasswordAuthentication yes
```

```bash
sudo systemctl restart sshd
```

### 操作端末

1. **Tailscale** に参加
2. パスワード認証を使う場合、`sshpass` をインストール

```bash
sudo dnf install sshpass    # Fedora
sudo apt install sshpass    # Debian/Ubuntu
```

3. ワンクリック起動でパスワードを毎回入力する場合、GUI 入力用に `zenity`（GNOME）または `kdialog`（KDE）があると便利

## セットアップ

### 1. 中継ホストで

```bash
cd wol
./install.sh relay
```

`~/wol/wake-relay.sh` が配置されます。

### 2. 操作端末で

```bash
cd wol
cp config.example.env config.env
# config.env を編集（下記参照）
./install.sh client
```

`config.env` の編集例:

```bash
WOL_RELAY_HOST="raspberrypi"          # 中継ホストの Tailscale 名
SSH_USER="mitac"
SSH_AUTH="password"                   # パスワード認証（デフォルト）

WOL_TARGET_MAC="AA:BB:CC:DD:EE:FF"    # 起動対象 PC の MAC
WOL_TARGET_HOST="desktop-pc"          # 起動確認用 Tailscale 名
```

### 3. SSH 認証の選び方

#### パスワード認証（デフォルト）

`config.env` で `SSH_AUTH="password"` に設定します。

| 方法 | 設定 | 用途 |
|------|------|------|
| **GUI で毎回入力** | `SSH_PASSWORD` を空のまま | セキュリティ重視。zenity のダイアログが表示される |
| **config に保存** | `SSH_PASSWORD="..."` を設定 | 完全ワンクリック。平文保存になるため注意 |

`SSH_PASSWORD` を設定しない場合、デスクトップランチャー実行時にパスワード入力ダイアログが開きます。  
ターミナルから実行した場合は、端末上でパスワード入力を求められます。

#### 鍵認証

鍵認証を使う場合は `config.env` を次のように変更します。

```bash
SSH_AUTH="key"
```

あわせて中継ホストに公開鍵を登録します。

```bash
ssh-copy-id mitac@raspberrypi
```

## config.env の設定項目

| 項目 | 必須 | 説明 |
|------|------|------|
| `WOL_RELAY_HOST` | ○ | 中継ホストの Tailscale 名または IP |
| `SSH_USER` | ○ | 中継ホストの SSH ユーザー |
| `SSH_AUTH` | - | `password`（デフォルト）または `key` |
| `SSH_PASSWORD` | - | パスワード認証時のパスワード。省略時は実行時に入力 |
| `RELAY_SCRIPT_PATH` | - | 中継ホスト上のスクリプトパス（デフォルト: `~/wol/wake-relay.sh`） |
| `WOL_TARGET_MAC` | ○ | 起動対象 PC の MAC アドレス |
| `WOL_TARGET_HOST` | - | 起動確認用 Tailscale 名。省略時は WOL 送信のみ |
| `WOL_BROADCAST` | - | ブロードキャストアドレス（必要な場合のみ） |
| `WAKE_TIMEOUT_SEC` | - | 起動待ちタイムアウト（秒、デフォルト: 120） |
| `PING_INTERVAL_SEC` | - | ping 間隔（秒、デフォルト: 5） |
| `USE_DESKTOP_NOTIFY` | - | デスクトップ通知（1=有効、0=無効） |
| `NTFY_TOPIC` | - | ntfy トピック名（スマホ通知用、任意） |

> **注意**: `config.env` にはパスワードなどの秘密情報を含むため、`.gitignore` で git 管理外にしています。リポジトリにコミットしないでください。

## 使い方

### ワンクリック（デスクトップ）

アプリメニューから **「PCを起動 (Wake-on-LAN)」** を選択。

- `SSH_PASSWORD` 未設定の場合 → パスワード入力ダイアログが表示される
- `SSH_PASSWORD` 設定済みの場合 → そのまま WOL が実行される

### コマンドライン

```bash
./wake-pc.sh
```

### 手動で中継ホストに SSH して実行

```bash
ssh mitac@raspberrypi '~/wol/wake-relay.sh AA:BB:CC:DD:EE:FF -t desktop-pc'
```

## 通知

| 状況 | 動作 |
|------|------|
| 既に起動済み | 「既に起動しています」と通知 |
| 起動成功 | 「起動に成功しました」と通知 |
| タイムアウト | 「起動失敗」と **critical** 通知 |
| SSH 接続失敗 | 「接続エラー」と **critical** 通知 |
| sshpass 未インストール等 | 「設定エラー」と **critical** 通知 |

`NTFY_TOPIC` を設定すると、スマホの ntfy アプリにも同内容を送信できます。

## トラブルシューティング

### WOL パケットは届くが起動しない

- BIOS の WOL 設定を確認
- 有線 LAN 接続を確認（Wi-Fi の WOL は環境依存）
- Windows の場合、ファストスタートを無効化

### 中継ホストに SSH できない

```bash
tailscale status          # 両端末がオンラインか確認
ssh -v mitac@raspberrypi  # 接続の詳細ログを確認
```

- パスワード認証: 中継ホストの `PasswordAuthentication yes` を確認
- 鍵認証: `ssh-copy-id` で鍵が登録されているか確認
- Tailscale の MagicDNS 名が正しいか確認

### パスワードダイアログが出ない

- `sshpass` がインストールされているか確認
- GNOME なら `zenity`、KDE なら `kdialog` をインストール
- または `config.env` に `SSH_PASSWORD` を設定して完全自動化

### 起動したが ping が通らない

- 対象 PC のファイアウォールで ICMP を許可
- `WOL_TARGET_HOST` の Tailscale 名が正しいか確認
- PC の起動に時間がかかる場合は `WAKE_TIMEOUT_SEC` を延長
