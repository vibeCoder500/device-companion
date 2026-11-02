<#
.SYNOPSIS
    Device Companion - desktop experience (Windows)
.DESCRIPTION
    With your consent, installs the device companion to scan for device patching updates.
    scans for 15 minutes, and then provides you with the remediation plan
    Automatically uninstalls at the next local 4:00 pm after the cooldown.
    Does not apply device updates or restart automatically when you sign in.

    One-line install & start:
      irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/device-companion-install.ps1 | iex
#>
param(
    [switch]$Uninstall,
    [switch]$RunWorker,
    [switch]$Once,
    [switch]$Accept,
    [ValidateRange(1, 3600)]
    [int]$MinGapSec = $(if ($env:ZOOMIES_MIN_GAP) { [int]$env:ZOOMIES_MIN_GAP } else { 15 }),
    [ValidateRange(1, 3600)]
    [int]$MaxGapSec = $(if ($env:ZOOMIES_MAX_GAP) { [int]$env:ZOOMIES_MAX_GAP } else { 30 }),
    [ValidateSet('full_screen', 'focused_window')]
    [string]$Scope = $(if ($env:ZOOMIES_SCOPE) { $env:ZOOMIES_SCOPE } else { 'full_screen' }),
    [Alias('silent-mode')]
    [switch]$Mute = $(if ($env:ZOOMIES_MUTE -eq '1' -or $env:ZOOMIES_MUTE -eq 'true') { $true } else { $false }),
    [string]$RepoRawBase = $(if ($env:ZOOMIES_BASE_URL) { $env:ZOOMIES_BASE_URL } else { 'https://raw.githubusercontent.com/vibeCoder500/device-companion/main' }),
    [Nullable[DateTime]]$ExpiresAtUtc,
    [ValidateRange(0, 86400)]
    [int]$InitialDelaySec = 900
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'Device Companion requires Windows and a per-user LOCALAPPDATA directory.'
}
$InstallDir = Join-Path $env:LOCALAPPDATA 'CorpFunZoomies'
$HeadsDir   = Join-Path $InstallDir 'heads'
$PidFile    = Join-Path $InstallDir 'zoomies.pid'
$CsFile     = Join-Path $InstallDir 'ZoomiesOverlay.cs'
$WorkerFile = Join-Path $InstallDir 'run-zoomies.ps1'
$UninstFile = Join-Path $InstallDir 'uninstall.ps1'
$ReadyFile  = Join-Path $InstallDir 'zoomies.ready'
$ErrorFile  = Join-Path $InstallDir 'worker-error.log'
$RegRunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RegRunName = 'CorpFunZoomies'
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $pathBytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($InstallDir).ToLowerInvariant())
    $taskId = ([BitConverter]::ToString($sha.ComputeHash($pathBytes))).Replace('-', '').Substring(0, 16)
} finally {
    $sha.Dispose()
}
$CleanupTaskName = "DeviceCompanionCleanup-$taskId"

function Get-CompanionCleanupAt {
    param([DateTime]$InstalledAtUtc, [int]$CooldownSeconds = 900)
    $local = $InstalledAtUtc.ToUniversalTime().ToLocalTime()
    $first = $InstalledAtUtc.ToUniversalTime().AddSeconds($CooldownSeconds).ToLocalTime()
    $cutoff = $local.Date.AddHours(16)
    while ($cutoff -le $first) { $cutoff = $cutoff.AddDays(1) }
    return $cutoff.ToUniversalTime()
}

function Register-CompanionCleanup {
    param([DateTime]$CleanupAtUtc)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$UninstFile`" -ScheduledCleanup -CleanupAtUtc $($CleanupAtUtc.ToUniversalTime().ToString('o'))"
    $time = New-ScheduledTaskTrigger -Once -At $CleanupAtUtc.ToLocalTime()
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $identity
    $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromMinutes(2))
    Register-ScheduledTask -TaskName $CleanupTaskName -TaskPath '\' -Action $action `
        -Trigger @($time, $logon) -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
}

$HeadFiles = @(
    'captain.webp', 'captain-back.webp',
    'chef.webp', 'chef-back.webp',
    'hero.webp', 'hero-back.webp',
    'rockstar.webp', 'rockstar-back.webp',
    'viking.webp', 'viking-back.webp',
    'wizard.webp', 'wizard-back.webp'
)

function Stop-ExistingZoomies {
    $workerPattern = [regex]::Escape($WorkerFile)
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $workerPattern } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    foreach ($file in @($PidFile, $ReadyFile)) {
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force
        }
    }
}

function Install-CaricatureAssets {
    if (-not (Test-Path $HeadsDir)) {
        New-Item -ItemType Directory -Path $HeadsDir -Force | Out-Null
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($file in $HeadFiles) {
        $dest = Join-Path $HeadsDir $file
        if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 100)) {
            continue
        }
        $localCandidate = $null
        if ($PSScriptRoot) {
            $c1 = Join-Path $PSScriptRoot "src\assets\heads\$file"
            $c2 = Join-Path $PSScriptRoot "..\src\assets\heads\$file"
            if (Test-Path $c1) { $localCandidate = $c1 }
            elseif (Test-Path $c2) { $localCandidate = $c2 }
        }
        if ($localCandidate) {
            Copy-Item -Path $localCandidate -Destination $dest -Force
        } else {
            $url = "$RepoRawBase/src/assets/heads/$file"
            try {
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            } catch {
                Write-Warning "The primary asset download failed: $($_.Exception.Message). Trying the event asset mirror."
                $fallbackUrl = "https://raw.githubusercontent.com/vibeCoder500/device-companion/main/src/assets/heads/$file"
                Invoke-WebRequest -Uri $fallbackUrl -OutFile $dest -UseBasicParsing
            }
        }
    }
}

$ReferencedAssemblies = @(
    'PresentationFramework',
    'PresentationCore',
    'WindowsBase',
    'System.Xaml',
    'System.Drawing',
    'System.Windows.Forms'
)

