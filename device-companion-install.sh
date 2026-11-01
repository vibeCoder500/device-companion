#!/usr/bin/env bash
# ============================================================================
# Device Companion - optional event desktop experience (macOS)
#
# With consent, installs surprise on-screen animations and sound effects.
# Waits 15 minutes, then uses 15-30 second pauses. Removes itself at the
# next local 4:00 pm after the cooldown. Animations do not restart at login.
# This is an event experience, not a device patching or security update tool.
#
# One-line install & start:
#   curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.sh | bash
#
# One-line uninstall:
#   curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.sh | bash
# ============================================================================
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] Device Companion's shell installer requires macOS." >&2
  exit 1
fi

INSTALL_DIR="${HOME}/.corpfun-zoomies"
HEADS_DIR="${INSTALL_DIR}/heads"
PID_FILE="${INSTALL_DIR}/zoomies.pid"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.corpfun.zoomies.plist"
REPO_RAW_BASE="${ZOOMIES_BASE_URL:-https://raw.githubusercontent.com/vibeCoder500/device-companion/main}"
FALLBACK_BASE="https://raw.githubusercontent.com/vibeCoder500/device-companion/main"
CLEANUP_LABEL="com.devicecompanion.cleanup"
CLEANUP_PLIST="${HOME}/Library/LaunchAgents/${CLEANUP_LABEL}.plist"
CLEANUP_SCRIPT="${INSTALL_DIR}/cleanup.sh"

MIN_GAP_SEC="${ZOOMIES_MIN_GAP:-15}"
MAX_GAP_SEC="${ZOOMIES_MAX_GAP:-30}"
MUTE="${ZOOMIES_MUTE:-0}"
COOLDOWN_SEC=900

stop_cleanup() {
  if launchctl print "gui/$(id -u)/${CLEANUP_LABEL}" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/${CLEANUP_LABEL}"
  fi
  if [[ -f "${CLEANUP_PLIST}" ]]; then rm -f "${CLEANUP_PLIST}"; fi
}

choose_timing() {
  completed_ms="$(/usr/bin/osascript -l JavaScript -e 'Date.now()')"
  if [[ ! "${completed_ms}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] Could not determine the installation completion time." >&2
    exit 1
  fi
  STARTS_AT_MS="$(( completed_ms + COOLDOWN_SEC * 1000 ))"
  STARTS_AT="$(( STARTS_AT_MS / 1000 ))"
  EXPIRES_AT="$(date -v16H -v0M -v0S +%s)"
  if (( STARTS_AT_MS >= EXPIRES_AT * 1000 )); then
    EXPIRES_AT="$(date -v+1d -v16H -v0M -v0S +%s)"
  fi
  printf '%s\n' "${STARTS_AT_MS}" > "${INSTALL_DIR}/starts-at"
  printf '%s\n' "${EXPIRES_AT}" > "${INSTALL_DIR}/expires-at"
  printf 'window.HEAD_IMAGES._startsAt = %s;\nwindow.HEAD_IMAGES._expiresAt = %s;\n' \
    "${STARTS_AT_MS}" "$((EXPIRES_AT * 1000))" > "${INSTALL_DIR}/timing.js"
}

stop_companion() {
  if launchctl list com.corpfun.zoomies >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/com.corpfun.zoomies"
  fi
  if [[ -f "${PLIST_PATH}" ]]; then
    rm -f "${PLIST_PATH}"
  fi
  if [[ -f "${PID_FILE}" ]]; then
    local old_pid command_line
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
    rm -f "${PID_FILE}"
  fi
  rm -f "${INSTALL_DIR}/zoomies.ready"
}

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "uninstall" ]]; then
  echo "[*] Stopping and uninstalling Device Companion..."
  stop_cleanup
  stop_companion
  if [[ -L "${INSTALL_DIR}" ]]; then
    echo "[ERROR] Refusing to delete a linked installation directory." >&2
    exit 1
  fi
  if [[ -d "${INSTALL_DIR}" ]]; then rm -rf "${HOME}/.corpfun-zoomies"; fi
  echo "[OK] Device Companion has been completely uninstalled."
  exit 0
fi

if [[ ! "${MIN_GAP_SEC}" =~ ^[0-9]{1,4}$ || ! "${MAX_GAP_SEC}" =~ ^[0-9]{1,4}$ ]]; then
  echo "[ERROR] Animation gaps must be integer seconds between 1 and 3600." >&2
  exit 1
fi
MIN_GAP_SEC="$((10#${MIN_GAP_SEC}))"
MAX_GAP_SEC="$((10#${MAX_GAP_SEC}))"
if (( MIN_GAP_SEC < 1 || MAX_GAP_SEC > 3600 || MAX_GAP_SEC < MIN_GAP_SEC )); then
  echo "[ERROR] Animation gaps must satisfy 1 <= minimum <= maximum <= 3600." >&2
  exit 1
fi
echo "Device Companion - optional event desktop experience"
echo "Waits 15 minutes after installation, then adds surprise animations and sounds with ${MIN_GAP_SEC}-${MAX_GAP_SEC} second pauses."
echo "Automatically removes itself at the next local 4:00 pm after cooldown, or uninstall sooner."
echo "If today is too late, removal moves to tomorrow. A cleanup-only launch agent catches up after wake or sign-in."
echo "Does not apply device patches or restart animations automatically when you sign in."
echo "Sound: ${MUTE} (0 = enabled, 1 or true = muted)."
echo "Installs files only under: ${INSTALL_DIR}"
echo "Uninstall: bash \"${INSTALL_DIR}/uninstall.sh\""
if [[ "${1:-}" != "--accept" ]]; then
  printf "Install and start Device Companion? Type YES to continue: " >/dev/tty
  if ! read -r answer </dev/tty; then
    echo "[ERROR] Interactive consent requires a terminal." >&2
    exit 1
  fi
  if [[ "${answer}" != "YES" ]]; then
    echo "Cancelled. No files or startup settings were changed."
    exit 0
  fi
fi

echo "[*] Installing Device Companion..."
mkdir -p "${HEADS_DIR}"
stop_cleanup
stop_companion

HEAD_FILES=(
  "captain.webp" "captain-back.webp"
  "chef.webp" "chef-back.webp"
  "hero.webp" "hero-back.webp"
  "rockstar.webp" "rockstar-back.webp"
  "viking.webp" "viking-back.webp"
  "wizard.webp" "wizard-back.webp"
)

for f in "${HEAD_FILES[@]}"; do
  dest="${HEADS_DIR}/${f}"
  if [[ -s "${dest}" ]]; then
    continue
  fi
  if [[ -f "src/assets/heads/${f}" ]]; then
    cp "src/assets/heads/${f}" "${dest}"
  else
    curl -fsSL "${REPO_RAW_BASE}/src/assets/heads/${f}" -o "${dest}" \
      || curl -fsSL "${FALLBACK_BASE}/src/assets/heads/${f}" -o "${dest}"
  fi
done

