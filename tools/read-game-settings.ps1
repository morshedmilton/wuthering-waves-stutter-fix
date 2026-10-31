<#
.SYNOPSIS
    Read the REAL graphics settings of Wuthering Waves from LocalStorage.db.

.DESCRIPTION
    Read-only. Prints every graphics-related key with a verdict column so you
    can see at a glance which values are hurting you.

    Requires Python 3 (uses the built-in sqlite3 module - no pip installs).

.PARAMETER GamePath
    Optional. Root of the game install. Auto-detected from the launcher
    registry key when omitted.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\read-game-settings.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\read-game-settings.ps1 -GamePath "E:\Games\Wuthering Waves"
#>
[CmdletBinding()]
param(
    [string]$GamePath
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- find game
if (-not $GamePath) {
    $reg = Get-ItemProperty 'HKCU:\Software\kurogame\KRLauncher\*\*' -ErrorAction SilentlyContinue |
           Select-Object -First 1 -ExpandProperty SingleLauncherInstallPath
    if ($reg) { $GamePath = $reg }

    if (-not $GamePath) {
        foreach ($guess in @('C:\Wuthering Waves','D:\Wuthering Waves','D:\Games\Wuthering Waves','E:\Games\Wuthering Waves')) {
            if (Test-Path (Join-Path $guess 'Wuthering Waves Game')) { $GamePath = $guess; break }
        }
    }
}

if (-not $GamePath) {
    Write-Host 'Could not find the game. Pass -GamePath "X:\...\Wuthering Waves"' -ForegroundColor Red
    exit 1
}

$db = Join-Path $GamePath 'Wuthering Waves Game\Client\Saved\LocalStorage\LocalStorage.db'
if (-not (Test-Path $db)) {
    Write-Host "LocalStorage.db not found at: $db" -ForegroundColor Red
    Write-Host 'Launch the game once so it creates the profile, then retry.' -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------- find python
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $py) {
    Write-Host 'Python 3 is required (sqlite3 is built in). Install it, or open the DB' -ForegroundColor Red
    Write-Host "manually in any SQLite browser: $db" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Wuthering Waves - real settings' -ForegroundColor Cyan
Write-Host ('=' * 62)
Write-Host "Database: $db" -ForegroundColor DarkGray
Write-Host ''

# copy first: the game may hold the file open
$tmp = Join-Path $env:TEMP ('wu_' + [guid]::NewGuid().ToString('N') + '.db')
Copy-Item $db $tmp -Force

$script = @'
import sqlite3, sys

RULES = {
    "PcVsync":                          ("0",  "VSync. 0 = OFF. THIS IS THE BIG ONE."),
    "CustomFrameRate":                  ("3",  "3 = 120 fps, 2 = 60 fps, 1 = 30 fps"),
    "NvidiaSuperSamplingFrameGenerate": ("0",  "Frame Generation. 0 = OFF (unlocks the fps cap)"),
    "NvidiaSuperSamplingEnable":        ("1",  "DLSS Super Resolution. Keep ON."),
    "NvidiaSuperSamplingQuality":       ("99", "99 = Auto"),
    "PcWindowMode":                     (None, "0 = fullscreen/borderless"),
    "PcResolutionIndex":                (None, "index into the resolution list (mapping unknown)"),
    "IsUsingQualityPreset":             (None, "___1B___ = a preset is overriding your settings"),
    "ImageQuality":                     (None, "overall preset index"),
    "ImageDetail":                      (None, "geometry detail"),
    "ShadowQuality":                    (None, "heaviest combat cost (CPU+GPU)"),
    "NiagaraQuality":                   (None, "particles - #1 combat cost"),
    "AntiAliasing":                     (None, "AA mode"),
    "MotionBlur":                       (None, "motion blur level"),
    "BloomEnable":                      (None, "bloom on/off"),
    "VolumeFog":                        (None, "volumetric fog"),
    "VolumeLight":                      (None, "volumetric light"),
    "RayTracedShadow":                  (None, "ray traced shadows"),
    "AnisoLevel":                       (None, "anisotropic filtering"),
    "LoadingRangeScaleLevel":           (None, "streaming distance"),
    "AutoAdjustImageQuality":           (None, "dynamic resolution"),
}

con = sqlite3.connect(sys.argv[1])
cur = con.cursor()

def get(k):
    cur.execute("SELECT value FROM LocalStorage WHERE key=?", (k,))
    r = cur.fetchone()
    return r[0] if r else None

print("%-36s %-12s %-8s %s" % ("KEY", "YOURS", "WANT", "MEANING"))
print("-" * 104)

issues = 0
for k, (want, meaning) in RULES.items():
    v = get(k)
    if v is None:
        continue
    mark = ""
    if want is not None and str(v) != want:
        mark = "  <-- FIX"
        issues += 1
    print("%-36s %-12s %-8s %s%s" % (k, str(v), (want if want else "-"), meaning, mark))

print()
if issues:
    print(">> %d setting(s) need attention." % issues)
else:
    print(">> All key settings look correct.")
con.close()
'@

$pyFile = Join-Path $env:TEMP ('wu_read_' + [guid]::NewGuid().ToString('N') + '.py')
[IO.File]::WriteAllText($pyFile, $script, (New-Object Text.UTF8Encoding($false)))

try {
    & $py $pyFile $tmp
} finally {
    Remove-Item $tmp, $pyFile -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Note: values are only trustworthy while the game is CLOSED.' -ForegroundColor DarkGray
Write-Host '      The game rewrites this database when you quit.' -ForegroundColor DarkGray
