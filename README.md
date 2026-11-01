# Device Companion

An optional event-day desktop experience. With your consent, it displays surprise on-screen animations over other windows, with sound effects enabled by default.

It is **not** a device patching, patch scanning, or security update tool. It does not record your screen or keystrokes. It stops at local midnight, does not start automatically at login, and can be quit or uninstalled sooner.

## Windows

Run in PowerShell, review the disclosure, and type **YES** to install:

```powershell
irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.ps1 | iex
```

Internet access and a working Windows WebP image codec are required. No Node.js, Python, or administrator installation is needed. Follow your organization's script-execution policies.

For no sound:

```powershell
$env:ZOOMIES_MUTE = '1'; irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.ps1 | iex
```

Quit using the **Device Companion** system-tray menu. Uninstall with:

```powershell
irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.ps1 | iex
```

Offline uninstall:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CorpFunZoomies\uninstall.ps1"
```

## macOS preview

**Syntax-checked, but not yet verified on an actual Mac. Rehearse before sharing with Mac participants.** Run in Terminal and type **YES** at the prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.sh | bash
```

Quit using the **DC** menu bar item. Uninstall with:

```bash
curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.sh | bash
```

Offline uninstall:

```bash
bash "$HOME/.corpfun-zoomies/uninstall.sh"
```

## Files and behavior

- The installers, uninstallers, and 12 image assets are self-contained in this repository. Downloads use GitHub only; no Cloudflare service is involved.
- Installers require interactive confirmation before changes. The explicit `-Accept` / `--accept` switch is for a caller who has already reviewed the notice or for non-interactive testing.
- `ZOOMIES_MIN_GAP` and `ZOOMIES_MAX_GAP` set the quiet interval between animations (1-3600 seconds; default 5-15). `ZOOMIES_MUTE=1` disables sound.
- The original local folder names are retained for compatibility and legacy startup registrations are removed. Uninstall only stops the companion worker, not an unrelated process identified by a stale PID.
- `downloads.json` lists SHA-256 checksums for the scripts. You can inspect the source before deciding to run it.
- Text files use LF line endings so checksums match the raw GitHub download bytes on every platform.
