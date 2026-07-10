#!/usr/bin/env bash
# 別端末から SSH 経由で WOL を実行し、失敗時に通知するクライアントスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ ! -f "$CONFIG_FILE" ]]; then
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "WOL エラー" "config.env がありません。\nconfig.example.env をコピーして設定してください。"
  fi
  echo "エラー: $CONFIG_FILE が見つかりません" >&2
  echo "  cp ${SCRIPT_DIR}/config.example.env ${CONFIG_FILE}" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

: "${WOL_RELAY_HOST:?config.env に WOL_RELAY_HOST を設定してください}"
: "${SSH_USER:?config.env に SSH_USER を設定してください}"
: "${WOL_TARGET_MAC:?config.env に WOL_TARGET_MAC を設定してください}"
: "${RELAY_SCRIPT_PATH:=~/wol/wake-relay.sh}"
: "${WOL_TARGET_HOST:=}"
: "${WAKE_TIMEOUT_SEC:=120}"
: "${PING_INTERVAL_SEC:=5}"
: "${USE_DESKTOP_NOTIFY:=1}"
: "${NTFY_TOPIC:=}"
: "${SSH_AUTH:=password}"
: "${SSH_PASSWORD:=}"

prompt_ssh_password() {
  if command -v zenity >/dev/null 2>&1; then
    zenity --password --title="SSH パスワード" \
      --text="${SSH_USER}@${WOL_RELAY_HOST} のパスワードを入力"
    return
  fi

  if command -v kdialog >/dev/null 2>&1; then
    kdialog --password "SSH パスワード (${SSH_USER}@${WOL_RELAY_HOST})"
    return
  fi

  if [[ -t 0 ]]; then
    read -r -s -p "SSH パスワード (${SSH_USER}@${WOL_RELAY_HOST}): " password
    echo >&2
    printf '%s' "$password"
    return
  fi

  echo "パスワード入力 UI (zenity / kdialog) が見つかりません" >&2
  return 1
}

run_ssh() {
  local relay_cmd="$1"
  local ssh_opts=(-o "ConnectTimeout=10")
  local ssh_target="${SSH_USER}@${WOL_RELAY_HOST}"
  local password=""

  case "$SSH_AUTH" in
    key)
      ssh_opts+=(-o "BatchMode=yes" -o "PreferredAuthentications=publickey")
      ssh "${ssh_opts[@]}" "$ssh_target" "$relay_cmd"
      ;;
    password)
      ssh_opts+=(-o "PreferredAuthentications=password" -o "PubkeyAuthentication=no")

      if [[ -n "$SSH_PASSWORD" ]]; then
        password="$SSH_PASSWORD"
      else
        password="$(prompt_ssh_password)" || return 255
      fi

      if ! command -v sshpass >/dev/null 2>&1; then
        echo "パスワード認証には sshpass が必要です: sudo dnf install sshpass" >&2
        return 2
      fi

      SSHPASS="$password" sshpass -e ssh "${ssh_opts[@]}" "$ssh_target" "$relay_cmd"
      ;;
    *)
      echo "SSH_AUTH は key または password を指定してください: ${SSH_AUTH}" >&2
      return 2
      ;;
  esac
}

notify_failure() {
  local title="$1"
  local body="$2"

  if [[ "${USE_DESKTOP_NOTIFY}" == "1" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical -i dialog-warning "$title" "$body"
  fi

  if [[ -n "$NTFY_TOPIC" ]]; then
    local topic_url="$NTFY_TOPIC"
    if [[ "$topic_url" != http* ]]; then
      topic_url="https://ntfy.sh/${topic_url}"
    fi
    curl -fsS -d "$body" -H "Title: $title" -H "Priority: urgent" "$topic_url" >/dev/null 2>&1 || true
  fi

  echo "通知: $title - $body" >&2
}

notify_success() {
  local body="$1"

  if [[ "${USE_DESKTOP_NOTIFY}" == "1" ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send -i dialog-information "PC 起動" "$body"
  fi

  if [[ -n "$NTFY_TOPIC" ]]; then
    local topic_url="$NTFY_TOPIC"
    if [[ "$topic_url" != http* ]]; then
      topic_url="https://ntfy.sh/${topic_url}"
    fi
    curl -fsS -d "$body" -H "Title: PC 起動" "$topic_url" >/dev/null 2>&1 || true
  fi

  echo "$body"
}

# まず対象 PC が既に起動しているか確認
if [[ -n "$WOL_TARGET_HOST" ]]; then
  if ping -c 1 -W 2 "$WOL_TARGET_HOST" >/dev/null 2>&1; then
    notify_success "${WOL_TARGET_HOST} は既に起動しています"
    exit 0
  fi
fi

relay_cmd="${RELAY_SCRIPT_PATH} ${WOL_TARGET_MAC}"

if [[ -n "$WOL_TARGET_HOST" ]]; then
  relay_cmd+=" -t ${WOL_TARGET_HOST} --timeout ${WAKE_TIMEOUT_SEC} --interval ${PING_INTERVAL_SEC}"
fi

if [[ -n "${WOL_BROADCAST:-}" ]]; then
  relay_cmd+=" -b ${WOL_BROADCAST}"
fi

echo "中継ホスト ${SSH_USER}@${WOL_RELAY_HOST} 経由で WOL を送信します..."

set +e
ssh_output=$(run_ssh "$relay_cmd" 2>&1)
ssh_exit=$?
set -e

echo "$ssh_output"

if [[ $ssh_exit -eq 0 ]]; then
  notify_success "${WOL_TARGET_HOST:-PC} の起動に成功しました"
  exit 0
fi

case $ssh_exit in
  1)
    notify_failure "PC 起動失敗" "${WOL_TARGET_HOST:-PC} が ${WAKE_TIMEOUT_SEC} 秒以内に応答しませんでした。\n電源ケーブル・BIOS の WOL 設定・LAN 接続を確認してください。"
    ;;
  255)
    notify_failure "WOL 接続エラー" "中継ホスト ${WOL_RELAY_HOST} に SSH 接続できませんでした。\nTailscale の接続と SSH 認証（パスワード/鍵）を確認してください。"
    ;;
  2)
    notify_failure "WOL 設定エラー" "SSH の実行に必要なツールや設定が不足しています。\nsshpass のインストールと config.env を確認してください。"
    ;;
  *)
    notify_failure "WOL エラー" "WOL 実行中にエラーが発生しました（終了コード: ${ssh_exit}）"
    ;;
esac

exit "$ssh_exit"
