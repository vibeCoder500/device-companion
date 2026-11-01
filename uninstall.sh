#!/usr/bin/env bash
# ============================================================================
# Device Companion Uninstaller (macOS)
#
# One-line uninstall:
#   curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.sh | bash
# ============================================================================
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] This uninstaller requires macOS." >&2
  exit 1
fi
PLIST_PATH="${HOME}/Library/LaunchAgents/com.corpfun.zoomies.plist"
INSTALL_DIR="${HOME}/.corpfun-zoomies"
PID_FILE="${INSTALL_DIR}/zoomies.pid"

echo "[*] Stopping and uninstalling Device Companion..."

if launchctl list com.corpfun.zoomies >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/com.corpfun.zoomies"
fi
if [[ -f "${PLIST_PATH}" ]]; then rm -f "${PLIST_PATH}"; fi

if [[ -f "${PID_FILE}" ]]; then
  old_pid="$(cat "${PID_FILE}")"
  if [[ "${old_pid}" =~ ^[1-9][0-9]*$ ]] && kill -0 "${old_pid}" 2>/dev/null; then
    command_line="$(ps -p "${old_pid}" -o command=)"
    if [[ "${command_line}" == *"${INSTALL_DIR}/run-overlay.jxa.js"* ]]; then
      kill "${old_pid}"
      for _ in {1..30}; do
        if ! kill -0 "${old_pid}" 2>/dev/null; then break; fi
        sleep 0.1
      done
      if kill -0 "${old_pid}" 2>/dev/null; then
        command_line="$(ps -p "${old_pid}" -o command=)"
        if [[ "${command_line}" == *"${INSTALL_DIR}/run-overlay.jxa.js"* ]]; then
          kill -KILL "${old_pid}"
        fi
      fi
    else
      echo "[WARNING] Ignoring a stale PID record for a different process." >&2
    fi
  fi
fi

if [[ -L "${INSTALL_DIR}" ]]; then
  echo "[ERROR] Refusing to delete a linked installation directory." >&2
  exit 1
fi
if [[ -d "${INSTALL_DIR}" ]]; then rm -rf "${HOME}/.corpfun-zoomies"; fi

echo "[OK] Device Companion has been completely uninstalled."