# Build a JS bundle of base64 data URIs for the 12 head images so WKWebView has zero file:// CORS issues
{
  printf "window.HEAD_IMAGES = {\n"
  for f in "${HEAD_FILES[@]}"; do
    key="${f%.webp}"
    b64="$(base64 < "${HEADS_DIR}/${f}" | tr -d '\r\n')"
    printf '  "%s": "data:image/webp;base64,%s",\n' "${key}" "${b64}"
  done
  printf "  \"_minGapMs\": %d,\n" "$((MIN_GAP_SEC * 1000))"
  printf "  \"_maxGapMs\": %d,\n" "$((MAX_GAP_SEC * 1000))"
  printf "  \"_muted\": %s\n" "$([[ "${MUTE}" == "1" || "${MUTE}" == "true" ]] && echo "true" || echo "false")"
  printf "};\n"
} > "${INSTALL_DIR}/heads.js"

cat > "${INSTALL_DIR}/overlay.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Device Companion</title>
<style>
  html, body {
    margin: 0;
    padding: 0;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
    background: transparent !important;
    pointer-events: none;
    user-select: none;
  }
  .zoomie svg { display: block; width: 100%; overflow: visible; }
  .cr-all { transform-origin: 60px 146px; }
  .zoomie { position: fixed; top: 0; left: 0; pointer-events: none; will-change: transform; }
  .zoomie-zoom { transform-origin: 50% 100%; }
  .zoomie-flip { position: relative; }
  .zoomie-flip > svg:last-child { position: absolute; inset: 0; }
  .zoomie-dash::before {
    content: "";
    position: absolute;
    inset: -80% 22%;
    rotate: var(--trail, 0deg);
    background: repeating-linear-gradient(90deg, transparent 0 12%, rgb(255 255 255 / 0.75) 12% 16%, transparent 16% 33%);
    -webkit-mask: linear-gradient(to bottom, transparent 6%, #000 30%, transparent 34%);
    mask: linear-gradient(to bottom, transparent 6%, #000 30%, transparent 34%);
  }
  .zoomie-dash { --stride: 0.2s; }
  .zoomie-zoom { --stride: 0.64s; }
  .zoomie-pop  { --stride: 0.6s; }
  .cr-fast     { --stride: 0.18s; }
  .cr-run .cr-all   { animation: cr-bob calc(var(--stride) / 2) ease-in-out infinite alternate; }
  .cr-run .cr-leg-l { animation: cr-step var(--stride) linear infinite; }
  .cr-run .cr-leg-r { animation: cr-step var(--stride) linear calc(var(--stride) / -2) infinite; }
  .cr-run .cr-arm-l { --pump: 24deg; animation: cr-pump var(--stride) ease-in-out infinite; }
  .cr-run .cr-arm-r { --pump: -24deg; animation: cr-pump var(--stride) ease-in-out infinite; }
  .cr-run .cr-head  { --bob: 6deg; animation: cr-bobble var(--stride) ease-in-out infinite; }
  .cr-run .cr-hat   { --sway: 8deg; animation: cr-sway var(--stride) ease-in-out infinite; }
  .cr-run .cr-cape  { animation: cr-flap calc(var(--stride) / 2) ease-in-out infinite alternate; }
  .cr-run .cr-parrot { animation: cr-peck 0.45s ease-in-out infinite alternate; }
  .cr-whee .cr-arm-l { --up: 110deg; animation: cr-wave calc(var(--stride) / 2) ease-in-out infinite alternate; }
  .cr-whee .cr-arm-r { --up: -110deg; animation: cr-wave calc(var(--stride) / 2) ease-in-out infinite alternate; }

  @keyframes cr-bobble { 0%, 100% { rotate: calc(var(--bob, 5deg) * -1); } 50% { rotate: var(--bob, 5deg); } }
  @keyframes cr-sway   { 0%, 100% { rotate: calc(var(--sway, 4deg) * -1); } 50% { rotate: var(--sway, 4deg); } }
  @keyframes cr-flap   { from { transform: skewX(-7deg); } to { transform: skewX(7deg); } }
  @keyframes cr-bob    { from { translate: 0 0; } to { translate: 0 -5px; } }
  @keyframes cr-step   { 0%, 50%, 100% { translate: 0 0; } 25% { translate: 0 -10px; } }
  @keyframes cr-pump   { 0%, 100% { rotate: var(--pump); } 50% { rotate: calc(var(--pump) * -1); } }
  @keyframes cr-wave   { from { rotate: calc(var(--up) * 0.8); } to { rotate: calc(var(--up) * 1.15); } }
  @keyframes cr-peck   { from { rotate: -8deg; } to { rotate: 6deg; } }
</style>
<script src="./heads.js"></script>
<script src="./timing.js"></script>
</head>
<body>
<div id="stage"></div>
<script>
(() => {
  const PEOPLE = ['rockstar', 'chef', 'wizard', 'captain', 'hero', 'viking'];
  const INK = '#3b2417';
  const K = 58 / 264;
  const EYES = 58;
  const HEAD = { x: 60 - 330 * K, y: EYES - 375 * K, w: 660 * K, h: 780 * K };
  const LOOKS = {
    rockstar: { sleeve: '#1f1f26', hand: '#9a6448', pants: '#2b3a67', shoe: '#f4f4f4' },
    chef:     { sleeve: '#fbfbf8', hand: '#c08a6e', pants: '#e3e3e3', shoe: '#2a2a2a' },
    wizard:   { sleeve: '#6c3fc7', hand: '#b57a5f', pants: '#4b2a8a', shoe: '#4b2a8a' },
    captain:  { sleeve: '#b91c1c', hand: '#c4896d', pants: '#f1e4c8', shoe: '#1d1d25' },
    hero:     { sleeve: '#2a6fdb', hand: '#e63946', pants: '#2a6fdb', shoe: '#e63946' },
    viking:   { sleeve: '#3a7d44', hand: '#8f6450', pants: '#7a6a58', shoe: '#8b5a2b' },
  };

  const TORSO = 'M37 109C37 103 44 101 52 101Q60 108 68 101C76 101 83 103 83 109L81 136Q60 140 39 136Z';
  const TORSO_BACK = 'M37 109C37 103 44 101 52 101Q60 103 68 101C76 101 83 103 83 109L81 136Q60 140 39 136Z';
  const ROBE = 'M37 109C37 103 44 101 52 101Q60 108 68 101C76 101 83 103 83 109L89 141Q60 147 31 141Z';
  const ROBE_BACK = 'M37 109C37 103 44 101 52 101Q60 103 68 101C76 101 83 103 83 109L89 141Q60 147 31 141Z';

  function star(cx, cy, r) {
    let d = '';
    for (let i = 0; i < 10; i++) {
      const a = (Math.PI / 5) * i - Math.PI / 2;
      const rr = i % 2 ? r * 0.45 : r;
      d += `${i ? 'L' : 'M'}${(cx + rr * Math.cos(a)).toFixed(1)} ${(cy + rr * Math.sin(a)).toFixed(1)}`;
    }
    return `${d}Z`;
  }

  function behindSvg(who) {
    if (who === 'hero') return `<path class="cr-cape" style="transform-origin:60px 104px" d="M41 104L27 141Q43 146 60 142Q77 146 93 141L79 104Z" fill="#e63946"/>`;
    if (who === 'viking') return `<path class="cr-cape" style="transform-origin:60px 104px" d="M38 104L31 140Q60 146 89 140L82 104Z" fill="#6b4423"/>`;
    return '';
  }

  function legsSvg(who) {
    const { pants, shoe } = LOOKS[who];
    const leg = (x, foot, cls) => `
      <g class="${cls}">
        <rect x="${x}" y="128" width="11" height="15" rx="3" fill="${pants}"/>
        ${who === 'chef' ? `<g fill="#3a3a3a" stroke="none"><rect x="${x+1.5}" y="131" width="3" height="3"/><rect x="${x+6.5}" y="131" width="3" height="3"/><rect x="${x+4}" y="135.5" width="3" height="3"/></g>` : ''}
        ${who === 'viking' ? `<path d="M${x} 133l11 4M${x} 137l11 -4M${x} 141l11 -4" fill="none" stroke="#c9b48f" stroke-width="1.4"/>` : ''}
        <ellipse cx="${foot}" cy="145" rx="8.5" ry="4.5" fill="${shoe}"/>
      </g>`;
    return leg(44, 48, 'cr-leg-l') + leg(65, 72, 'cr-leg-r');
  }

  function hatSvg(who) {
    switch (who) {
      case 'chef':
        return `<g class="cr-hat" style="transform-origin:60px 20px">
          <path d="M37 13C27 11 25 -5 37 -7C39 -19 53 -21 59 -13C65 -23 81 -19 83 -8C96 -7 94 11 83 13Z" fill="#fff"/>
          <path d="M48 12L46 -1M60 12V-3M72 12L74 -1" fill="none" stroke="#d5d8de" stroke-width="1.6"/>
          <rect x="36" y="11" width="48" height="11" rx="3" fill="#fff"/>
        </g>`;
      case 'wizard':
        return `<g class="cr-hat" style="transform-origin:60px 18px">
          <ellipse cx="61" cy="19" rx="33" ry="5.5" fill="#5a32a8"/>
          <path d="M41 19Q51 -4 62 -30Q66 -37 71 -31Q73 -4 81 19Z" fill="#6c3fc7"/>
          <path d="M42 14Q61 10 80 14L81.5 18.5Q61 14.5 40.5 18.5Z" fill="#ffd23f" stroke-width="1.6"/>
          <path d="${star(59, 2, 3.4)}" fill="#ffd23f" stroke-width="1"/>
          <path d="${star(66, -14, 2.6)}" fill="#ffd23f" stroke-width="1"/>
        </g>`;
      case 'captain':
        return `<g class="cr-hat" style="transform-origin:60px 20px">
          <path d="M10 16Q28 -6 60 -14Q92 -6 110 16Q86 9 60 25Q34 9 10 16Z" fill="#1d1d25"/>
          <path d="M14 15.5Q36 11 60 23Q84 11 106 15.5" fill="none" stroke="#ffd23f" stroke-width="2.2"/>
          <path d="M53 -2L67 8M67 -2L53 8" fill="none" stroke="#fff" stroke-width="2"/>
          <circle cx="60" cy="1" r="4.4" fill="#fff" stroke-width="1.2"/>
          <circle cx="58.3" cy="0.6" r="0.9" fill="${INK}" stroke="none"/>
          <circle cx="61.7" cy="0.6" r="0.9" fill="${INK}" stroke="none"/>
        </g>`;
      case 'viking':
        return `<g class="cr-hat" style="transform-origin:60px 27px">
          <path d="M33 22C22 21 13 12 13 -3C19 7 25 11 35 12Z" fill="#fff4dd"/>
          <path d="M87 22C98 21 107 12 107 -3C101 7 95 11 85 12Z" fill="#fff4dd"/>
          <path d="M30 27C30 1 90 1 90 27Z" fill="#b8c1cc"/>
          <path d="M60 6V24" fill="none" stroke="#8a94a3" stroke-width="3"/>
          <rect x="28" y="23" width="64" height="8" rx="3" fill="#8a94a3"/>
          <g fill="#e6ebf0" stroke="none">${[36, 48, 72, 84].map(x => `<circle cx="${x}" cy="27" r="1.3"/>`).join('')}</g>
        </g>`;
      default:
        return '';
    }
  }

  function torsoSvg(who, back) {
    switch (who) {
      case 'rockstar':
        return back ? `
          <path d="${TORSO_BACK}" fill="#1f1f26"/>
          <path d="${star(60, 119, 9)}" fill="#fff" stroke-width="1.6"/>
          <g fill="#cfd6dd" stroke="none">${[42, 47, 73, 78].map(x => `<circle cx="${x}" cy="${x < 60 ? 105 + (47 - x) * 0.4 : 105 + (x - 73) * 0.4}" r="1.3"/>`).join('')}</g>
        ` : `
          <path d="${TORSO}" fill="#1f1f26"/>
          <path d="M53 102Q60 108 67 102L64 138L56 138Z" fill="#e63946" stroke-width="1.8"/>
          <path d="M61.5 110L57.5 118H61.5L58.5 127" fill="none" stroke="#fff" stroke-width="1.8"/>
          <g fill="#cfd6dd" stroke="none">${[42, 47, 73, 78].map(x => `<circle cx="${x}" cy="${x < 60 ? 105 + (47 - x) * 0.4 : 105 + (x - 73) * 0.4}" r="1.3"/>`).join('')}</g>
        `;
      case 'chef':
        return back ? `
          <path d="${TORSO_BACK}" fill="#fbfbf8"/>
          <path d="M60 128Q51 121 50 128Q51 135 60 128Q69 121 70 128Q69 135 60 128Z" fill="#e63946" stroke-width="1.8"/>
          <path d="M58 129L55 138M62 129L65 138" fill="none" stroke="#e63946" stroke-width="2.4"/>
        ` : `
          <path d="${TORSO}" fill="#fbfbf8"/>
          <path d="M65 108V137" fill="none" stroke="#c9ccd3" stroke-width="1.4"/>
          <g fill="${INK}" stroke="none">${[116, 124, 132].map(y => `<circle cx="55" cy="${y}" r="1.3"/><circle cx="71" cy="${y}" r="1.3"/>`).join('')}</g>
          <path d="M51 102Q60 110 69 102L60 117Z" fill="#e63946" stroke-width="2"/>
          <circle cx="60" cy="106" r="2.6" fill="#c62f3b" stroke-width="1.6"/>
        `;
      case 'wizard':
        return back ? `
          <path d="${ROBE_BACK}" fill="#6c3fc7"/>
          <path d="${star(48, 118, 3.6)}" fill="#ffd23f" stroke-width="1"/>
          <path d="${star(71, 130, 3)}" fill="#ffd23f" stroke-width="1"/>
          <path d="${star(55, 136, 2.4)}" fill="#ffd23f" stroke-width="1"/>
        ` : `
          <path d="${ROBE}" fill="#6c3fc7"/>
          <path d="M60 107V145" fill="none" stroke="#ffd23f" stroke-width="2.2"/>
          <path d="${star(47, 124, 3.6)}" fill="#ffd23f" stroke-width="1"/>
          <path d="${star(74, 134, 3)}" fill="#ffd23f" stroke-width="1"/>
          <path d="M72 112a5 5 0 1 0 5 8a4 4 0 1 1 -5 -8Z" fill="#ffe08a" stroke-width="1.2"/>
        `;
      case 'captain':
        return back ? `
          <path d="M37 109C37 103 44 101 52 101Q60 103 68 101C76 101 83 103 83 109L86 141Q74 144 66 139L60 129L54 139Q46 144 34 141Z" fill="#b91c1c"/>
          <rect x="38" y="123" width="44" height="5" fill="#1d1d25" stroke-width="2"/>
          <path d="M60 128V139" fill="none" stroke-width="1.6"/>
        ` : `
          <path d="M37 109C37 103 44 101 52 101Q60 108 68 101C76 101 83 103 83 109L86 141Q74 144 66 139L60 129L54 139Q46 144 34 141Z" fill="#b91c1c"/>
          <path d="M53 103Q60 108 67 103L65 123L55 123Z" fill="#f5f0e6" stroke-width="1.8"/>
          <g fill="#fff" stroke-width="1.2"><circle cx="57.5" cy="107.5" r="2.4"/><circle cx="62.5" cy="107.5" r="2.4"/><circle cx="60" cy="111.5" r="2.4"/></g>
          <g fill="#ffd23f" stroke-width="1">${[110, 117].map(y => `<circle cx="50.5" cy="${y}" r="1.6"/><circle cx="69.5" cy="${y}" r="1.6"/>`).join('')}</g>
          <rect x="38" y="123" width="44" height="5" fill="#1d1d25" stroke-width="2"/>
          <rect x="56" y="122" width="8" height="7" rx="1.5" fill="#ffd23f" stroke-width="1.5"/>
          <g class="cr-parrot" style="transform-origin:88px 104px">
            <path d="M92 103L99 116L90 106Z" fill="#2563eb" stroke-width="1.4"/>
            <ellipse cx="88" cy="97" rx="6" ry="8" fill="#22c55e" stroke-width="1.6"/>
            <path d="M90 92Q97 99 91 105Q88 99 90 92Z" fill="#ef4444" stroke-width="1.2"/>
            <circle cx="86" cy="87.5" r="5" fill="#22c55e" stroke-width="1.6"/>
            <path d="M82 86.5Q77.5 88.5 81 92L84 89.5Z" fill="#f59e0b" stroke-width="1.2"/>
            <circle cx="86.2" cy="86.6" r="1.2" fill="${INK}" stroke="none"/>
          </g>
        `;
      case 'hero':
        return back ? `
          <path d="${TORSO_BACK}" fill="#2a6fdb"/>
          <path class="cr-cape" style="transform-origin:60px 104px" d="M38 103Q60 99 82 103L91 142Q60 149 29 142Z" fill="#e63946"/>
        ` : `
          <path d="${TORSO}" fill="#2a6fdb"/>
          <rect x="39" y="126" width="42" height="5" fill="#ffd23f" stroke-width="2"/>
          <rect x="56" y="125" width="8" height="7" rx="1.5" fill="#ffb703" stroke-width="1.6"/>
          <path d="M60 107L67.5 114L60 121L52.5 114Z" fill="#ffd23f" stroke-width="2"/>
          <path d="M61.3 109L57.6 114.6H61.4L58.6 119.5" fill="none" stroke="#e63946" stroke-width="1.8"/>
          <circle cx="42" cy="105" r="2.2" fill="#ffd23f" stroke-width="1.4"/>
          <circle cx="78" cy="105" r="2.2" fill="#ffd23f" stroke-width="1.4"/>
        `;
      case 'viking': {
        const fur = 'M33 108Q36 100 44 102Q48 97 53 102Q60 98 67 102Q72 97 76 102Q84 100 87 108Q82 113 76 110Q70 114 64 110Q60 113 56 110Q50 114 44 110Q38 113 33 108Z';
        return back ? `
          <path d="${TORSO_BACK}" fill="#3a7d44"/>
          <path class="cr-cape" style="transform-origin:60px 104px" d="M35 104Q60 99 85 104L89 141Q60 147 31 141Z" fill="#6b4423"/>
          <path d="${fur}" fill="#a0703c"/>
        ` : `
          <path d="${TORSO}" fill="#3a7d44"/>
          <rect x="39" y="125" width="42" height="5.5" fill="#5a3a1e" stroke-width="2"/>
          <rect x="56.5" y="124.5" width="7" height="6.5" rx="1.5" fill="#ffd23f" stroke-width="1.5"/>
          <path d="${fur}" fill="#a0703c"/>
        `;
      }
    }
  }

  function armSvg(who, cls, x1, y1, x2, y2) {
    const w = who === 'wizard' ? 9 : 7.5;
    const { sleeve, hand } = LOOKS[who];
    return `<g class="${cls}" style="transform-origin:${x1}px ${y1}px">
      <g fill="none">
        <path d="M${x1} ${y1}L${x2} ${y2}" stroke-width="${w + 4.5}"/>
        <path d="M${x1} ${y1}L${x2} ${y2}" stroke="${sleeve}" stroke-width="${w}"/>
      </g>
      <circle cx="${x2}" cy="${y2}" r="4" fill="${hand}" stroke-width="2"/>
    </g>`;
  }

  function caricatureSvg(who, back, cls) {
    const src = window.HEAD_IMAGES[back ? `${who}-back` : who] || '';
    return `<svg viewBox="0 0 120 150" class="cr-${who} ${cls || ''}" aria-hidden="true">
      <g class="cr-all" stroke="${INK}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        ${!back ? behindSvg(who) : ''}
        ${legsSvg(who)}
        <g class="cr-head" style="transform-origin:60px 104px">
          <image href="${src}" x="${HEAD.x}" y="${HEAD.y}" width="${HEAD.w}" height="${HEAD.h}"/>
          ${hatSvg(who)}
        </g>
        ${torsoSvg(who, back)}
        ${armSvg(who, 'cr-arm-l', 40, 108, 31, 126)}
        ${armSvg(who, 'cr-arm-r', 80, 108, 89, 126)}
      </g>
    </svg>`;
  }

  // Synthesized sound effects (from src/lib/zoomieSounds.ts)
  let sfx = null;
  function getAudio() {
    if (window.HEAD_IMAGES._muted) return null;
    if (!sfx) {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const out = ctx.createGain();
      out.gain.value = 0.8;
      out.connect(ctx.createDynamicsCompressor()).connect(ctx.destination);
      const noise = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
      const data = noise.getChannelData(0);
      for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
      sfx = { ctx, out, noise };
    }
    if (sfx.ctx.state === 'suspended') sfx.ctx.resume().catch(() => {});
    return sfx;
  }

  function track(a, path) {
    const panner = a.ctx.createStereoPanner();
    panner.pan.setValueAtTime(path[0][1], path[0][0]);
    for (const [at, pan] of path.slice(1)) panner.pan.linearRampToValueAtTime(pan, at);
    panner.connect(a.out);
    return { ctx: a.ctx, dest: panner, noise: a.noise };
  }
  function env(t, at, peak, attack, end, hold = 0) {
    const g = t.ctx.createGain();
    g.gain.setValueAtTime(0.0001, at);
    g.gain.exponentialRampToValueAtTime(peak, at + attack);
    if (hold) g.gain.setValueAtTime(peak, at + attack + hold);
    g.gain.exponentialRampToValueAtTime(0.0001, end);
    g.connect(t.dest);
    return g;
  }
  function glide(t, type, at, points, dest) {
    const osc = t.ctx.createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(points[0][1], at);
    for (const [s, hz] of points.slice(1)) osc.frequency.exponentialRampToValueAtTime(hz, at + s);
    osc.connect(dest);
    osc.start(at);
    osc.stop(at + points[points.length - 1][0] + 0.05);
    return osc;
  }
  function bandpass(t, hz, q) {
    const f = t.ctx.createBiquadFilter();
    f.type = 'bandpass'; f.frequency.value = hz; f.Q.value = q;
    return f;
  }
  function lowpass(t, hz, q = 0.8) {
    const f = t.ctx.createBiquadFilter();
    f.type = 'lowpass'; f.frequency.value = hz; f.Q.value = q;
    return f;
  }
  function stepSfx(t, at, level) { glide(t, 'triangle', at, [[0, 1500], [0.05, 600]], env(t, at, level, 0.004, at + 0.07)); }
  function hopSfx(t, at, level, pitch = 1) { glide(t, 'sine', at, [[0, 240 * pitch], [0.08, 780 * pitch], [0.18, 560 * pitch]], env(t, at, level, 0.01, at + 0.2)); }
  function zipSfx(t, at) {
    const air = t.ctx.createBufferSource();
    air.buffer = t.noise;
    const band = bandpass(t, 600, 1.2);
    band.frequency.setValueAtTime(600, at);
    band.frequency.exponentialRampToValueAtTime(5000, at + 0.13);
    air.connect(band).connect(env(t, at, 1.2, 0.03, at + 0.16, 0.05));
    air.start(at, Math.random() * 0.5);
    air.stop(at + 0.16);
  }
  function wheeSfx(t, at, dur, from, peak, to) {
    const end = at + dur;
    const level = t.ctx.createGain();
    level.gain.setValueAtTime(0.0001, at);
    level.gain.exponentialRampToValueAtTime(0.3, at + 0.06);
    level.gain.setValueAtTime(0.3, at + dur * 0.55);
    level.gain.exponentialRampToValueAtTime(0.0001, end);
    level.connect(t.dest);
    const whistle = glide(t, 'sine', at, [[0, from], [0.2, peak], [dur * 0.6, peak * 0.94], [dur, to]], level);
    const vibrato = t.ctx.createOscillator();
    vibrato.frequency.value = 7;
    const depth = t.ctx.createGain();
    depth.gain.value = peak * 0.03;
    vibrato.connect(depth).connect(whistle.frequency);
    vibrato.start(at); vibrato.stop(end + 0.05);
    const air = t.ctx.createBufferSource();
    air.buffer = t.noise; air.loop = true;
    const band = bandpass(t, peak * 1.6, 1.4);
    band.frequency.setValueAtTime(peak * 1.6, at);
    band.frequency.exponentialRampToValueAtTime(to, end);
    air.connect(band).connect(env(t, at, 0.1, dur * 0.3, end));
    air.start(at); air.stop(end + 0.05);
    return end;
  }
  function voiceSfx(t, who, at) {
    switch (who) {
      case 'rockstar': {
        const wah = bandpass(t, 450, 4);
        wah.frequency.setValueAtTime(450, at);
        wah.frequency.exponentialRampToValueAtTime(2200, at + 0.18);
        wah.frequency.exponentialRampToValueAtTime(600, at + 0.5);
        wah.connect(env(t, at, 0.9, 0.01, at + 0.55, 0.2));
        for (const hz of [147, 220, 294]) glide(t, 'sawtooth', at, [[0, hz], [0.55, hz * 0.98]], wah);
        return at + 0.55;
      }
      case 'chef':
        for (const [hz, level, ring] of [[520, 0.35, 0.6], [1310, 0.25, 0.45], [2210, 0.18, 0.3], [3450, 0.1, 0.2]])
          glide(t, 'sine', at, [[0, hz], [ring, hz * 0.995]], env(t, at, level, 0.003, at + ring));
        return at + 0.6;
      case 'wizard':
        [1047, 1319, 1568, 2093, 2637, 3136].forEach((hz, i) => {
          const s = at + i * 0.055;
          glide(t, 'sine', s, [[0, hz], [0.18, hz * 1.01]], env(t, s, 0.35, 0.005, s + 0.2));
        });
        return at + 0.5;
      case 'hero':
        for (const [d, hz, len] of [[0, 392, 0.12], [0.14, 523, 0.42]]) {
          const brass = lowpass(t, 2600);
          brass.connect(env(t, at + d, 0.18, 0.015, at + d + len, len * 0.6));
          glide(t, 'square', at + d, [[0, hz], [len, hz]], brass);
        }
        return at + 0.56;
      case 'viking': {
        const horn = lowpass(t, 900, 1.2);
        horn.connect(env(t, at, 0.25, 0.06, at + 0.7, 0.35));
        glide(t, 'sawtooth', at, [[0, 98], [0.1, 110], [0.7, 104]], horn);
        glide(t, 'sawtooth', at, [[0, 147], [0.1, 165], [0.7, 156]], horn);
        return at + 0.7;
      }
      case 'captain':
        for (const [d, chord] of [[0, [196, 247, 294]], [0.24, [262, 330, 392]]]) {
          const reed = lowpass(t, 1800, 1);
          reed.connect(env(t, at + d, 0.12, 0.02, at + d + 0.22, 0.1));
          for (const hz of chord) {
            glide(t, 'sawtooth', at + d, [[0, hz], [0.22, hz]], reed);
            glide(t, 'sawtooth', at + d, [[0, hz * 1.006], [0.22, hz * 1.006]], reed);
          }
        }
        return at + 0.5;
    }
  }

  // Zoomies animation engine (from src/components/Zoomies.tsx)
  const DASH_MS = 1400, JOG = 0.45, SWAY_MS = 350;
  const STEPS = 7, STEP_MS = 320, PEEK_MS = 950, TURN_MS = 160, AWAY_MS = 520;
  const TURNED_MS = STEPS * STEP_MS + PEEK_MS + TURN_MS, ZOOM_MS = TURNED_MS + AWAY_MS;
  const FAR = 0.08, NEAR = 1.3;
  const scaleAt = (step) => FAR * (NEAR / FAR) ** (step / STEPS);
  const POP_IN = 750, POP_STAY = 1800, POP_OUT = 380, POP_MS = POP_IN + POP_STAY + POP_OUT;
  const EDGES = ['bottom', 'left', 'top', 'right'];
  const TILT = { bottom: 0, left: 90, top: 180, right: -90 };
  const CHORD = [1, 1.26, 1.5];
  const lerp = (a, b, p) => a + (b - a) * p;
  const panOf = (x) => Math.min(1, Math.max(-1, (x / innerWidth) * 2 - 1));
  const dashInMs = (r) => (2 * r.mid * DASH_MS) / (1 + JOG);
  const dashMs = (r) => dashInMs(r) + (1 - r.mid) * DASH_MS;
  const runMs = (r) => (r.style === 'dash' ? dashMs(r) : r.style === 'zoom' ? ZOOM_MS : POP_MS);

  function dashAt(r, ms) {
    const v = 1 / DASH_MS;
    const inMs = dashInMs(r);
    if (ms <= inMs) return v * ms - ((1 - JOG) * v * ms * ms) / (2 * inMs);
    const outMs = (1 - r.mid) * DASH_MS;
    const u = Math.min(ms - inMs, outMs);
    return r.mid + JOG * v * u + ((1 - JOG) * v * u * u) / outMs;
  }
  function reach(p, dx, dy, margin) {
    const tx = dx > 0 ? (innerWidth + margin - p.x) / dx : dx < 0 ? (p.x + margin) / -dx : Infinity;
    const ty = dy > 0 ? (innerHeight + margin - p.y) / dy : dy < 0 ? (p.y + margin) / -dy : Infinity;
    return Math.min(tx, ty);
  }

  function animateZoom(el, run) {
    const w = el.offsetWidth, h = el.offsetHeight;
    const horizon = innerHeight * 0.45, ground = innerHeight * 0.97;
    const depth = (s) => (s - FAR) / (NEAR - FAR);
    const inward = (s) => lerp(run.far, run.near, depth(s));
    const outward = (s) => lerp(run.away, run.near, depth(s));
    const at = (s, x, lift = 0, tilt = 0) => `translate(${x - w / 2}px, ${lerp(horizon, ground, depth(s)) - h - lift}px) scale(${s}) rotate(${tilt}deg)`;
    const t = (ms) => ms / ZOOM_MS;
    const frames = [];
    for (let i = 0; i < STEPS; i++) {
      const mid = Math.sqrt(scaleAt(i) * scaleAt(i + 1));
      frames.push({ offset: t(i * STEP_MS), transform: at(scaleAt(i), inward(scaleAt(i))), easing: 'ease-out' });
      frames.push({ offset: t((i + 0.5) * STEP_MS), transform: at(mid, inward(mid), h * 0.14 * mid, i % 2 ? 5 : -5), easing: 'ease-in' });
    }
    const arrived = STEPS * STEP_MS;
    frames.push(
      { offset: t(arrived), transform: at(NEAR, run.near) },
      { offset: t(arrived + PEEK_MS * 0.33), transform: at(NEAR, run.near, 0, -6) },
      { offset: t(arrived + PEEK_MS * 0.66), transform: at(NEAR, run.near, 0, 6) },
      { offset: t(TURNED_MS), transform: at(NEAR, run.near), easing: 'ease-in' },
      { offset: t(TURNED_MS + AWAY_MS * 0.45), transform: at(0.4, outward(0.4), h * 0.08), opacity: 1, easing: 'ease-in' },
      { offset: 1, transform: at(0.02, outward(0.02)), opacity: 0 }
    );
    const flip = el.firstElementChild;
    const [front, back] = Array.from(flip.children);
    const mid = t(TURNED_MS - TURN_MS / 2);
    const show = (from, to) => [{ opacity: from }, { opacity: from, offset: mid }, { opacity: to, offset: mid }, { opacity: to }];
    const timing = { duration: ZOOM_MS, delay: run.delay, fill: 'both' };
    return [
      el.animate(frames, timing),
      flip.animate([{ transform: 'scaleX(1)' }, { transform: 'scaleX(1)', offset: t(TURNED_MS - TURN_MS) }, { transform: 'scaleX(0.1)', offset: mid }, { transform: 'scaleX(1)', offset: t(TURNED_MS) }, { transform: 'scaleX(1)' }], timing),
      front.animate(show(1, 0), timing),
      back.animate(show(0, 1), timing),
    ];
  }

  function animateDash(el, run) {
    const w = el.offsetWidth, h = el.offsetHeight;
    const total = dashMs(run);
    const at = (ms) => {
      const p = dashAt(run, ms);
      const sway = 1 - Math.abs(((ms / SWAY_MS) % 2) - 1);
      return {
        offset: ms / total,
        transform: `translate(${lerp(run.from.x, run.to.x, p) - w / 2}px, ${lerp(run.from.y, run.to.y, p) - h / 2}px) rotate(${run.lean - 6 + 12 * sway}deg)`,
      };
    };
    const frames = [];
    for (let ms = 0; ms < total; ms += SWAY_MS / 4) frames.push(at(ms));
    frames.push(at(total));
    return [el.animate(frames, { duration: total, delay: run.delay, fill: 'both' })];
  }

  function animatePop(el, run) {
    const w = el.offsetWidth, h = el.offsetHeight;
    const deg = TILT[run.edge];
    const [ux, uy] = [Math.sin((deg * Math.PI) / 180), -Math.cos((deg * Math.PI) / 180)];
    const edge = run.edge === 'bottom' ? { x: run.along, y: innerHeight } : run.edge === 'top' ? { x: run.along, y: 0 } : run.edge === 'left' ? { x: 0, y: run.along } : { x: innerWidth, y: run.along };
    const at = (r, tilt = 0) => {
      const d = r * h - h / 2;
      return `translate(${edge.x + ux * d - w / 2}px, ${edge.y + uy * d - h / 2}px) rotate(${deg + tilt}deg)`;
    };
    const shown = 0.74, hidden = -0.32;
    const t = (ms) => ms / POP_MS;
    return [
      el.animate([
        { offset: 0, transform: at(hidden), easing: 'cubic-bezier(0.35, 1, 0.4, 1.2)' },
        { offset: t(POP_IN), transform: at(shown), easing: 'ease-in-out' },
        { offset: t(POP_IN + POP_STAY * 0.3), transform: at(shown + 0.03, -9), easing: 'ease-in-out' },
        { offset: t(POP_IN + POP_STAY * 0.65), transform: at(shown - 0.02, 8), easing: 'ease-in-out' },
        { offset: t(POP_IN + POP_STAY), transform: at(shown), easing: 'cubic-bezier(0.36, 0, 0.66, -0.56)' },
        { offset: 1, transform: at(hidden) },
      ], { duration: POP_MS, delay: run.delay, fill: 'both' }),
    ];
  }

  function playGroupSound(a, group) {
    const now = a.ctx.currentTime + 0.03;
    for (const r of group) {
      const t0 = now + r.delay / 1000;
      if (r.style === 'dash') {
        const ms = dashMs(r), dur = ms / 1000;
        const t = track(a, [0, 0.25, 0.5, 0.75, 1].map(f => [t0 + f * dur, panOf(lerp(r.from.x, r.to.x, dashAt(r, f * ms)))]));
        for (let s = 0.05; s < dur; s += 0.1) stepSfx(t, t0 + s, 0.1 + 0.25 * Math.sin((Math.PI * s) / dur));
        voiceSfx(t, r.who, t0 + 0.05);
        wheeSfx(t, t0 + 0.4, dur - 0.3, 560 * r.pitch, 1180 * r.pitch, 620 * r.pitch);
      } else if (r.style === 'pop') {
        const t = track(a, [[t0, r.edge === 'left' ? -0.85 : r.edge === 'right' ? 0.85 : panOf(r.along)]]);
        hopSfx(t, t0, 0.4, 1.15);
        voiceSfx(t, r.who, t0 + POP_IN / 1000);
        const out = t0 + (POP_IN + POP_STAY) / 1000;
        zipSfx(t, out);
        wheeSfx(t, out, POP_OUT / 1000 + 0.25, 1250, 1450, 520);
      } else {
        const away = t0 + TURNED_MS / 1000;
        const t = track(a, [[t0, panOf(r.far)], [t0 + (STEPS * STEP_MS) / 1000, panOf(r.near)], [away, panOf(r.near)], [away + AWAY_MS / 1000, panOf(r.away)]]);
        for (let i = 0; i < STEPS; i++) hopSfx(t, t0 + (i * STEP_MS) / 1000, 0.06 + 0.4 * (i / (STEPS - 1)) ** 1.5, 1.35 - 0.45 * (i / (STEPS - 1)));
        voiceSfx(t, r.who, t0 + (STEPS * STEP_MS) / 1000 + 0.03);
        zipSfx(t, t0 + (TURNED_MS - TURN_MS) / 1000);
        for (let s = 0; s < AWAY_MS / 1000; s += 0.09) stepSfx(t, away + s, 0.3 * (1 - (s * 1000) / AWAY_MS) + 0.02);
        wheeSfx(t, away, AWAY_MS / 1000 + 0.3, 950 * r.pitch, 1350 * r.pitch, 480 * r.pitch);
      }
    }
  }

  const stage = document.getElementById('stage');
  const minGapMs = window.HEAD_IMAGES._minGapMs || 15000;
  const maxGapMs = window.HEAD_IMAGES._maxGapMs || 30000;
  let lastPerson, lastEdge;
  let heading = Math.random() * 2 * Math.PI;
  let seq = 0;

  function scheduleNext(busyMs = 0) {
    if (Date.now() < window.HEAD_IMAGES._expiresAt) {
      setTimeout(triggerRun, busyMs + minGapMs + Math.random() * (maxGapMs - minGapMs));
    }
  }

  function triggerRun() {
    if (Date.now() >= window.HEAD_IMAGES._expiresAt) return;
    if (Date.now() < window.HEAD_IMAGES._startsAt) {
      setTimeout(triggerRun, window.HEAD_IMAGES._startsAt - Date.now());
      return;
    }
    const roll = Math.random();
    const style = roll < 0.4 ? 'pop' : roll < 0.75 ? 'dash' : 'zoom';
    const count = style === 'pop' ? 1 : Math.random() < 0.55 ? 1 : Math.random() < 0.67 ? 2 : 3;
    const kinds = PEOPLE.filter(s => s !== lastPerson).sort(() => Math.random() - 0.5).slice(0, count);
    lastPerson = kinds[kinds.length - 1];
    const [W, H] = [innerWidth, innerHeight];
    const lanes = kinds.map((_, i) => i - (count - 1) / 2);
    let group;

    if (style === 'pop') {
      const edges = EDGES.filter(e => e !== lastEdge);
      const edge = edges[Math.floor(Math.random() * edges.length)];
      lastEdge = edge;
      const width = Math.min(0.42 * W, 0.24 * H);
      const span = edge === 'top' || edge === 'bottom' ? W : H;
      const pad = width * 0.6;
      const along = pad + Math.random() * Math.max(0, span - 2 * pad);
      group = [{ id: ++seq, who: kinds[0], width, pitch: 1, rank: 0, delay: 0, style: 'pop', edge, along }];
    } else if (style === 'dash') {
      heading += ((60 + Math.random() * 240) * Math.PI) / 180;
      const [dx, dy] = [Math.cos(heading), Math.sin(heading)];
      const width = Math.min(0.36 * W, 0.26 * H);
      const margin = width * 1.4;
      const centre = { x: W * (0.3 + Math.random() * 0.4), y: H * (0.25 + Math.random() * 0.5) };
      group = kinds.map((who, i) => {
        const p = { x: centre.x - dy * lanes[i] * width, y: centre.y + dx * lanes[i] * width };
        const back = reach(p, -dx, -dy, margin);
        const ahead = reach(p, dx, dy, margin);
        return {
          id: ++seq, who, width, pitch: CHORD[i], rank: i, delay: i * 330 + Math.random() * 80, style: 'dash',
          from: { x: p.x - dx * back, y: p.y - dy * back },
          to: { x: p.x + dx * ahead, y: p.y + dy * ahead },
          lean: dx * 14,
          mid: Math.min(0.8, Math.max(0.2, back / (back + ahead))),
        };
      });
    } else {
      const width = Math.min(0.52 * W, 0.4 * H) * [1, 0.8, 0.66][count - 1];
      const spot = (lo, hi) => W * (lo + Math.random() * (hi - lo));
      const [far, near, away] = [spot(0.15, 0.85), spot(0.3, 0.7), spot(0.1, 0.9)];
      group = kinds.map((who, i) => {
        const lane = lanes[i] * 0.26 * W;
        return { id: ++seq, who, width, pitch: CHORD[i], rank: i, delay: i * 280 + Math.random() * 80, style: 'zoom', far: far + lane, near: near + lane, away: away + lane };
      });
    }

    for (const run of group) {
      const el = document.createElement('div');
      const trail = run.style === 'dash' ? (Math.atan2(run.to.y - run.from.y, run.to.x - run.from.x) * 180) / Math.PI - 90 - run.lean : 0;
      el.className = `zoomie zoomie-${run.style}`;
      el.style.width = `${run.width}px`;
      el.style.zIndex = String(92 - run.rank);
      el.style.setProperty('--trail', `${trail}deg`);
      el.innerHTML = run.style === 'zoom'
        ? `<div class="zoomie-flip">${caricatureSvg(run.who, false, 'cr-run')}${caricatureSvg(run.who, true, 'cr-run cr-fast')}</div>`
        : caricatureSvg(run.who, false, 'cr-run cr-whee');
      stage.appendChild(el);
      const anims = run.style === 'dash' ? animateDash(el, run) : run.style === 'zoom' ? animateZoom(el, run) : animatePop(el, run);
      anims[0].onfinish = () => el.remove();
    }

    const a = getAudio();
    if (a) playGroupSound(a, group);
    scheduleNext(Math.max(...group.map(r => r.delay + runMs(r))));
  }

  const images = PEOPLE.flatMap(who => [who, `${who}-back`]);
  Promise.all(images.map(key => {
    const image = new Image();
    image.src = window.HEAD_IMAGES[key];
    return image.decode();
  })).then(() => setTimeout(triggerRun, Math.max(0, window.HEAD_IMAGES._startsAt - Date.now()))).catch(error => {
    console.error('Device Companion could not decode its images:', error);
  });
})();
</script>
</body>
</html>
EOF

cat > "${INSTALL_DIR}/run-overlay.jxa.js" <<'EOF'
ObjC.import('Cocoa');
ObjC.import('WebKit');

const app = $.NSApplication.sharedApplication;
app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
app.finishLaunching;

const installDir = $('~/.corpfun-zoomies').stringByExpandingTildeInPath;
const expiresPath = installDir.stringByAppendingPathComponent($('expires-at'));
const expiresText = $.NSString.stringWithContentsOfFileEncodingError(expiresPath, $.NSUTF8StringEncoding, null);
const expiresAt = Number(ObjC.unwrap(expiresText)) * 1000;
if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
  throw new Error('Device Companion end time is missing or expired.');
}

ObjC.registerSubclass({
  name: 'DeviceCompanionExpiry',
  superclass: 'NSObject',
  methods: {
    'expire:': {
      types: ['void', ['id']],
      implementation: function () { app.terminate(null); }
    }
  }
});
const expiryTarget = $.DeviceCompanionExpiry.alloc.init;
const expiryTimer = $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
  (expiresAt - Date.now()) / 1000, expiryTarget, $('expire:'), null, false
);