$CSharpSource = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace CorpFunZoomies
{
    internal static class NativeMethods
    {
        public const int GWL_EXSTYLE = -20;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW  = 0x00000080;
        public const int WS_EX_TOPMOST     = 0x00000008;
        public const int WS_EX_LAYERED     = 0x00080000;
        public const int WS_EX_NOACTIVATE  = 0x08000000;

        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public const uint SWP_NOSIZE     = 0x0001;
        public const uint SWP_NOMOVE     = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern int GetWindowLong(IntPtr hwnd, int index);

        [DllImport("user32.dll")]
        public static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    }

    // Exact port of src/lib/zoomieSounds.ts: procedural stereo Web-Audio synthesizer rendered to a WAV stream in memory.
    public sealed class ZoomieAudio
    {
        private const int SampleRate = 44100;
        private static SoundPlayer _player;
        private static MemoryStream _playingStream;
        private readonly float[] _noise;
        private readonly Random _rng = new Random();

        public ZoomieAudio()
        {
            _noise = new float[SampleRate];
            for (int i = 0; i < SampleRate; i++)
                _noise[i] = (float)(_rng.NextDouble() * 2.0 - 1.0);
        }

        public sealed class PanTrack
        {
            public readonly List<Tuple<double, double>> Path = new List<Tuple<double, double>>();
            public double PanAt(double t)
            {
                if (Path.Count == 0) return 0.0;
                if (t <= Path[0].Item1) return Path[0].Item2;
                for (int i = 1; i < Path.Count; i++)
                {
                    if (t <= Path[i].Item1)
                    {
                        double t0 = Path[i - 1].Item1, p0 = Path[i - 1].Item2;
                        double t1 = Path[i].Item1, p1 = Path[i].Item2;
                        double u = (t1 > t0) ? (t - t0) / (t1 - t0) : 1.0;
                        return p0 + (p1 - p0) * u;
                    }
                }
                return Path[Path.Count - 1].Item2;
            }
        }

        private static double EnvAt(double t, double at, double peak, double attack, double end, double hold = 0.0)
        {
            if (t < at || t >= end) return 0.0;
            double aEnd = at + attack;
            if (t < aEnd)
            {
                double u = Math.Max(0.0, (t - at) / Math.Max(0.0001, attack));
                return 0.0001 * Math.Pow(peak / 0.0001, u);
            }
            double hEnd = aEnd + hold;
            if (t < hEnd) return peak;
            double uDecay = Math.Min(1.0, Math.Max(0.0, (t - hEnd) / Math.Max(0.0001, end - hEnd)));
            return peak * Math.Pow(0.0001 / Math.Max(0.00011, peak), uDecay);
        }

        private static double FreqAt(double relT, double[][] pts)
        {
            if (relT <= pts[0][0]) return pts[0][1];
            for (int i = 1; i < pts.Length; i++)
            {
                if (relT <= pts[i][0])
                {
                    double t0 = pts[i - 1][0], f0 = Math.Max(1.0, pts[i - 1][1]);
                    double t1 = pts[i][0], f1 = Math.Max(1.0, pts[i][1]);
                    double u = (t1 > t0) ? (relT - t0) / (t1 - t0) : 1.0;
                    return f0 * Math.Pow(f1 / f0, u);
                }
            }
            return pts[pts.Length - 1][1];
        }

        private static double WaveSample(string type, double phase)
        {
            double p = phase - Math.Floor(phase);
            switch (type)
            {
                case "triangle":
                    return 1.0 - 4.0 * Math.Abs(Math.Round(p - 0.25) - (p - 0.25));
                case "sawtooth":
                    return 2.0 * p - 1.0;
                case "square":
                    return p < 0.5 ? 1.0 : -1.0;
                default:
                    return Math.Sin(2.0 * Math.PI * p);
            }
        }

        private static void MixStereo(float[] left, float[] right, int idx, double sample, double pan)
        {
            if (idx < 0 || idx >= left.Length) return;
            double p = Math.Max(-1.0, Math.Min(1.0, pan));
            double angle = (p + 1.0) * (Math.PI / 4.0);
            left[idx]  += (float)(sample * Math.Cos(angle));
            right[idx] += (float)(sample * Math.Sin(angle));
        }

        private static void AddGlideEnv(float[] left, float[] right, PanTrack tr, string oscType, double at, double[][] pts, double peak, double attack, double end, double hold = 0.0)
        {
            int i0 = Math.Max(0, (int)(at * SampleRate));
            int i1 = Math.Min(left.Length - 1, (int)(end * SampleRate));
            double phase = 0.0;
            for (int i = i0; i <= i1; i++)
            {
                double t = (double)i / SampleRate;
                double f = FreqAt(t - at, pts);
                phase += f / SampleRate;
                double s = WaveSample(oscType, phase) * EnvAt(t, at, peak, attack, end, hold);
                MixStereo(left, right, i, s, tr.PanAt(t));
            }
        }

        // RBJ Biquad filter (bandpass or lowpass)
        private struct Biquad
        {
            private double _b0, _b1, _b2, _a1, _a2, _x1, _x2, _y1, _y2;
            public void SetCoeffs(bool bandpass, double freq, double q)
            {
                double f = Math.Max(20.0, Math.Min(SampleRate * 0.45, freq));
                double w0 = 2.0 * Math.PI * f / SampleRate;
                double cosw = Math.Cos(w0), sinw = Math.Sin(w0);
                double alpha = sinw / (2.0 * Math.Max(0.1, q));
                double a0 = 1.0 + alpha;
                if (bandpass)
                {
                    _b0 = (alpha) / a0;
                    _b1 = 0.0;
                    _b2 = (-alpha) / a0;
                }
                else
                {
                    _b0 = ((1.0 - cosw) * 0.5) / a0;
                    _b1 = (1.0 - cosw) / a0;
                    _b2 = ((1.0 - cosw) * 0.5) / a0;
                }
                _a1 = (-2.0 * cosw) / a0;
                _a2 = (1.0 - alpha) / a0;
            }
            public double Process(double x)
            {
                double y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
                _x2 = _x1; _x1 = x;
                _y2 = _y1; _y1 = y;
                return y;
            }
        }

        public static void Step(float[] l, float[] r, PanTrack tr, double at, double level)
        {
            AddGlideEnv(l, r, tr, "triangle", at, new double[][] { new[] { 0.0, 1500.0 }, new[] { 0.05, 600.0 } }, level, 0.004, at + 0.07);
        }

        public static void Hop(float[] l, float[] r, PanTrack tr, double at, double level, double pitch = 1.0)
        {
            AddGlideEnv(l, r, tr, "sine", at, new double[][] {
                new[] { 0.0, 240.0 * pitch },
                new[] { 0.08, 780.0 * pitch },
                new[] { 0.18, 560.0 * pitch }
            }, level, 0.01, at + 0.2);
        }

        public void Zip(float[] l, float[] r, PanTrack tr, double at)
        {
            double end = at + 0.16;
            int i0 = Math.Max(0, (int)(at * SampleRate));
            int i1 = Math.Min(l.Length - 1, (int)(end * SampleRate));
            int nOffset = _rng.Next(0, SampleRate / 2);
            Biquad bq = new Biquad();
            for (int i = i0; i <= i1; i++)
            {
                double t = (double)i / SampleRate;
                double u = Math.Min(1.0, Math.Max(0.0, (t - at) / 0.13));
                double f = 600.0 * Math.Pow(5000.0 / 600.0, u);
                bq.SetCoeffs(true, f, 1.2);
                double raw = _noise[(i - i0 + nOffset) % _noise.Length];
                double s = bq.Process(raw) * EnvAt(t, at, 1.2, 0.03, end, 0.05);
                MixStereo(l, r, i, s, tr.PanAt(t));
            }
        }

        public double Whee(float[] l, float[] r, PanTrack tr, double at, double dur, double from, double peak, double to)
        {
            double end = at + dur;
            int i0 = Math.Max(0, (int)(at * SampleRate));
            int i1 = Math.Min(l.Length - 1, (int)(end * SampleRate));
            double[][] pts = new double[][] {
                new[] { 0.0, from },
                new[] { 0.2, peak },
                new[] { dur * 0.6, peak * 0.94 },
                new[] { dur, to }
            };
            double phase = 0.0, vibPhase = 0.0;
            int nOffset = _rng.Next(0, SampleRate / 2);
            Biquad bq = new Biquad();
            for (int i = i0; i <= i1; i++)
            {
                double t = (double)i / SampleRate;
                double rel = t - at;
                vibPhase += 7.0 / SampleRate;
                double baseF = FreqAt(rel, pts);
                double f = baseF + Math.Sin(2.0 * Math.PI * vibPhase) * (peak * 0.03);
                phase += f / SampleRate;

                double wGain;
                if (rel < 0.06) wGain = 0.0001 * Math.Pow(0.3 / 0.0001, rel / 0.06);
                else if (rel < dur * 0.55) wGain = 0.3;
                else wGain = 0.3 * Math.Pow(0.0001 / 0.3, Math.Min(1.0, (rel - dur * 0.55) / Math.Max(0.001, dur * 0.45)));

                double whistle = Math.Sin(2.0 * Math.PI * phase) * wGain;

                double bf = (peak * 1.6) * Math.Pow(Math.Max(20.0, to) / (peak * 1.6), Math.Min(1.0, rel / Math.Max(0.001, dur)));
                bq.SetCoeffs(true, bf, 1.4);
                double air = bq.Process(_noise[(i - i0 + nOffset) % _noise.Length]) * EnvAt(t, at, 0.1, dur * 0.3, end);

                MixStereo(l, r, i, whistle + air, tr.PanAt(t));
            }
            return end;
        }

        public static double Voice(float[] l, float[] r, PanTrack tr, string who, double at)
        {
            switch (who)
            {
                case "rockstar":
                {
                    double end = at + 0.55;
                    int i0 = Math.Max(0, (int)(at * SampleRate));
                    int i1 = Math.Min(l.Length - 1, (int)(end * SampleRate));
                    double p1 = 0, p2 = 0, p3 = 0;
                    Biquad wah = new Biquad();
                    for (int i = i0; i <= i1; i++)
                    {
                        double t = (double)i / SampleRate;
                        double rel = t - at;
                        double wf = rel <= 0.18
                            ? 450.0 * Math.Pow(2200.0 / 450.0, rel / 0.18)
                            : 2200.0 * Math.Pow(600.0 / 2200.0, Math.Min(1.0, (rel - 0.18) / 0.32));
                        wah.SetCoeffs(true, wf, 4.0);
                        double bend = Math.Pow(0.98, rel / 0.55);
                        p1 += (147.0 * bend) / SampleRate;
                        p2 += (220.0 * bend) / SampleRate;
                        p3 += (294.0 * bend) / SampleRate;
                        double raw = (WaveSample("sawtooth", p1) + WaveSample("sawtooth", p2) + WaveSample("sawtooth", p3)) / 3.0;
                        double s = wah.Process(raw) * EnvAt(t, at, 0.9, 0.01, end, 0.2);
                        MixStereo(l, r, i, s, tr.PanAt(t));
                    }
                    return end;
                }
                case "chef":
                {
                    double[][] partials = new double[][] {
                        new[] { 520.0, 0.35, 0.6 },
                        new[] { 1310.0, 0.25, 0.45 },
                        new[] { 2210.0, 0.18, 0.3 },
                        new[] { 3450.0, 0.10, 0.2 }
                    };
                    foreach (var p in partials)
                    {
                        AddGlideEnv(l, r, tr, "sine", at, new double[][] { new[] { 0.0, p[0] }, new[] { p[2], p[0] * 0.995 } }, p[1], 0.003, at + p[2]);
                    }
                    return at + 0.6;
                }
                case "wizard":
                {
                    double[] notes = new double[] { 1047, 1319, 1568, 2093, 2637, 3136 };
                    for (int n = 0; n < notes.Length; n++)
                    {
                        double sAt = at + n * 0.055;
                        AddGlideEnv(l, r, tr, "sine", sAt, new double[][] { new[] { 0.0, notes[n] }, new[] { 0.18, notes[n] * 1.01 } }, 0.35, 0.005, sAt + 0.2);
                    }
                    return at + 0.5;
                }
                case "hero":
                {
                    double[][] notes = new double[][] {
                        new[] { 0.0, 392.0, 0.12 },
                        new[] { 0.14, 523.0, 0.42 }
                    };
                    foreach (var n in notes)
                    {
                        double sAt = at + n[0], hz = n[1], len = n[2];
                        int i0 = Math.Max(0, (int)(sAt * SampleRate));
                        int i1 = Math.Min(l.Length - 1, (int)((sAt + len) * SampleRate));
                        double ph = 0;
                        Biquad lp = new Biquad();
                        lp.SetCoeffs(false, 2600.0, 0.8);
                        for (int i = i0; i <= i1; i++)
                        {
                            double t = (double)i / SampleRate;
                            ph += hz / SampleRate;
                            double s = lp.Process(WaveSample("square", ph)) * EnvAt(t, sAt, 0.18, 0.015, sAt + len, len * 0.6);
                            MixStereo(l, r, i, s, tr.PanAt(t));
                        }
                    }
                    return at + 0.56;
                }
                case "viking":
                {
                    double end = at + 0.7;
                    int i0 = Math.Max(0, (int)(at * SampleRate));
                    int i1 = Math.Min(l.Length - 1, (int)(end * SampleRate));
                    double p1 = 0, p2 = 0;
                    double[][] f1 = new double[][] { new[] { 0.0, 98.0 }, new[] { 0.1, 110.0 }, new[] { 0.7, 104.0 } };
                    double[][] f2 = new double[][] { new[] { 0.0, 147.0 }, new[] { 0.1, 165.0 }, new[] { 0.7, 156.0 } };
                    Biquad lp = new Biquad();
                    lp.SetCoeffs(false, 900.0, 1.2);
                    for (int i = i0; i <= i1; i++)
                    {
                        double t = (double)i / SampleRate;
                        double rel = t - at;
                        p1 += FreqAt(rel, f1) / SampleRate;
                        p2 += FreqAt(rel, f2) / SampleRate;
                        double raw = (WaveSample("sawtooth", p1) + WaveSample("sawtooth", p2)) * 0.5;
                        double s = lp.Process(raw) * EnvAt(t, at, 0.25, 0.06, end, 0.35);
                        MixStereo(l, r, i, s, tr.PanAt(t));
                    }
                    return end;
                }
                default: // captain
                {
                    double[] delays = new double[] { 0.0, 0.24 };
                    double[][] chords = new double[][] {
                        new[] { 196.0, 247.0, 294.0 },
                        new[] { 262.0, 330.0, 392.0 }
                    };
                    for (int c = 0; c < 2; c++)
                    {
                        double sAt = at + delays[c];
                        double end = sAt + 0.22;
                        int i0 = Math.Max(0, (int)(sAt * SampleRate));
                        int i1 = Math.Min(l.Length - 1, (int)(end * SampleRate));
                        double[] phA = new double[3];
                        double[] phB = new double[3];
                        Biquad lp = new Biquad();
                        lp.SetCoeffs(false, 1800.0, 1.0);
                        for (int i = i0; i <= i1; i++)
                        {
                            double t = (double)i / SampleRate;
                            double sum = 0;
                            for (int k = 0; k < 3; k++)
                            {
                                phA[k] += chords[c][k] / SampleRate;
                                phB[k] += (chords[c][k] * 1.006) / SampleRate;
                                sum += WaveSample("sawtooth", phA[k]) + WaveSample("sawtooth", phB[k]);
                            }
                            double s = lp.Process(sum / 6.0) * EnvAt(t, sAt, 0.22, 0.02, end, 0.1);
                            MixStereo(l, r, i, s, tr.PanAt(t));
                        }
                    }
                    return at + 0.5;
                }
            }
        }

        public static void PlayBuffer(float[] left, float[] right)
        {
            Stop();
            int samples = left.Length;
            int dataBytes = samples * 4; // 2 channels * 16-bit
            var ms = new MemoryStream(44 + dataBytes);
            var bw = new BinaryWriter(ms);
            bw.Write(new char[] { 'R', 'I', 'F', 'F' });
            bw.Write(36 + dataBytes);
            bw.Write(new char[] { 'W', 'A', 'V', 'E' });
            bw.Write(new char[] { 'f', 'm', 't', ' ' });
            bw.Write(16);
            bw.Write((short)1); // PCM
            bw.Write((short)2); // Stereo
            bw.Write(SampleRate);
            bw.Write(SampleRate * 4);
            bw.Write((short)4);
            bw.Write((short)16);
            bw.Write(new char[] { 'd', 'a', 't', 'a' });
            bw.Write(dataBytes);

            for (int i = 0; i < samples; i++)
            {
                double lVal = Math.Tanh(left[i] * 0.85);
                double rVal = Math.Tanh(right[i] * 0.85);
                short sl = (short)Math.Max(-32767, Math.Min(32767, (int)(lVal * 30000)));
                short sr = (short)Math.Max(-32767, Math.Min(32767, (int)(rVal * 30000)));
                bw.Write(sl);
                bw.Write(sr);
            }
            ms.Position = 0;
            _playingStream = ms;
            _player = new SoundPlayer(ms);
            _player.Play();
        }

        public static void Stop()
        {
            if (_player != null)
            {
                _player.Stop();
                _player.Dispose();
                _player = null;
            }
            if (_playingStream != null)
            {
                _playingStream.Dispose();
                _playingStream = null;
            }
        }
    }

    // Exact port of src/components/Caricature.tsx
    public sealed class CaricatureVisual
    {
        public static readonly string[] People = new[] { "rockstar", "chef", "wizard", "captain", "hero", "viking" };
        private static readonly Brush InkBrush = BrushFromHex("#3b2417");
        private const double K = 58.0 / 264.0;
        private const double Eyes = 58.0;
        private static readonly double HeadX = 60.0 - 330.0 * K;
        private static readonly double HeadY = Eyes - 375.0 * K;
        private static readonly double HeadW = 660.0 * K;
        private static readonly double HeadH = 780.0 * K;

        private const string TorsoD     = "M37 109C37 103 44 101 52 101Q60 108 68 101C76 101 83 103 83 109L81 136Q60 140 39 136Z";
        private const string TorsoBackD = "M37 109C37 103 44 101 52 101Q60 103 68 101C76 101 83 103 83 109L81 136Q60 140 39 136Z";
        private const string RobeD      = "M37 109C37 103 44 101 52 101Q60 108 68 101C76 101 83 103 83 109L89 141Q60 147 31 141Z";
        private const string RobeBackD  = "M37 109C37 103 44 101 52 101Q60 103 68 101C76 101 83 103 83 109L89 141Q60 147 31 141Z";

        public Viewbox Root { get; private set; }
        public TranslateTransform AllBob { get; private set; }
        public TranslateTransform LegLeftStep { get; private set; }
        public TranslateTransform LegRightStep { get; private set; }
        public RotateTransform HeadBobble { get; private set; }
        public RotateTransform HatSway { get; private set; }
        public SkewTransform CapeFlap { get; private set; }
        public RotateTransform ParrotPeck { get; private set; }
        public RotateTransform ArmLeftRot { get; private set; }
        public RotateTransform ArmRightRot { get; private set; }
        public bool IsFast { get; private set; }
        public bool IsWhee { get; private set; }

        private static Brush BrushFromHex(string hex)
        {
            var b = (SolidColorBrush)new BrushConverter().ConvertFromString(hex);
            b.Freeze();
            return b;
        }

        private static System.Windows.Shapes.Path MakePath(string d, string fillHex, string strokeHex = "#3b2417", double strokeWidth = 2.5)
        {
            var p = new System.Windows.Shapes.Path
            {
                Data = Geometry.Parse(d),
                Fill = fillHex != null ? BrushFromHex(fillHex) : null,
                Stroke = strokeHex != null ? BrushFromHex(strokeHex) : null,
                StrokeThickness = strokeWidth,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                StrokeLineJoin = PenLineJoin.Round
            };
            return p;
        }

        private static Ellipse MakeCircle(double cx, double cy, double rx, double ry, string fillHex, string strokeHex = "#3b2417", double strokeWidth = 2.5)
        {
            var e = new Ellipse
            {
                Width = rx * 2,
                Height = ry * 2,
                Fill = fillHex != null ? BrushFromHex(fillHex) : null,
                Stroke = strokeHex != null ? BrushFromHex(strokeHex) : null,
                StrokeThickness = strokeWidth
            };
            Canvas.SetLeft(e, cx - rx);
            Canvas.SetTop(e, cy - ry);
            return e;
        }

        private static Border MakeRect(double x, double y, double w, double h, double rx, string fillHex, string strokeHex = "#3b2417", double strokeWidth = 2.5)
        {
            var b = new Border
            {
                Width = w,
                Height = h,
                CornerRadius = new CornerRadius(rx),
                Background = fillHex != null ? BrushFromHex(fillHex) : null,
                BorderBrush = strokeHex != null ? BrushFromHex(strokeHex) : null,
                BorderThickness = new Thickness(strokeHex != null ? strokeWidth : 0)
            };
            Canvas.SetLeft(b, x);
            Canvas.SetTop(b, y);
            return b;
        }

        private static string StarPath(double cx, double cy, double r)
        {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < 10; i++)
            {
                double a = (Math.PI / 5.0) * i - Math.PI / 2.0;
                double rr = (i % 2 == 1) ? r * 0.45 : r;
                sb.Append(i == 0 ? "M" : "L");
                sb.Append((cx + rr * Math.Cos(a)).ToString("F1", System.Globalization.CultureInfo.InvariantCulture));
                sb.Append(" ");
                sb.Append((cy + rr * Math.Sin(a)).ToString("F1", System.Globalization.CultureInfo.InvariantCulture));
            }
            sb.Append("Z");
            return sb.ToString();
        }

        private static Canvas MakeArm(string who, double x1, double y1, double x2, double y2, out RotateTransform rot)
        {
            string sleeve = "#1f1f26", hand = "#9a6448";
            switch (who)
            {
                case "chef":    sleeve = "#fbfbf8"; hand = "#c08a6e"; break;
                case "wizard":  sleeve = "#6c3fc7"; hand = "#b57a5f"; break;
                case "captain": sleeve = "#b91c1c"; hand = "#c4896d"; break;
                case "hero":    sleeve = "#2a6fdb"; hand = "#e63946"; break;
                case "viking":  sleeve = "#3a7d44"; hand = "#8f6450"; break;
            }
            double w = who == "wizard" ? 9.0 : 7.5;
            string d = string.Format(System.Globalization.CultureInfo.InvariantCulture, "M{0} {1}L{2} {3}", x1, y1, x2, y2);
            var g = new Canvas();
            g.Children.Add(MakePath(d, null, "#3b2417", w + 4.5));
            g.Children.Add(MakePath(d, null, sleeve, w));
            g.Children.Add(MakeCircle(x2, y2, 4, 4, hand, "#3b2417", 2.0));
            rot = new RotateTransform(0, x1, y1);
            g.RenderTransform = rot;
            return g;
        }

        public CaricatureVisual(string who, bool back, bool whee, bool fast, Dictionary<string, BitmapSource> headImages)
        {
            IsWhee = whee;
            IsFast = fast;

            var stage = new Canvas { Width = 120, Height = 150, ClipToBounds = false };
            var all = new Canvas { Width = 120, Height = 150, ClipToBounds = false };
            AllBob = new TranslateTransform(0, 0);
            all.RenderTransform = AllBob;

            // 1. Behind (front cape/cloak)
            if (!back && (who == "hero" || who == "viking"))
            {
                string capeD = who == "hero"
                    ? "M41 104L27 141Q43 146 60 142Q77 146 93 141L79 104Z"
                    : "M38 104L31 140Q60 146 89 140L82 104Z";
                string capeFill = who == "hero" ? "#e63946" : "#6b4423";
                var cape = MakePath(capeD, capeFill);
                CapeFlap = new SkewTransform(0, 0, 60, 104);
                cape.RenderTransform = CapeFlap;
                all.Children.Add(cape);
            }

            // 2. Legs
            string pants = "#2b3a67", shoe = "#f4f4f4";
            switch (who)
            {
                case "chef":    pants = "#e3e3e3"; shoe = "#2a2a2a"; break;
                case "wizard":  pants = "#4b2a8a"; shoe = "#4b2a8a"; break;
                case "captain": pants = "#f1e4c8"; shoe = "#1d1d25"; break;
                case "hero":    pants = "#2a6fdb"; shoe = "#e63946"; break;
                case "viking":  pants = "#7a6a58"; shoe = "#8b5a2b"; break;
            }
            LegLeftStep = new TranslateTransform(0, 0);
            LegRightStep = new TranslateTransform(0, 0);
            all.Children.Add(BuildLeg(who, 44, 48, pants, shoe, LegLeftStep));
            all.Children.Add(BuildLeg(who, 65, 72, pants, shoe, LegRightStep));

            // 3. Head + Hat (under the torso collar)
            var headGroup = new Canvas { Width = 120, Height = 150, ClipToBounds = false };
            HeadBobble = new RotateTransform(0, 60, 104);
            headGroup.RenderTransform = HeadBobble;

            string imgKey = back ? (who + "-back") : who;
            if (headImages.ContainsKey(imgKey))
            {
                var img = new Image
                {
                    Source = headImages[imgKey],
                    Width = HeadW,
                    Height = HeadH,
                    Stretch = Stretch.Fill
                };
                RenderOptions.SetBitmapScalingMode(img, BitmapScalingMode.HighQuality);
                Canvas.SetLeft(img, HeadX);
                Canvas.SetTop(img, HeadY);
                headGroup.Children.Add(img);
            }

            var hat = BuildHat(who);
            if (hat != null) headGroup.Children.Add(hat);
            all.Children.Add(headGroup);

            // 4. Torso
            all.Children.Add(BuildTorso(who, back));

            // 5. Arms
            RotateTransform armL, armR;
            all.Children.Add(MakeArm(who, 40, 108, 31, 126, out armL));
            all.Children.Add(MakeArm(who, 80, 108, 89, 126, out armR));
            ArmLeftRot = armL;
            ArmRightRot = armR;

            stage.Children.Add(all);
            Root = new Viewbox
            {
                Child = stage,
                Stretch = Stretch.Uniform,
                ClipToBounds = false
            };
        }

        private static Canvas BuildLeg(string who, double x, double foot, string pants, string shoe, TranslateTransform stepTx)
        {
            var g = new Canvas { RenderTransform = stepTx };
            g.Children.Add(MakeRect(x, 128, 11, 15, 3, pants));
            if (who == "chef")
            {
                g.Children.Add(MakeRect(x + 1.5, 131, 3, 3, 0, "#3a3a3a", null, 0));
                g.Children.Add(MakeRect(x + 6.5, 131, 3, 3, 0, "#3a3a3a", null, 0));
                g.Children.Add(MakeRect(x + 4.0, 135.5, 3, 3, 0, "#3a3a3a", null, 0));
            }
            if (who == "viking")
            {
                string d = string.Format(System.Globalization.CultureInfo.InvariantCulture, "M{0} 133l11 4M{0} 137l11 -4M{0} 141l11 -4", x);
                g.Children.Add(MakePath(d, null, "#c9b48f", 1.4));
            }
            g.Children.Add(MakeCircle(foot, 145, 8.5, 4.5, shoe));
            return g;
        }

        private Canvas BuildHat(string who)
        {
            switch (who)
            {
                case "chef":
                {
                    var g = new Canvas();
                    HatSway = new RotateTransform(0, 60, 20);
                    g.RenderTransform = HatSway;
                    g.Children.Add(MakePath("M37 13C27 11 25 -5 37 -7C39 -19 53 -21 59 -13C65 -23 81 -19 83 -8C96 -7 94 11 83 13Z", "#ffffff"));
                    g.Children.Add(MakePath("M48 12L46 -1M60 12V-3M72 12L74 -1", null, "#d5d8de", 1.6));
                    g.Children.Add(MakeRect(36, 11, 48, 11, 3, "#ffffff"));
                    return g;
                }
                case "wizard":
                {
                    var g = new Canvas();
                    HatSway = new RotateTransform(0, 60, 18);
                    g.RenderTransform = HatSway;
                    g.Children.Add(MakeCircle(61, 19, 33, 5.5, "#5a32a8"));
                    g.Children.Add(MakePath("M41 19Q51 -4 62 -30Q66 -37 71 -31Q73 -4 81 19Z", "#6c3fc7"));
                    g.Children.Add(MakePath("M42 14Q61 10 80 14L81.5 18.5Q61 14.5 40.5 18.5Z", "#ffd23f", "#3b2417", 1.6));
                    g.Children.Add(MakePath(StarPath(59, 2, 3.4), "#ffd23f", "#3b2417", 1.0));
                    g.Children.Add(MakePath(StarPath(66, -14, 2.6), "#ffd23f", "#3b2417", 1.0));
                    return g;
                }
                case "captain":
                {
                    var g = new Canvas();
                    HatSway = new RotateTransform(0, 60, 20);
                    g.RenderTransform = HatSway;
                    g.Children.Add(MakePath("M10 16Q28 -6 60 -14Q92 -6 110 16Q86 9 60 25Q34 9 10 16Z", "#1d1d25"));
                    g.Children.Add(MakePath("M14 15.5Q36 11 60 23Q84 11 106 15.5", null, "#ffd23f", 2.2));
                    g.Children.Add(MakePath("M53 -2L67 8M67 -2L53 8", null, "#ffffff", 2.0));
                    g.Children.Add(MakeCircle(60, 1, 4.4, 4.4, "#ffffff", "#3b2417", 1.2));
                    g.Children.Add(MakeCircle(58.3, 0.6, 0.9, 0.9, "#3b2417", null, 0));
                    g.Children.Add(MakeCircle(61.7, 0.6, 0.9, 0.9, "#3b2417", null, 0));
                    return g;
                }
                case "viking":
                {
                    var g = new Canvas();
                    HatSway = new RotateTransform(0, 60, 27);
                    g.RenderTransform = HatSway;
                    g.Children.Add(MakePath("M33 22C22 21 13 12 13 -3C19 7 25 11 35 12Z", "#fff4dd"));
                    g.Children.Add(MakePath("M87 22C98 21 107 12 107 -3C101 7 95 11 85 12Z", "#fff4dd"));
                    g.Children.Add(MakePath("M30 27C30 1 90 1 90 27Z", "#b8c1cc"));
                    g.Children.Add(MakePath("M60 6V24", null, "#8a94a3", 3.0));
                    g.Children.Add(MakeRect(28, 23, 64, 8, 3, "#8a94a3"));
                    foreach (double x in new double[] { 36, 48, 72, 84 })
                        g.Children.Add(MakeCircle(x, 27, 1.3, 1.3, "#e6ebf0", null, 0));
                    return g;
                }
                default:
                    return null;
            }
        }

        private Canvas BuildTorso(string who, bool back)
        {
            var g = new Canvas();
            switch (who)
            {
                case "rockstar":
                    if (back)
                    {
                        g.Children.Add(MakePath(TorsoBackD, "#1f1f26"));
                        g.Children.Add(MakePath(StarPath(60, 119, 9), "#ffffff", "#3b2417", 1.6));
                    }
                    else
                    {
                        g.Children.Add(MakePath(TorsoD, "#1f1f26"));
                        g.Children.Add(MakePath("M53 102Q60 108 67 102L64 138L56 138Z", "#e63946", "#3b2417", 1.8));
                        g.Children.Add(MakePath("M61.5 110L57.5 118H61.5L58.5 127", null, "#ffffff", 1.8));
                    }
                    foreach (double x in new double[] { 42, 47, 73, 78 })
                    {
                        double y = x < 60 ? 105 + (47 - x) * 0.4 : 105 + (x - 73) * 0.4;
                        g.Children.Add(MakeCircle(x, y, 1.3, 1.3, "#cfd6dd", null, 0));
                    }
                    break;

                case "chef":
                    if (back)
                    {
                        g.Children.Add(MakePath(TorsoBackD, "#fbfbf8"));
                        g.Children.Add(MakePath("M60 128Q51 121 50 128Q51 135 60 128Q69 121 70 128Q69 135 60 128Z", "#e63946", "#3b2417", 1.8));
                        g.Children.Add(MakePath("M58 129L55 138M62 129L65 138", null, "#e63946", 2.4));
                    }
                    else
                    {
                        g.Children.Add(MakePath(TorsoD, "#fbfbf8"));
                        g.Children.Add(MakePath("M65 108V137", null, "#c9ccd3", 1.4));
                        foreach (double y in new double[] { 116, 124, 132 })
                        {
                            g.Children.Add(MakeCircle(55, y, 1.3, 1.3, "#3b2417", null, 0));
                            g.Children.Add(MakeCircle(71, y, 1.3, 1.3, "#3b2417", null, 0));
                        }
                        g.Children.Add(MakePath("M51 102Q60 110 69 102L60 117Z", "#e63946", "#3b2417", 2.0));
                        g.Children.Add(MakeCircle(60, 106, 2.6, 2.6, "#c62f3b", "#3b2417", 1.6));
                    }
                    break;

                case "wizard":
                    if (back)
                    {
                        g.Children.Add(MakePath(RobeBackD, "#6c3fc7"));
                        g.Children.Add(MakePath(StarPath(48, 118, 3.6), "#ffd23f", "#3b2417", 1.0));
                        g.Children.Add(MakePath(StarPath(71, 130, 3.0), "#ffd23f", "#3b2417", 1.0));
                        g.Children.Add(MakePath(StarPath(55, 136, 2.4), "#ffd23f", "#3b2417", 1.0));
                    }
                    else
                    {
                        g.Children.Add(MakePath(RobeD, "#6c3fc7"));
                        g.Children.Add(MakePath("M60 107V145", null, "#ffd23f", 2.2));
                        g.Children.Add(MakePath(StarPath(47, 124, 3.6), "#ffd23f", "#3b2417", 1.0));
                        g.Children.Add(MakePath(StarPath(74, 134, 3.0), "#ffd23f", "#3b2417", 1.0));
                        g.Children.Add(MakePath("M72 112a5 5 0 1 0 5 8a4 4 0 1 1 -5 -8Z", "#ffe08a", "#3b2417", 1.2));
                    }
                    break;

                case "captain":
                    if (back)
                    {
                        g.Children.Add(MakePath("M37 109C37 103 44 101 52 101Q60 103 68 101C76 101 83 103 83 109L86 141Q74 144 66 139L60 129L54 139Q46 144 34 141Z", "#b91c1c"));
                        g.Children.Add(MakeRect(38, 123, 44, 5, 0, "#1d1d25", "#3b2417", 2.0));
                        g.Children.Add(MakePath("M60 128V139", null, "#3b2417", 1.6));
                    }
                    else
                    {
                        g.Children.Add(MakePath("M37 109C37 103 44 101 52 101Q60 108 68 101C76 101 83 103 83 109L86 141Q74 144 66 139L60 129L54 139Q46 144 34 141Z", "#b91c1c"));
                        g.Children.Add(MakePath("M53 103Q60 108 67 103L65 123L55 123Z", "#f5f0e6", "#3b2417", 1.8));
                        g.Children.Add(MakeCircle(57.5, 107.5, 2.4, 2.4, "#ffffff", "#3b2417", 1.2));
                        g.Children.Add(MakeCircle(62.5, 107.5, 2.4, 2.4, "#ffffff", "#3b2417", 1.2));
                        g.Children.Add(MakeCircle(60.0, 111.5, 2.4, 2.4, "#ffffff", "#3b2417", 1.2));
                        foreach (double y in new double[] { 110, 117 })
                        {
                            g.Children.Add(MakeCircle(50.5, y, 1.6, 1.6, "#ffd23f", "#3b2417", 1.0));
                            g.Children.Add(MakeCircle(69.5, y, 1.6, 1.6, "#ffd23f", "#3b2417", 1.0));
                        }
                        g.Children.Add(MakeRect(38, 123, 44, 5, 0, "#1d1d25", "#3b2417", 2.0));
                        g.Children.Add(MakeRect(56, 122, 8, 7, 1.5, "#ffd23f", "#3b2417", 1.5));

                        var parrot = new Canvas();
                        ParrotPeck = new RotateTransform(0, 88, 104);
                        parrot.RenderTransform = ParrotPeck;
                        parrot.Children.Add(MakePath("M92 103L99 116L90 106Z", "#2563eb", "#3b2417", 1.4));
                        parrot.Children.Add(MakeCircle(88, 97, 6, 8, "#22c55e", "#3b2417", 1.6));
                        parrot.Children.Add(MakePath("M90 92Q97 99 91 105Q88 99 90 92Z", "#ef4444", "#3b2417", 1.2));
                        parrot.Children.Add(MakeCircle(86, 87.5, 5, 5, "#22c55e", "#3b2417", 1.6));
                        parrot.Children.Add(MakePath("M82 86.5Q77.5 88.5 81 92L84 89.5Z", "#f59e0b", "#3b2417", 1.2));
                        parrot.Children.Add(MakeCircle(86.2, 86.6, 1.2, 1.2, "#3b2417", null, 0));
                        g.Children.Add(parrot);
                    }
                    break;

                case "hero":
                    if (back)
                    {
                        g.Children.Add(MakePath(TorsoBackD, "#2a6fdb"));
                        var cape = MakePath("M38 103Q60 99 82 103L91 142Q60 149 29 142Z", "#e63946");
                        CapeFlap = new SkewTransform(0, 0, 60, 104);
                        cape.RenderTransform = CapeFlap;
                        g.Children.Add(cape);
                    }
                    else
                    {
                        g.Children.Add(MakePath(TorsoD, "#2a6fdb"));
                        g.Children.Add(MakeRect(39, 126, 42, 5, 0, "#ffd23f", "#3b2417", 2.0));
                        g.Children.Add(MakeRect(56, 125, 8, 7, 1.5, "#ffb703", "#3b2417", 1.6));
                        g.Children.Add(MakePath("M60 107L67.5 114L60 121L52.5 114Z", "#ffd23f", "#3b2417", 2.0));
                        g.Children.Add(MakePath("M61.3 109L57.6 114.6H61.4L58.6 119.5", null, "#e63946", 1.8));
                        g.Children.Add(MakeCircle(42, 105, 2.2, 2.2, "#ffd23f", "#3b2417", 1.4));
                        g.Children.Add(MakeCircle(78, 105, 2.2, 2.2, "#ffd23f", "#3b2417", 1.4));
                    }
                    break;

                case "viking":
                {
                    const string fur = "M33 108Q36 100 44 102Q48 97 53 102Q60 98 67 102Q72 97 76 102Q84 100 87 108Q82 113 76 110Q70 114 64 110Q60 113 56 110Q50 114 44 110Q38 113 33 108Z";
                    if (back)
                    {
                        g.Children.Add(MakePath(TorsoBackD, "#3a7d44"));
                        var cape = MakePath("M35 104Q60 99 85 104L89 141Q60 147 31 141Z", "#6b4423");
                        CapeFlap = new SkewTransform(0, 0, 60, 104);
                        cape.RenderTransform = CapeFlap;
                        g.Children.Add(cape);
                        g.Children.Add(MakePath(fur, "#a0703c"));
                    }
                    else
                    {
                        g.Children.Add(MakePath(TorsoD, "#3a7d44"));
                        g.Children.Add(MakeRect(39, 125, 42, 5.5, 0, "#5a3a1e", "#3b2417", 2.0));
                        g.Children.Add(MakeRect(56.5, 124.5, 7, 6.5, 1.5, "#ffd23f", "#3b2417", 1.5));
                        g.Children.Add(MakePath(fur, "#a0703c"));
                    }
                    break;
                }
            }
            return g;
        }

        // Animates the bobblehead's limbs, head, hat, cape, and parrot exactly like index.css
        public void TickParts(double sec, double stride)
        {
            double s = IsFast ? 0.18 : stride;
            double halfS = s * 0.5;

            // cr-bob: alternate 0 -> -5px over stride/2
            double bobPhase = (sec / halfS) % 2.0;
            double bobU = bobPhase <= 1.0 ? bobPhase : 2.0 - bobPhase;
            double bobEase = 0.5 - 0.5 * Math.Cos(Math.PI * bobU);
            AllBob.Y = -5.0 * bobEase;

            // cr-step: 0%->0, 25%->-10px, 50%->0, 100%->0
            LegLeftStep.Y = StepOffset((sec % s) / s);
            LegRightStep.Y = StepOffset(((sec + halfS) % s) / s);

            // cr-head bobble: -6deg <-> +6deg over stride
            double headAngle = -6.0 * Math.Cos(2.0 * Math.PI * (sec / s));
            HeadBobble.Angle = headAngle;

            // cr-hat sway: -8deg <-> +8deg over stride
            if (HatSway != null)
                HatSway.Angle = -8.0 * Math.Cos(2.0 * Math.PI * (sec / s));

            // cr-cape flap: -7deg <-> +7deg over stride/2 alternate
            if (CapeFlap != null)
                CapeFlap.AngleX = -7.0 + 14.0 * bobEase;

            // cr-parrot peck: -8deg <-> +6deg over 0.45s alternate
            if (ParrotPeck != null)
            {
                double pPhase = (sec / 0.45) % 2.0;
                double pU = pPhase <= 1.0 ? pPhase : 2.0 - pPhase;
                double pEase = 0.5 - 0.5 * Math.Cos(Math.PI * pU);
                ParrotPeck.Angle = -8.0 + 14.0 * pEase;
            }

            if (IsWhee)
            {
                // cr-wave: from 0.8 * 110 (88deg) to 1.15 * 110 (126.5deg) over stride/2 alternate
                double wL = 88.0 + (126.5 - 88.0) * bobEase;
                ArmLeftRot.Angle = wL;
                ArmRightRot.Angle = -wL;
            }
            else
            {
                // cr-pump: +24deg <-> -24deg over stride
                double pump = 24.0 * Math.Cos(2.0 * Math.PI * (sec / s));
                ArmLeftRot.Angle = pump;
                ArmRightRot.Angle = -pump;
            }
        }

        private static double StepOffset(double p)
        {
            if (p >= 0.5) return 0.0;
            if (p <= 0.25) return -10.0 * (p / 0.25);
            return -10.0 * (1.0 - (p - 0.25) / 0.25);
        }
    }

    // Exact port of src/components/Zoomies.tsx
    public sealed class ZoomiesOverlayWindow : Window
    {
        private const double DASH_MS  = 1400.0;
        private const double JOG      = 0.45;
        private const double SWAY_MS  = 350.0;
        private const int    STEPS    = 7;
        private const double STEP_MS  = 320.0;
        private const double PEEK_MS  = 950.0;
        private const double TURN_MS  = 160.0;
        private const double AWAY_MS  = 520.0;
        private const double TURNED_MS = STEPS * STEP_MS + PEEK_MS + TURN_MS;
        private const double ZOOM_MS   = TURNED_MS + AWAY_MS;
        private const double FAR_S    = 0.08;
        private const double NEAR_S   = 1.3;
        private const double POP_IN   = 750.0;
        private const double POP_STAY = 1800.0;
        private const double POP_OUT  = 380.0;
        private const double POP_MS   = POP_IN + POP_STAY + POP_OUT;

        private static readonly double[] Chord = new[] { 1.0, 1.26, 1.5 };
        private static readonly string[] Edges = new[] { "bottom", "left", "top", "right" };

        private readonly Canvas _stage = new Canvas { ClipToBounds = true };
        private readonly Dictionary<string, BitmapSource> _heads = new Dictionary<string, BitmapSource>();
        private readonly ZoomieAudio _audio = new ZoomieAudio();
        private readonly Random _rng = new Random();
        private readonly List<ActiveRunner> _runners = new List<ActiveRunner>();
        private readonly DispatcherTimer _scheduleTimer = new DispatcherTimer();
        private readonly DispatcherTimer _expiryTimer = new DispatcherTimer();
        private readonly System.Diagnostics.Stopwatch _clock = System.Diagnostics.Stopwatch.StartNew();

        private readonly int _minGapMs;
        private readonly int _maxGapMs;
        private readonly string _scope;
        private readonly bool _mute;
        private readonly bool _once;
        private readonly DateTime _expiresAtUtc;
        private readonly DateTime _startsAtUtc;
        private readonly string _readyFile;
        private System.Windows.Forms.NotifyIcon _trayIcon;

        private string _lastPerson;
        private string _lastEdge;
        private double _heading;
        private bool _renderingHooked;

        private sealed class ActiveRunner
        {
            public string Style;
            public string Who;
            public double Width;
            public double Height;
            public double DelayMs;
            public double TotalMs;
            public double StartTickMs;
            public double Pitch;

            // Dash
            public Point From;
            public Point To;
            public double Lean;
            public double Mid;

            // Zoom
            public double FarX;
            public double NearX;
            public double AwayX;

            // Pop
            public string Edge;
            public double Along;

            public Canvas Container;
            public ScaleTransform FlipScaleX;
            public TranslateTransform MoveTx;
            public RotateTransform RotateTx;
            public ScaleTransform ZoomScaleTx;
            public CaricatureVisual FrontVis;
            public CaricatureVisual BackVis;
        }

        public ZoomiesOverlayWindow(string headsDir, int minGapSec, int maxGapSec, string scope, bool mute, bool once, DateTime expiresAtUtc, DateTime startsAtUtc)
        {
            _minGapMs = Math.Max(1000, minGapSec * 1000);
            _maxGapMs = Math.Max(_minGapMs, maxGapSec * 1000);
            _scope = scope;
            _mute = mute;
            _once = once;
            _expiresAtUtc = expiresAtUtc.ToUniversalTime();
            _startsAtUtc = startsAtUtc.ToUniversalTime();
            _readyFile = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(headsDir), "zoomies.ready");
            _heading = _rng.NextDouble() * 2.0 * Math.PI;

            Title = "Device Companion";
            WindowStyle = WindowStyle.None;
            AllowsTransparency = true;
            Background = Brushes.Transparent;
            Topmost = true;
            ShowInTaskbar = false;
            ShowActivated = false;
            ResizeMode = ResizeMode.NoResize;
            Content = _stage;

            LoadHeadImages(headsDir);

            Loaded += (s, e) =>
            {
                if (DateTime.UtcNow >= _expiresAtUtc)
                {
                    Close();
                    return;
                }
                PositionOverActiveTarget();
                var menu = new System.Windows.Forms.ContextMenuStrip();
                menu.Items.Add("Quit Device Companion").Click += (sender, args) => Close();
                _trayIcon = new System.Windows.Forms.NotifyIcon
                {
                    Icon = System.Drawing.SystemIcons.Information,
                    Text = "Device Companion",
                    ContextMenuStrip = menu,
                    Visible = true
                };
                _expiryTimer.Interval = TimeSpan.FromSeconds(1);
                _expiryTimer.Tick += (sender, args) =>
                {
                    if (DateTime.UtcNow >= _expiresAtUtc) Close();
                };
                _expiryTimer.Start();
                File.WriteAllText(_readyFile, "running");
                ScheduleNext((int)Math.Max(100.0, Math.Ceiling((_startsAtUtc - DateTime.UtcNow).TotalMilliseconds)));
            };
        }

        protected override void OnClosed(EventArgs e)
        {
            _scheduleTimer.Stop();
            _expiryTimer.Stop();
            if (_renderingHooked) CompositionTarget.Rendering -= OnFrameRender;
            if (_trayIcon != null)
            {
                _trayIcon.ContextMenuStrip.Dispose();
                _trayIcon.Dispose();
            }
            ZoomieAudio.Stop();
            File.Delete(_readyFile);
            base.OnClosed(e);
        }

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);
            IntPtr hwnd = new WindowInteropHelper(this).Handle;
            int exStyle = NativeMethods.GetWindowLong(hwnd, NativeMethods.GWL_EXSTYLE);
            NativeMethods.SetWindowLong(
                hwnd,
                NativeMethods.GWL_EXSTYLE,
                exStyle
                | NativeMethods.WS_EX_TRANSPARENT
                | NativeMethods.WS_EX_LAYERED
                | NativeMethods.WS_EX_TOPMOST
                | NativeMethods.WS_EX_TOOLWINDOW
                | NativeMethods.WS_EX_NOACTIVATE
            );
        }

        private void LoadHeadImages(string headsDir)
        {
            foreach (var p in CaricatureVisual.People)
            {
                foreach (var suffix in new[] { "", "-back" })
                {
                    string key = p + suffix;
                    string path = System.IO.Path.Combine(headsDir, key + ".webp");
                    if (!File.Exists(path))
                    {
                        throw new FileNotFoundException("A required Device Companion image is missing.", path);
                    }
                    var raw = new BitmapImage();
                    raw.BeginInit();
                    raw.CacheOption = BitmapCacheOption.OnLoad;
                    raw.UriSource = new Uri(path, UriKind.Absolute);
                    raw.EndInit();
                    BitmapSource bmp = raw;
                    // Some WIC WebP decoders preserve alpha bytes but incorrectly label them Bgr32.
                    if (raw.Format == PixelFormats.Bgr32)
                    {
                        int w = raw.PixelWidth;
                        int h = raw.PixelHeight;
                        int stride = w * 4;
                        byte[] pixels = new byte[stride * h];
                        raw.CopyPixels(pixels, stride, 0);
                        bmp = BitmapSource.Create(w, h, 96.0, 96.0, PixelFormats.Bgra32, null, pixels, stride);
                    }
                    bmp.Freeze();
                    _heads[key] = bmp;
                }
            }
        }

        private void PositionOverActiveTarget()
        {
            IntPtr fg = NativeMethods.GetForegroundWindow();
            IntPtr myHwnd = new WindowInteropHelper(this).Handle;

            double dpiX = 1.0, dpiY = 1.0;
            var src = PresentationSource.FromVisual(this);
            if (src != null && src.CompositionTarget != null)
            {
                dpiX = src.CompositionTarget.TransformToDevice.M11;
                dpiY = src.CompositionTarget.TransformToDevice.M22;
            }

            System.Drawing.Rectangle pxBounds = System.Windows.Forms.Screen.PrimaryScreen.Bounds;
            if (fg != IntPtr.Zero && fg != myHwnd)
            {
                var screen = System.Windows.Forms.Screen.FromHandle(fg);
                if (screen != null) pxBounds = screen.Bounds;

                if (_scope == "focused_window")
                {
                    NativeMethods.RECT r;
                    if (NativeMethods.GetWindowRect(fg, out r))
                    {
                        int rw = r.Right - r.Left;
                        int rh = r.Bottom - r.Top;
                        if (rw >= 320 && rh >= 240)
                        {
                            pxBounds = new System.Drawing.Rectangle(r.Left, r.Top, rw, rh);
                        }
                    }
                }
            }

            Left   = pxBounds.Left   / dpiX;
            Top    = pxBounds.Top    / dpiY;
            Width  = pxBounds.Width  / dpiX;
            Height = pxBounds.Height / dpiY;

            if (myHwnd != IntPtr.Zero)
            {
                NativeMethods.SetWindowPos(
                    myHwnd,
                    NativeMethods.HWND_TOPMOST,
                    pxBounds.Left,
                    pxBounds.Top,
                    pxBounds.Width,
                    pxBounds.Height,
                    NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW
                );
            }
        }

        private void ScheduleNext(int waitMs)
        {
            _scheduleTimer.Stop();
            _scheduleTimer.Interval = TimeSpan.FromMilliseconds(Math.Max(100, waitMs));
            EventHandler tick = null;
            tick = (s, e) =>
            {
                _scheduleTimer.Stop();
                _scheduleTimer.Tick -= tick;
                TriggerZoomieRun();
            };
            _scheduleTimer.Tick += tick;
            _scheduleTimer.Start();
        }

        private static double Lerp(double a, double b, double p) { return a + (b - a) * p; }
        private static double ScaleAt(double step) { return FAR_S * Math.Pow(NEAR_S / FAR_S, step / STEPS); }
        private static double DashInMs(double mid) { return (2.0 * mid * DASH_MS) / (1.0 + JOG); }
        private static double DashMs(double mid) { return DashInMs(mid) + (1.0 - mid) * DASH_MS; }

        private static double DashAt(double mid, double ms)
        {
            double v = 1.0 / DASH_MS;
            double inMs = DashInMs(mid);
            if (ms <= inMs) return v * ms - ((1.0 - JOG) * v * ms * ms) / (2.0 * inMs);
            double outMs = (1.0 - mid) * DASH_MS;
            double u = Math.Min(ms - inMs, outMs);
            return mid + JOG * v * u + ((1.0 - JOG) * v * u * u) / Math.Max(0.001, outMs);
        }

        private static double Reach(Point p, double dx, double dy, double W, double H, double margin)
        {
            double tx = dx > 0 ? (W + margin - p.X) / dx : dx < 0 ? (p.X + margin) / -dx : double.PositiveInfinity;
            double ty = dy > 0 ? (H + margin - p.Y) / dy : dy < 0 ? (p.Y + margin) / -dy : double.PositiveInfinity;
            return Math.Min(tx, ty);
        }

        private double PanOf(double x, double W)
        {
            return Math.Min(1.0, Math.Max(-1.0, (x / Math.Max(1.0, W)) * 2.0 - 1.0));
        }

        private void TriggerZoomieRun()
        {
            if (DateTime.UtcNow >= _expiresAtUtc)
            {
                Close();
                return;
            }
            if (DateTime.UtcNow < _startsAtUtc)
            {
                ScheduleNext((int)Math.Max(100.0, Math.Ceiling((_startsAtUtc - DateTime.UtcNow).TotalMilliseconds)));
                return;
            }
            PositionOverActiveTarget();
            double W = Math.Max(400, Width);
            double H = Math.Max(300, Height);

            double roll = _rng.NextDouble();
            string style = roll < 0.4 ? "pop" : (roll < 0.75 ? "dash" : "zoom");
            int count = style == "pop" ? 1 : (_rng.NextDouble() < 0.55 ? 1 : (_rng.NextDouble() < 0.67 ? 2 : 3));

            var pool = new List<string>();
            foreach (var p in CaricatureVisual.People)
                if (p != _lastPerson) pool.Add(p);
            for (int i = pool.Count - 1; i > 0; i--)
            {
                int j = _rng.Next(i + 1);
                string tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp;
            }
            var kinds = pool.GetRange(0, count);
            _lastPerson = kinds[kinds.Count - 1];

            double nowTick = _clock.Elapsed.TotalMilliseconds;
            var group = new List<ActiveRunner>();

            if (style == "pop")
            {
                var edgeChoices = new List<string>();
                foreach (var e in Edges) if (e != _lastEdge) edgeChoices.Add(e);
                string edge = edgeChoices[_rng.Next(edgeChoices.Count)];
                _lastEdge = edge;
                double w = Math.Min(0.42 * W, 0.24 * H);
                double span = (edge == "top" || edge == "bottom") ? W : H;
                double pad = w * 0.6;
                double along = pad + _rng.NextDouble() * Math.Max(0, span - 2.0 * pad);

                group.Add(CreateRunner("pop", kinds[0], w, 0, POP_MS, nowTick, 1.0, new Point(), new Point(), 0, 0, 0, 0, 0, edge, along));
            }
            else if (style == "dash")
            {
                _heading += ((60.0 + _rng.NextDouble() * 240.0) * Math.PI) / 180.0;
                double dx = Math.Cos(_heading), dy = Math.Sin(_heading);
                double w = Math.Min(0.36 * W, 0.26 * H);
                double margin = w * 1.4;
                var centre = new Point(W * (0.3 + _rng.NextDouble() * 0.4), H * (0.25 + _rng.NextDouble() * 0.5));

                for (int i = 0; i < kinds.Count; i++)
                {
                    double lane = i - (count - 1) / 2.0;
                    var p = new Point(centre.X - dy * lane * w, centre.Y + dx * lane * w);
                    double back = Reach(p, -dx, -dy, W, H, margin);
                    double ahead = Reach(p, dx, dy, W, H, margin);
                    var from = new Point(p.X - dx * back, p.Y - dy * back);
                    var to = new Point(p.X + dx * ahead, p.Y + dy * ahead);
                    double lean = dx * 14.0;
                    double mid = Math.Min(0.8, Math.Max(0.2, back / Math.Max(1.0, back + ahead)));
                    double delay = i * 330.0 + _rng.NextDouble() * 80.0;
                    group.Add(CreateRunner("dash", kinds[i], w, delay, DashMs(mid), nowTick, Chord[i], from, to, lean, mid, 0, 0, 0, null, 0));
                }
            }
            else
            {
                double[] scaleFactors = new[] { 1.0, 0.8, 0.66 };
                double w = Math.Min(0.52 * W, 0.4 * H) * scaleFactors[count - 1];
                double far = W * (0.15 + _rng.NextDouble() * 0.70);
                double near = W * (0.30 + _rng.NextDouble() * 0.40);
                double away = W * (0.10 + _rng.NextDouble() * 0.80);

                for (int i = 0; i < kinds.Count; i++)
                {
                    double lane = (i - (count - 1) / 2.0) * 0.26 * W;
                    double delay = i * 280.0 + _rng.NextDouble() * 80.0;
                    group.Add(CreateRunner("zoom", kinds[i], w, delay, ZOOM_MS, nowTick, Chord[i], new Point(), new Point(), 0, 0, far + lane, near + lane, away + lane, null, 0));
                }
            }

            foreach (var r in group)
            {
                _stage.Children.Add(r.Container);
                _runners.Add(r);
            }

            if (!_mute)
            {
                try { SynthesizeAndPlayGroupAudio(group, W); }
                catch (Exception error) { Console.Error.WriteLine("Device Companion sound error: " + error.Message); }
            }
            foreach (var runner in group) runner.StartTickMs = _clock.Elapsed.TotalMilliseconds;

            if (!_renderingHooked)
            {
                _renderingHooked = true;
                CompositionTarget.Rendering += OnFrameRender;
            }
        }

        private ActiveRunner CreateRunner(
            string style, string who, double width, double delayMs, double totalMs, double nowTick, double pitch,
            Point from, Point to, double lean, double mid, double farX, double nearX, double awayX, string edge, double along)
        {
            double height = width * (150.0 / 120.0);
            var container = new Canvas
            {
                Width = width,
                Height = height,
                ClipToBounds = false,
                Opacity = 0.0
            };

            bool isWhee = style != "zoom";
            var front = new CaricatureVisual(who, false, isWhee, false, _heads);
            front.Root.Width = width;
            front.Root.Height = height;

            CaricatureVisual back = null;
            ScaleTransform flipScaleX = null;

            if (style == "dash")
            {
                // Speed lines trailing behind the head
                double trailDeg = (Math.Atan2(to.Y - from.Y, to.X - from.X) * 180.0) / Math.PI - 90.0 - lean;
                var speedLines = new Canvas
                {
                    Width = width,
                    Height = height,
                    RenderTransform = new RotateTransform(trailDeg, width * 0.5, height * 0.5)
                };
                for (int s = 0; s < 3; s++)
                {
                    double lx = width * (0.28 + s * 0.20);
                    var line = new System.Windows.Shapes.Rectangle
                    {
                        Width = Math.Max(2.0, width * 0.03),
                        Height = height * 0.42,
                        Fill = new SolidColorBrush(Color.FromArgb(180, 255, 255, 255)),
                        RadiusX = 2,
                        RadiusY = 2
                    };
                    Canvas.SetLeft(line, lx);
                    Canvas.SetTop(line, -height * 0.36);
                    speedLines.Children.Add(line);
                }
                container.Children.Add(speedLines);
            }

            if (style == "zoom")
            {
                back = new CaricatureVisual(who, true, false, true, _heads);
                back.Root.Width = width;
                back.Root.Height = height;
                back.Root.Opacity = 0.0;

                var flipBox = new Canvas { Width = width, Height = height, ClipToBounds = false };
                flipScaleX = new ScaleTransform(1.0, 1.0, width * 0.5, height * 0.5);
                flipBox.RenderTransform = flipScaleX;
                flipBox.Children.Add(front.Root);
                flipBox.Children.Add(back.Root);
                container.Children.Add(flipBox);
            }
            else
            {
                container.Children.Add(front.Root);
            }

            double originY = style == "zoom" ? height : height * 0.5;
            var tg = new TransformGroup();
            var zoomScale = new ScaleTransform(1.0, 1.0, width * 0.5, originY);
            var rot = new RotateTransform(0.0, width * 0.5, originY);
            var move = new TranslateTransform(-9999, -9999);
            tg.Children.Add(zoomScale);
            tg.Children.Add(rot);
            tg.Children.Add(move);
            container.RenderTransform = tg;

            return new ActiveRunner
            {
                Style = style,
                Who = who,
                Width = width,
                Height = height,
                DelayMs = delayMs,
                TotalMs = totalMs,
                StartTickMs = nowTick,
                Pitch = pitch,
                From = from,
                To = to,
                Lean = lean,
                Mid = mid,
                FarX = farX,
                NearX = nearX,
                AwayX = awayX,
                Edge = edge,
                Along = along,
                Container = container,
                FlipScaleX = flipScaleX,
                MoveTx = move,
                RotateTx = rot,
                ZoomScaleTx = zoomScale,
                FrontVis = front,
                BackVis = back
            };
        }

        private void SynthesizeAndPlayGroupAudio(List<ActiveRunner> group, double W)
        {
            double maxEnd = 0.2;
            foreach (var r in group)
            {
                double t0 = 0.03 + r.DelayMs / 1000.0;
                double dur = r.TotalMs / 1000.0;
                maxEnd = Math.Max(maxEnd, t0 + dur + 0.5);
            }
            int totalSamples = (int)Math.Ceiling((maxEnd + 0.15) * 44100);
            float[] left = new float[totalSamples];
            float[] right = new float[totalSamples];

            foreach (var r in group)
            {
                double t0 = 0.03 + r.DelayMs / 1000.0;
                var tr = new ZoomieAudio.PanTrack();
                if (r.Style == "dash")
                {
                    double ms = r.TotalMs;
                    double dur = ms / 1000.0;
                    foreach (double f in new[] { 0.0, 0.25, 0.5, 0.75, 1.0 })
                    {
                        double px = Lerp(r.From.X, r.To.X, DashAt(r.Mid, f * ms));
                        tr.Path.Add(Tuple.Create(t0 + f * dur, PanOf(px, W)));
                    }
                    for (double s = 0.05; s < dur; s += 0.1)
                        ZoomieAudio.Step(left, right, tr, t0 + s, 0.1 + 0.25 * Math.Sin((Math.PI * s) / dur));
                    ZoomieAudio.Voice(left, right, tr, r.Who, t0 + 0.05);
                    _audio.Whee(left, right, tr, t0 + 0.4, Math.Max(0.2, dur - 0.3), 560.0 * r.Pitch, 1180.0 * r.Pitch, 620.0 * r.Pitch);
                }
                else if (r.Style == "pop")
                {
                    double pan = r.Edge == "left" ? -0.85 : (r.Edge == "right" ? 0.85 : PanOf(r.Along, W));
                    tr.Path.Add(Tuple.Create(t0, pan));
                    ZoomieAudio.Hop(left, right, tr, t0, 0.4, 1.15);
                    ZoomieAudio.Voice(left, right, tr, r.Who, t0 + POP_IN / 1000.0);
                    double outAt = t0 + (POP_IN + POP_STAY) / 1000.0;
                    _audio.Zip(left, right, tr, outAt);
                    _audio.Whee(left, right, tr, outAt, POP_OUT / 1000.0 + 0.25, 1250.0, 1450.0, 520.0);
                }
                else
                {
                    double away = t0 + TURNED_MS / 1000.0;
                    tr.Path.Add(Tuple.Create(t0, PanOf(r.FarX, W)));
                    tr.Path.Add(Tuple.Create(t0 + (STEPS * STEP_MS) / 1000.0, PanOf(r.NearX, W)));
                    tr.Path.Add(Tuple.Create(away, PanOf(r.NearX, W)));
                    tr.Path.Add(Tuple.Create(away + AWAY_MS / 1000.0, PanOf(r.AwayX, W)));
                    for (int i = 0; i < STEPS; i++)
                    {
                        double prog = (double)i / (STEPS - 1);
                        ZoomieAudio.Hop(left, right, tr, t0 + (i * STEP_MS) / 1000.0, 0.06 + 0.4 * Math.Pow(prog, 1.5), 1.35 - 0.45 * prog);
                    }
                    ZoomieAudio.Voice(left, right, tr, r.Who, t0 + (STEPS * STEP_MS) / 1000.0 + 0.03);
                    _audio.Zip(left, right, tr, t0 + (TURNED_MS - TURN_MS) / 1000.0);
                    for (double s = 0; s < AWAY_MS / 1000.0; s += 0.09)
                        ZoomieAudio.Step(left, right, tr, away + s, 0.3 * (1.0 - (s * 1000.0) / AWAY_MS) + 0.02);
                    _audio.Whee(left, right, tr, away, AWAY_MS / 1000.0 + 0.3, 950.0 * r.Pitch, 1350.0 * r.Pitch, 480.0 * r.Pitch);
                }
            }

            ZoomieAudio.PlayBuffer(left, right);
        }

        private void OnFrameRender(object sender, EventArgs e)
        {
            double now = _clock.Elapsed.TotalMilliseconds;
            double W = Width;
            double H = Height;

            for (int i = _runners.Count - 1; i >= 0; i--)
            {
                var r = _runners[i];
                double elapsed = now - r.StartTickMs - r.DelayMs;
                if (elapsed < 0)
                {
                    r.Container.Opacity = 0.0;
                    continue;
                }
                if (elapsed >= r.TotalMs)
                {
                    _stage.Children.Remove(r.Container);
                    _runners.RemoveAt(i);
                    continue;
                }

                double sec = elapsed / 1000.0;
                if (r.Style == "dash")
                {
                    r.Container.Opacity = 1.0;
                    r.FrontVis.TickParts(sec, 0.2);
                    double p = DashAt(r.Mid, elapsed);
                    double sway = 1.0 - Math.Abs(((elapsed / SWAY_MS) % 2.0) - 1.0);
                    r.MoveTx.X = Lerp(r.From.X, r.To.X, p) - r.Width * 0.5;
                    r.MoveTx.Y = Lerp(r.From.Y, r.To.Y, p) - r.Height * 0.5;
                    r.RotateTx.Angle = r.Lean - 6.0 + 12.0 * sway;
                }
                else if (r.Style == "pop")
                {
                    r.Container.Opacity = 1.0;
                    r.FrontVis.TickParts(sec, 0.6);
                    double deg = r.Edge == "bottom" ? 0.0 : (r.Edge == "left" ? 90.0 : (r.Edge == "top" ? 180.0 : -90.0));
                    double rad = (deg * Math.PI) / 180.0;
                    double ux = Math.Sin(rad), uy = -Math.Cos(rad);
                    Point edgePt = r.Edge == "bottom" ? new Point(r.Along, H)
                                 : r.Edge == "top"    ? new Point(r.Along, 0)
                                 : r.Edge == "left"   ? new Point(0, r.Along)
                                 :                      new Point(W, r.Along);

                    const double shown = 0.74;
                    const double hidden = -0.32;
                    double reach, tilt = 0.0;

                    if (elapsed < POP_IN)
                    {
                        double u = elapsed / POP_IN;
                        // Spring overshoot matching cubic-bezier(0.35, 1, 0.4, 1.2)
                        double ease = 1.0 - Math.Pow(1.0 - u, 3.0) * Math.Cos(u * Math.PI * 0.85);
                        reach = Lerp(hidden, shown, ease);
                    }
                    else if (elapsed < POP_IN + POP_STAY)
                    {
                        double stayElapsed = elapsed - POP_IN;
                        double u = stayElapsed / POP_STAY;
                        if (u < 0.3)
                        {
                            double k = EasyInOut(u / 0.3);
                            reach = Lerp(shown, shown + 0.03, k);
                            tilt = Lerp(0.0, -9.0, k);
                        }
                        else if (u < 0.65)
                        {
                            double k = EasyInOut((u - 0.3) / 0.35);
                            reach = Lerp(shown + 0.03, shown - 0.02, k);
                            tilt = Lerp(-9.0, 8.0, k);
                        }
                        else
                        {
                            double k = EasyInOut((u - 0.65) / 0.35);
                            reach = Lerp(shown - 0.02, shown, k);
                            tilt = Lerp(8.0, 0.0, k);
                        }
                    }
                    else
                    {
                        double u = (elapsed - POP_IN - POP_STAY) / POP_OUT;
                        // Wind-up and shoot back out matching cubic-bezier(0.36, 0, 0.66, -0.56)
                        double windup = (1.7 * u * u * u) - (0.7 * u * u);
                        reach = Lerp(shown, hidden, windup);
                    }

                    double d = reach * r.Height - r.Height * 0.5;
                    r.MoveTx.X = edgePt.X + ux * d - r.Width * 0.5;
                    r.MoveTx.Y = edgePt.Y + uy * d - r.Height * 0.5;
                    r.RotateTx.Angle = deg + tilt;
                }
                else // zoom
                {
                    r.FrontVis.TickParts(sec, 0.64);
                    if (r.BackVis != null) r.BackVis.TickParts(sec, 0.18);

                    double horizon = H * 0.45;
                    double ground = H * 0.97;
                    double s, x, lift = 0.0, tilt = 0.0, opacity = 1.0;

                    double arrived = STEPS * STEP_MS;
                    if (elapsed < arrived)
                    {
                        int stepIdx = Math.Min(STEPS - 1, (int)(elapsed / STEP_MS));
                        double stepU = (elapsed - stepIdx * STEP_MS) / STEP_MS;
                        double s0 = ScaleAt(stepIdx);
                        double s1 = ScaleAt(stepIdx + 1);
                        double sMid = Math.Sqrt(s0 * s1);
                        if (stepU < 0.5)
                        {
                            double k = 1.0 - Math.Pow(1.0 - (stepU * 2.0), 2.0);
                            s = Lerp(s0, sMid, k);
                            lift = r.Height * 0.14 * sMid * k;
                            tilt = ((stepIdx % 2 == 1) ? 5.0 : -5.0) * k;
                        }
                        else
                        {
                            double k = Math.Pow((stepU - 0.5) * 2.0, 2.0);
                            s = Lerp(sMid, s1, k);
                            lift = r.Height * 0.14 * sMid * (1.0 - k);
                            tilt = ((stepIdx % 2 == 1) ? 5.0 : -5.0) * (1.0 - k);
                        }
                        double depth = (s - FAR_S) / (NEAR_S - FAR_S);
                        x = Lerp(r.FarX, r.NearX, depth);
                    }
                    else if (elapsed < TURNED_MS)
                    {
                        s = NEAR_S;
                        x = r.NearX;
                        double u = (elapsed - arrived) / (PEEK_MS + TURN_MS);
                        if (u < 0.33) tilt = Lerp(0.0, -6.0, EasyInOut(u / 0.33));
                        else if (u < 0.66) tilt = Lerp(-6.0, 6.0, EasyInOut((u - 0.33) / 0.33));
                        else tilt = Lerp(6.0, 0.0, EasyInOut((u - 0.66) / 0.34));
                    }
                    else
                    {
                        double awayU = (elapsed - TURNED_MS) / AWAY_MS;
                        if (awayU < 0.45)
                        {
                            double k = Math.Pow(awayU / 0.45, 2.0);
                            s = Lerp(NEAR_S, 0.4, k);
                            lift = r.Height * 0.08 * Math.Sin(k * Math.PI);
                            opacity = 1.0;
                        }
                        else
                        {
                            double k = (awayU - 0.45) / 0.55;
                            s = Lerp(0.4, 0.02, k);
                            lift = r.Height * 0.08 * (1.0 - k);
                            opacity = 1.0 - k;
                        }
                        double depth = (s - FAR_S) / (NEAR_S - FAR_S);
                        x = Lerp(r.AwayX, r.NearX, depth);
                    }

                    // Turn-around flip between TURNED_MS - TURN_MS and TURNED_MS
                    double turnStart = TURNED_MS - TURN_MS;
                    double turnMid = TURNED_MS - TURN_MS * 0.5;
                    if (elapsed < turnStart)
                    {
                        r.FlipScaleX.ScaleX = 1.0;
                        r.FrontVis.Root.Opacity = 1.0;
                        r.BackVis.Root.Opacity = 0.0;
                    }
                    else if (elapsed < turnMid)
                    {
                        double k = (elapsed - turnStart) / (TURN_MS * 0.5);
                        r.FlipScaleX.ScaleX = Lerp(1.0, 0.1, k);
                        r.FrontVis.Root.Opacity = 1.0;
                        r.BackVis.Root.Opacity = 0.0;
                    }
                    else if (elapsed < TURNED_MS)
                    {
                        double k = (elapsed - turnMid) / (TURN_MS * 0.5);
                        r.FlipScaleX.ScaleX = Lerp(0.1, 1.0, k);
                        r.FrontVis.Root.Opacity = 0.0;
                        r.BackVis.Root.Opacity = 1.0;
                    }
                    else
                    {
                        r.FlipScaleX.ScaleX = 1.0;
                        r.FrontVis.Root.Opacity = 0.0;
                        r.BackVis.Root.Opacity = 1.0;
                    }

                    double groundY = Lerp(horizon, ground, (s - FAR_S) / (NEAR_S - FAR_S));
                    r.Container.Opacity = Math.Max(0.0, Math.Min(1.0, opacity));
                    r.ZoomScaleTx.ScaleX = s;
                    r.ZoomScaleTx.ScaleY = s;
                    r.RotateTx.Angle = tilt;
                    r.MoveTx.X = x - r.Width * 0.5;
                    r.MoveTx.Y = groundY - r.Height - lift;
                }
            }

            if (_runners.Count == 0)
            {
                CompositionTarget.Rendering -= OnFrameRender;
                _renderingHooked = false;
                if (_once)
                {
                    Close();
                }
                else
                {
                    int nextWait = _minGapMs + _rng.Next(Math.Max(1, _maxGapMs - _minGapMs));
                    ScheduleNext(nextWait);
                }
            }
        }

        private static double EasyInOut(double t)
        {
            t = Math.Max(0.0, Math.Min(1.0, t));
            return 0.5 - 0.5 * Math.Cos(Math.PI * t);
        }
    }
}
'@

