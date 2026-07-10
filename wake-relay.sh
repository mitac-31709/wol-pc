#!/usr/bin/env bash
# 中継ホスト（常時起動マシン）で実行する WOL スクリプト
# 別端末から SSH 経由で呼び出されます

set -euo pipefail

usage() {
  cat <<'EOF'
使い方: wake-relay.sh <MACアドレス> [オプション]

オプション:
  -t, --target HOST   起動確認用の Tailscale ホスト名/IP
  -b, --broadcast IP  ブロードキャストアドレス
  --timeout SEC       起動待ちタイムアウト（秒、デフォルト: 120）
  --interval SEC      ping 間隔（秒、デフォルト: 5）
  -h, --help          このヘルプを表示

終了コード:
  0 = 起動成功（ping 応答あり）
  1 = 起動失敗（タイムアウト）
  2 = 引数エラー / wakeonlan 未インストール
EOF
}

MAC=""
TARGET_HOST=""
BROADCAST=""
TIMEOUT_SEC=120
INTERVAL_SEC=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target) TARGET_HOST="${2:-}"; shift 2 ;;
    -b|--broadcast) BROADCAST="${2:-}"; shift 2 ;;
    --timeout) TIMEOUT_SEC="${2:-}"; shift 2 ;;
    --interval) INTERVAL_SEC="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "不明なオプション: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -z "$MAC" ]]; then
        MAC="$1"
      else
        echo "余分な引数: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$MAC" ]]; then
  echo "MAC アドレスを指定してください" >&2
  usage >&2
  exit 2
fi

if ! command -v wakeonlan >/dev/null 2>&1; then
  echo "wakeonlan がインストールされていません" >&2
  echo "  Fedora: sudo dnf install wakeonlan" >&2
  echo "  Debian/Ubuntu: sudo apt install wakeonlan" >&2
  exit 2
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] WOL 送信: MAC=$MAC"
if [[ -n "$BROADCAST" ]]; then
  wakeonlan -i "$BROADCAST" "$MAC"
else
  wakeonlan "$MAC"
fi

if [[ -z "$TARGET_HOST" ]]; then
  echo "起動確認ホスト未指定のため、パケット送信のみで終了します"
  exit 0
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 起動確認: $TARGET_HOST (最大 ${TIMEOUT_SEC}秒)"

elapsed=0
while (( elapsed < TIMEOUT_SEC )); do
  if ping -c 1 -W 2 "$TARGET_HOST" >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 起動成功: $TARGET_HOST が応答しました"
    exit 0
  fi
  sleep "$INTERVAL_SEC"
  elapsed=$((elapsed + INTERVAL_SEC))
  echo "  待機中... ${elapsed}/${TIMEOUT_SEC}秒"
done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 起動失敗: ${TIMEOUT_SEC}秒以内に $TARGET_HOST から応答がありませんでした" >&2
exit 1
