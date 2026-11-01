# Device Companion

An optional event-day desktop experience. With your consent, it displays surprise on-screen animations over other windows, with sound effects enabled by default.

It is **not** a device patching, patch scanning, or security update tool. It does not record your screen or keystrokes. Animations do not start automatically at login, and you can quit or uninstall sooner.

## Timing and automatic removal

- The first animation is delayed for **15 minutes after installation**. After that, there are **15-30 second quiet pauses** between animations.
- The companion **automatically uninstalls at 4:00 pm according to the device's local time zone**, using the first 4:00 pm strictly after the cooldown.
- If installation is after 4:00 pm, or the cooldown would reach/past 4:00 pm, removal moves to **4:00 pm the following day**. For example, installing at 3:55 pm starts effects at 4:10 pm and removes them the following day at 4:00 pm.
- Windows installs a per-user cleanup-only scheduled task; macOS installs a cleanup-only launch agent. These remain active if you quit the animations and remove their own registration after successful cleanup.
- If the device is asleep or powered off at the cutoff, cleanup catches up on wake/sign-in. No network connection is needed for removal.
- Existing installations must run the updated install command once to receive the new timing and automatic cleanup.

## Windows

Run in PowerShell, review the disclosure, and type **YES** to install:

The compact Windows notice is: "device companion which may use desktop visual and sound." The automatic-cleanup information and confirmation prompt are still shown.

```powershell
irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.ps1 | iex
```

Internet access, a working Windows WebP image codec, and permission to register a limited per-user scheduled task are required. No Node.js or Python installation is needed. Follow your organization's script-execution policies.

For no sound, pass **`-silent-mode`** to the installer (not to `iex`):

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.ps1'))) -silent-mode
```

Silent mode mutes only the companion effects. The confirmation prompt, 15-minute cooldown, and automatic cleanup are unchanged. The existing `-Mute` switch and `ZOOMIES_MUTE=1` setting still work.

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

For no sound:

```bash
curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.sh | bash -s -- -silent-mode
```

Quit using the **DC** menu bar item. Uninstall with:

```bash
curl -fsSL https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.sh | bash
```

Offline uninstall:

```bash
bash "$HOME/.corpfun-zoomies/uninstall.sh"
```

### macOS startup troubleshooting

If an earlier installer failed with `-[NSNull count]: unrecognized selector`, rerun the current install command above. The readiness-file creation now passes a real empty `NSDictionary`, rather than JavaScript `null`, and the other native-null/error-reference arguments have been corrected.

Startup errors name the failing phase before the installer rolls back its files and cleanup job. A successful install remains visually quiet during the 15-minute cooldown; the **DC** menu-bar item should be present immediately.

## Files and behavior

- The installers, uninstallers, and 12 image assets are self-contained in this repository. Downloads use GitHub only; no Cloudflare service is involved.
- Installers require interactive confirmation before changes. The explicit `-Accept` / `--accept` switch is for a caller who has already reviewed the notice or for non-interactive testing.
- `ZOOMIES_MIN_GAP` and `ZOOMIES_MAX_GAP` set the quiet interval between animations (1-3600 seconds; default 15-30). `-silent-mode` or `ZOOMIES_MUTE=1` disables sound.
- Windows testing can explicitly override `-InitialDelaySec` and `-ExpiresAtUtc` to accelerate validation; the normal one-line command uses the full 900-second cooldown and local 4:00 pm policy.
- The original local folder names are retained for compatibility and legacy startup registrations are removed. Uninstall only stops the companion worker, not an unrelated process identified by a stale PID.
- `downloads.json` lists SHA-256 checksums for the scripts. You can inspect the source before deciding to run it.
- Text files use LF line endings so checksums match the raw GitHub download bytes on every platform.