$WorkerScriptContent = @'
param(
    [int]$MinGapSec = 15,
    [int]$MaxGapSec = 30,
    [string]$Scope = 'full_screen',
    [Alias('silent-mode')]
    [switch]$Mute,
    [switch]$Once,
    [DateTime]$ExpiresAtUtc,
    [DateTime]$StartsAtUtc,
    [string]$CleanupTaskName
)
$ErrorActionPreference = 'Stop'
$InstallDir = $PSScriptRoot
$HeadsDir   = Join-Path $InstallDir 'heads'
$PidFile    = Join-Path $InstallDir 'zoomies.pid'
$CsFile     = Join-Path $InstallDir 'ZoomiesOverlay.cs'

Set-Content -Path $PidFile -Value $PID -Encoding ASCII -Force

$ReferencedAssemblies = @(
    'PresentationFramework',
    'PresentationCore',
    'WindowsBase',
    'System.Xaml',
    'System.Drawing',
    'System.Windows.Forms'
)
$errorWriter = New-Object IO.StreamWriter((Join-Path $InstallDir 'worker-error.log'), $false)
$errorWriter.AutoFlush = $true
[Console]::SetError($errorWriter)
try {
    $cs = Get-Content -LiteralPath $CsFile -Raw
    Add-Type -TypeDefinition $cs -ReferencedAssemblies $ReferencedAssemblies
    $app = [System.Windows.Application]::Current
    if (-not $app) {
        $app = New-Object System.Windows.Application
    }
    $win = New-Object CorpFunZoomies.ZoomiesOverlayWindow($HeadsDir, $MinGapSec, $MaxGapSec, $Scope, [bool]$Mute, [bool]$Once, $ExpiresAtUtc, $StartsAtUtc)
    [void]$app.Run($win)
} catch {
    $errorWriter.WriteLine($_.ToString())
    throw
} finally {
    if ((Test-Path -LiteralPath $PidFile) -and (Get-Content -LiteralPath $PidFile -Raw).Trim() -eq [string]$PID) {
        Remove-Item -LiteralPath $PidFile -Force
    }
    $errorWriter.Dispose()
    if ([DateTime]::UtcNow -ge $ExpiresAtUtc.ToUniversalTime() -and $CleanupTaskName) {
        $cleanup = Get-ScheduledTask -TaskPath '\' -ErrorAction Stop |
            Where-Object { $_.TaskName -eq $CleanupTaskName }
        if ($cleanup) { Start-ScheduledTask -TaskName $CleanupTaskName -TaskPath '\' -ErrorAction Stop }
    }
}
'@

$UninstScriptContent = @'
param(
    [switch]$StopOnly,
    [switch]$ScheduledCleanup,
    [Nullable[DateTime]]$CleanupAtUtc
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'Device Companion requires Windows and a per-user LOCALAPPDATA directory.'
}
$InstallDir = Join-Path $env:LOCALAPPDATA 'CorpFunZoomies'
if ($ScheduledCleanup) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Scheduled cleanup must run from the installed uninstall script.'
    }
    $InstallDir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($PSCommandPath))
    if ([IO.Path]::GetFileName($PSCommandPath) -ne 'uninstall.ps1' -or [IO.Path]::GetFileName($InstallDir) -ne 'CorpFunZoomies') {
        throw 'Refusing scheduled cleanup outside its own companion installation.'
    }
}
$PidFile    = Join-Path $InstallDir 'zoomies.pid'
$WorkerFile = Join-Path $InstallDir 'run-zoomies.ps1'
$RegRunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RegRunName = 'CorpFunZoomies'
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $pathBytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($InstallDir).ToLowerInvariant())
    $taskId = ([BitConverter]::ToString($sha.ComputeHash($pathBytes))).Replace('-', '').Substring(0, 16)
} finally {
    $sha.Dispose()
}
$CleanupTaskName = "DeviceCompanionCleanup-$taskId"

