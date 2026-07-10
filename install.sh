#!/usr/bin/env bash
# WOL スクリプトのセットアップ

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-client}"

usage() {
  cat <<EOF
使い方: $0 [client|relay|both]

  client  操作端末にデスクトップランチャーをインストール（デフォルト）
  relay   中継ホストに wake-relay.sh を配置し wakeonlan を確認
  both    両方

例:
  # 中継ホスト（常時起動マシン）で:
  $0 relay

  # 操作端末（ノート PC 等）で:
  $0 client
EOF
}

install_relay() {
  echo "=== 中継ホストのセットアップ ==="

  if ! command -v wakeonlan >/dev/null 2>&1; then
    echo "wakeonlan をインストールしてください:"
    echo "  Fedora:   sudo dnf install wakeonlan"
    echo "  Debian:   sudo apt install wakeonlan"
    exit 1
  fi

  mkdir -p "$HOME/wol"
  cp "$SCRIPT_DIR/wake-relay.sh" "$HOME/wol/wake-relay.sh"
  chmod +x "$HOME/wol/wake-relay.sh"
  echo "配置完了: $HOME/wol/wake-relay.sh"
}

install_client() {
  echo "=== 操作端末のセットアップ ==="

  if [[ "${SSH_AUTH:-password}" == "password" ]] && ! command -v sshpass >/dev/null 2>&1; then
    echo "注意: パスワード認証には sshpass が必要です"
    echo "  Fedora:   sudo dnf install sshpass"
    echo "  Debian:   sudo apt install sshpass"
    echo ""
  fi

  if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
    cp "$SCRIPT_DIR/config.example.env" "$SCRIPT_DIR/config.env"
    echo "config.env を作成しました。編集してから再度実行してください:"
    echo "  ${SCRIPT_DIR}/config.env"
  fi

  chmod +x "$SCRIPT_DIR/wake-pc.sh" "$SCRIPT_DIR/wake-relay.sh"

  local desktop_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$desktop_dir"

  sed "s|__SCRIPT_DIR__|${SCRIPT_DIR}|g" "$SCRIPT_DIR/Wake-PC.desktop" \
    > "$desktop_dir/wake-pc.desktop"
  chmod +x "$desktop_dir/wake-pc.desktop"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$desktop_dir" 2>/dev/null || true
  fi

  echo "デスクトップランチャーをインストールしました:"
  echo "  $desktop_dir/wake-pc.desktop"
  echo ""
  echo "アプリメニューから「PCを起動 (Wake-on-LAN)」を選ぶか、"
  echo "  ${SCRIPT_DIR}/wake-pc.sh"
  echo "でワンクリック起動できます。"
}

case "$MODE" in
  relay) install_relay ;;
  client) install_client ;;
  both) install_relay; install_client ;;
  -h|--help) usage; exit 0 ;;
  *) echo "不明なモード: $MODE" >&2; usage >&2; exit 1 ;;
esac