const statusItem = $.NSStatusBar.systemStatusBar.statusItemWithLength($.NSVariableStatusItemLength);
statusItem.button.setTitle($('DC'));
const menu = $.NSMenu.alloc.init;
const quit = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent($('Quit Device Companion'), $('terminate:'), $(''));
quit.setTarget(app);
menu.addItem(quit);
statusItem.setMenu(menu);

const screen = $.NSScreen.mainScreen;
const frame = screen.frame;

const win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
  frame,
  0, // NSWindowStyleMaskBorderless
  $.NSBackingStoreBuffered,
  false
);

win.setOpaque(false);
win.setBackgroundColor($.NSColor.clearColor);
win.setIgnoresMouseEvents(true);
win.setHasShadow(false);
win.setLevel(1000); // NSScreenSaverWindowLevel
win.setCollectionBehavior((1 << 0) | (1 << 4) | (1 << 8)); // CanJoinAllSpaces | Stationary | FullScreenAuxiliary

const config = $.WKWebViewConfiguration.alloc.init;
config.mediaTypesRequiringUserActionForPlayback = 0;

const viewFrame = $.NSMakeRect(0, 0, frame.size.width, frame.size.height);
const webview = $.WKWebView.alloc.initWithFrameConfiguration(viewFrame, config);
webview.setValueForKey($.NSNumber.numberWithBool(false), $('drawsBackground'));