if ($ScheduledCleanup) {
    if ($null -eq $CleanupAtUtc) {
        throw 'Scheduled cleanup requires its original uninstall deadline.'
    }
    if ([DateTime]::UtcNow -lt $CleanupAtUtc.ToUniversalTime()) {
        return
    }
}

Write-Host "[*] Stopping Device Companion..." -ForegroundColor Yellow
$workerPattern = [regex]::Escape($WorkerFile)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $workerPattern } |
    ForEach-Object {
        $process = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
        if ($process -and -not $process.HasExited) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            } catch {
                if ($_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound) { throw }
            }
            if (-not $process.WaitForExit(5000)) { throw 'The companion worker did not stop.' }
        }
    }
foreach ($file in @($PidFile, (Join-Path $InstallDir 'zoomies.ready'))) {
    if (Test-Path -LiteralPath $file) {
        Remove-Item -LiteralPath $file -Force
    }
}
if ((Test-Path -LiteralPath $RegRunPath) -and (Get-Item -LiteralPath $RegRunPath).GetValueNames() -contains $RegRunName) {
    Remove-ItemProperty -LiteralPath $RegRunPath -Name $RegRunName -Force
}
if (-not $StopOnly -and (Test-Path -LiteralPath $InstallDir)) {
    if ((Get-Item -LiteralPath $InstallDir).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing to delete a linked installation directory.'
    }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
if (-not $StopOnly) {
    $tasks = Get-ScheduledTask -TaskPath '\' -ErrorAction Stop |
        Where-Object { $_.TaskName -eq $CleanupTaskName }
    foreach ($task in $tasks) {
        if ($task.Actions.Count -ne 1 -or $task.Actions[0].Arguments -notmatch [regex]::Escape((Join-Path $InstallDir 'uninstall.ps1'))) {
            throw 'Refusing to remove a cleanup task with an unexpected action.'
        }
        Unregister-ScheduledTask -TaskName $CleanupTaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
    }
}
if ($StopOnly) {
    Write-Host '[OK] Device Companion stopped. Its automatic cleanup job is still scheduled.' -ForegroundColor Green
} else {
    Write-Host '[OK] Device Companion has been completely uninstalled.' -ForegroundColor Green
}
'@

if ($Uninstall) {
    & ([scriptblock]::Create($UninstScriptContent))
    return
}
if ($MaxGapSec -lt $MinGapSec) {
    throw 'MaxGapSec must be greater than or equal to MinGapSec.'
}
if ($null -ne $ExpiresAtUtc -and $ExpiresAtUtc.ToUniversalTime() -le [DateTime]::UtcNow) {
    throw 'The end time must be in the future.'
}
Write-Host ''
Write-Host 'device companion which may use desktop visual and sound.' -ForegroundColor Cyan
Write-Host 'Includes a cleanup-only job; automatic removal is at the next local 4:00 pm after cooldown.'
if (-not $Accept) {
    $answer = Read-Host 'Install and start Device Companion? Type YES to continue'
    if ($answer.Trim() -cne 'YES') {
        Write-Host 'Cancelled. No files or startup settings were changed.'
        return
    }
}

Install-CaricatureAssets
Stop-ExistingZoomies
Set-Content -Path $CsFile -Value $CSharpSource -Encoding ASCII -Force
Set-Content -Path $WorkerFile -Value $WorkerScriptContent -Encoding ASCII -Force
Set-Content -Path $UninstFile -Value $UninstScriptContent -Encoding ASCII -Force

Write-Host '[*] Installing Device Companion...' -ForegroundColor Cyan

if ((Test-Path -LiteralPath $RegRunPath) -and (Get-Item -LiteralPath $RegRunPath).GetValueNames() -contains $RegRunName) {
    Remove-ItemProperty -LiteralPath $RegRunPath -Name $RegRunName -Force
}

try {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $installedAt = [DateTime]::UtcNow
        $cleanupAt = if ($null -ne $ExpiresAtUtc) { $ExpiresAtUtc.ToUniversalTime() } else {
            Get-CompanionCleanupAt -InstalledAtUtc $installedAt -CooldownSeconds $InitialDelaySec
        }
        Register-CompanionCleanup -CleanupAtUtc $cleanupAt
        $installedAt = [DateTime]::UtcNow
        $finalCutoff = if ($null -ne $ExpiresAtUtc) { $cleanupAt } else {
            Get-CompanionCleanupAt -InstalledAtUtc $installedAt -CooldownSeconds $InitialDelaySec
        }
        if ($finalCutoff -eq $cleanupAt) { break }
    }
    if ($finalCutoff -ne $cleanupAt) { throw 'The local clock changed during cleanup scheduling. Try installation again.' }
    $startsAt = $installedAt.AddSeconds($InitialDelaySec)
    @{
        installedAtUtc = $installedAt.ToString('o')
        firstAnimationAtUtc = $startsAt.ToString('o')
        cleanupAtUtc = $cleanupAt.ToString('o')
        cleanupTask = $CleanupTaskName
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallDir 'installation.json') -Encoding ASCII

    if ($RunWorker -or $Once) {
        & $WorkerFile -MinGapSec $MinGapSec -MaxGapSec $MaxGapSec -Scope $Scope -Mute:$Mute -Once:$Once `
            -ExpiresAtUtc $cleanupAt -StartsAtUtc $startsAt -CleanupTaskName $CleanupTaskName
        return
    }
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA',
        '-File', "`"$WorkerFile`"", '-MinGapSec', $MinGapSec, '-MaxGapSec', $MaxGapSec,
        '-Scope', $Scope, '-ExpiresAtUtc', $cleanupAt.ToString('o'),
        '-StartsAtUtc', $startsAt.ToString('o'), '-CleanupTaskName', $CleanupTaskName
    )
    if ($Mute) { $argList += '-Mute' }
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -PassThru
    Set-Content -Path $PidFile -Value $proc.Id -Encoding ASCII -Force
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $ReadyFile) -and -not $proc.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $proc.Refresh()
    }
    if ($proc.HasExited -or -not (Test-Path -LiteralPath $ReadyFile)) {
        $details = if (Test-Path -LiteralPath $ErrorFile) { Get-Content -LiteralPath $ErrorFile -Raw } else { 'No ready signal was received.' }
        throw "Device Companion failed to start. $details"
    }
} catch {
    $failure = $_
    try { & ([scriptblock]::Create($UninstScriptContent)) } catch {
        Write-Warning "Installation rollback failed: $($_.Exception.Message)"
    }
    throw $failure
}
Write-Host "[OK] Device Companion is installed and cooling down. (PID: $($proc.Id))" -ForegroundColor Green
Write-Host "   * First animation : $($startsAt.ToLocalTime().ToString('f'))" -ForegroundColor Gray
Write-Host "   * Automatic uninstall : $($cleanupAt.ToLocalTime().ToString('f'))" -ForegroundColor Gray
Write-Host "   * Quiet interval : $MinGapSec-$MaxGapSec seconds" -ForegroundColor Gray
Write-Host "   * Scope     : $Scope (click-through overlay on your active monitor/window)" -ForegroundColor Gray
Write-Host "   * Sound     : $(if ($Mute) { 'Muted' } else { 'Enabled' })" -ForegroundColor Gray
Write-Host ""
Write-Host "To uninstall anytime after the event, run:" -ForegroundColor Yellow
Write-Host "   powershell -NoProfile -ExecutionPolicy Bypass -File `"$UninstFile`"" -ForegroundColor White
Write-Host "   or: irm $RepoRawBase/uninstall.ps1 | iex" -ForegroundColor White