const htmlPath = $.NSString.stringWithString('~/.corpfun-zoomies/overlay.html').stringByExpandingTildeInPath;
const htmlUrl = $.NSURL.fileURLWithPath(htmlPath);
const dirUrl = htmlUrl.URLByDeletingLastPathComponent;
webview.loadFileURLAllowingReadAccessToURL(htmlUrl, dirUrl);

win.setContentView(webview);
win.orderFrontRegardless;
const readyPath = installDir.stringByAppendingPathComponent($('zoomies.ready'));
$.NSFileManager.defaultManager.createFileAtPathContentsAttributes(
  readyPath, $('running').dataUsingEncoding($.NSUTF8StringEncoding), null
);

app.run;
EOF

cat > "${INSTALL_DIR}/uninstall.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PLIST_PATH="${HOME}/Library/LaunchAgents/com.corpfun.zoomies.plist"
INSTALL_DIR="${HOME}/.corpfun-zoomies"
PID_FILE="${INSTALL_DIR}/zoomies.pid"
CLEANUP_LABEL="com.devicecompanion.cleanup"
CLEANUP_PLIST="${HOME}/Library/LaunchAgents/${CLEANUP_LABEL}.plist"
SCHEDULED=false

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] This uninstaller requires macOS." >&2
  exit 1
fi
if [[ "${1:-}" == "--scheduled-cleanup" ]]; then
  SCHEDULED=true
  script_dir="$(dirname "${BASH_SOURCE[0]}")"
  if [[ -L "${script_dir}" ]]; then
    echo "[ERROR] Refusing cleanup of a linked installation directory." >&2
    exit 1
  fi
  INSTALL_DIR="$(cd "${script_dir}" && pwd -P)"
  if [[ "${INSTALL_DIR##*/}" != ".corpfun-zoomies" ]]; then
    echo "[ERROR] Scheduled cleanup must run inside its own installation." >&2
    exit 1
  fi
  PID_FILE="${INSTALL_DIR}/zoomies.pid"
  cutoff="$(cat "${INSTALL_DIR}/expires-at")"
  if [[ ! "${cutoff}" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] Invalid automatic uninstall deadline." >&2
    exit 1
  fi
  if (( $(date +%s) < cutoff )); then exit 0; fi
fi
if [[ -f "${INSTALL_DIR}/cleanup-plist-path" ]]; then
  CLEANUP_PLIST="$(cat "${INSTALL_DIR}/cleanup-plist-path")"
  if [[ "${CLEANUP_PLIST##*/}" != "${CLEANUP_LABEL}.plist" || "${CLEANUP_PLIST%/*}" != */Library/LaunchAgents ]]; then
    echo "[ERROR] Refusing to remove an unexpected cleanup registration." >&2
    exit 1
  fi
fi
echo "[*] Stopping and uninstalling Device Companion..."
if [[ "${SCHEDULED}" == false ]] && launchctl print "gui/$(id -u)/${CLEANUP_LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/${CLEANUP_LABEL}"
fi
if [[ -f "${CLEANUP_PLIST}" ]]; then rm -f "${CLEANUP_PLIST}"; fi
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
if [[ "${INSTALL_DIR##*/}" != ".corpfun-zoomies" ]]; then
  echo "[ERROR] Refusing deletion outside the companion installation." >&2
  exit 1
fi
if [[ -d "${INSTALL_DIR}" ]]; then rm -rf "${INSTALL_DIR}"; fi
echo "[OK] Device Companion has been completely uninstalled."
if [[ "${SCHEDULED}" == true ]] && launchctl print "gui/$(id -u)/${CLEANUP_LABEL}" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/${CLEANUP_LABEL}"
fi
EOF
chmod +x "${INSTALL_DIR}/uninstall.sh"

cat > "${CLEANUP_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec /bin/bash "${directory}/uninstall.sh" --scheduled-cleanup
EOF
chmod +x "${CLEANUP_SCRIPT}"
mkdir -p "${HOME}/Library/LaunchAgents"
escaped_script="$(printf '%s' "${CLEANUP_SCRIPT}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
cat > "${CLEANUP_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${CLEANUP_LABEL}</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>${escaped_script}</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>16</integer><key>Minute</key><integer>0</integer></dict>
</dict>
</plist>
EOF
printf '%s\n' "${CLEANUP_PLIST}" > "${INSTALL_DIR}/cleanup-plist-path"
choose_timing
if ! launchctl bootstrap "gui/$(id -u)" "${CLEANUP_PLIST}"; then
  echo "[ERROR] Could not register automatic cleanup; installation will not continue." >&2
  stop_cleanup
  bash "${INSTALL_DIR}/uninstall.sh"
  exit 1
fi
choose_timing
nohup /usr/bin/osascript -l JavaScript "${INSTALL_DIR}/run-overlay.jxa.js" >"${INSTALL_DIR}/worker-error.log" 2>&1 &
worker_pid=$!
printf '%s\n' "${worker_pid}" > "${PID_FILE}"
for _ in {1..100}; do
  if ! kill -0 "${worker_pid}" 2>/dev/null || [[ -f "${INSTALL_DIR}/zoomies.ready" ]]; then break; fi
  sleep 0.1
done
if ! kill -0 "${worker_pid}" 2>/dev/null || [[ ! -f "${INSTALL_DIR}/zoomies.ready" ]]; then
  echo "[ERROR] Device Companion failed to start:" >&2
  cat "${INSTALL_DIR}/worker-error.log" >&2
  stop_companion
  bash "${INSTALL_DIR}/uninstall.sh"
  exit 1
fi

echo "[OK] Device Companion is installed and cooling down on macOS."
echo "   * Quiet interval : ${MIN_GAP_SEC}-${MAX_GAP_SEC} seconds"
echo "   * Scope     : full_screen (click-through overlay across all spaces)"
echo "   * First animation : $(date -r "${STARTS_AT}")"
echo "   * Automatic uninstall : $(date -r "${EXPIRES_AT}")"
echo ""
echo "To uninstall anytime after the event, run:"
echo "   ~/.corpfun-zoomies/uninstall.sh"
echo "   or: curl -fsSL ${REPO_RAW_BASE}/uninstall.sh | bash"
