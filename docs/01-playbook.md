# 🧭 The Diagnosis Playbook

> Work through this **in order**. Stop as soon as you find your problem.
> Step 1 and 2 catch roughly 90 % of stutter cases.

---

## Before you start

```powershell
# Close the game. It locks the database while running.
Get-Process Client-Win64-Shipping -ErrorAction SilentlyContinue

# Find your install path (the launcher stores it)
Get-ItemProperty 'HKCU:\Software\kurogame\KRLauncher\*\*' -ErrorAction SilentlyContinue |
    Select-Object SingleLauncherInstallPath
```

Throughout this guide we assume:

```powershell
$Game = 'D:\Games\Wuthering Waves'      # ← change to your path
$Cfg  = "$Game\Wuthering Waves Game\Client\Saved\Config\WindowsNoEditor"
$Db   = "$Game\Wuthering Waves Game\Client\Saved\LocalStorage\LocalStorage.db"
```

---

## Step 1 — Read what the game is *actually* set to

Most people never do this. They look at the in-game menu, see one value, and assume that's the truth. It usually isn't.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\read-game-settings.ps1
```

Or by hand, with Python (no extra packages needed):

```powershell
python -c "import sqlite3;c=sqlite3.connect(r'$Db').cursor();[print(k,'=',c.execute('SELECT value FROM LocalStorage WHERE key=?',(k,)).fetchone()[0]) for k in ['PcVsync','CustomFrameRate','NvidiaSuperSamplingFrameGenerate','PcResolutionIndex']]"
```

### What you're looking for

| Key | Bad value | Good value | Meaning |
|---|---|---|---|
| `PcVsync` | `1` | **`0`** | VSync. The single biggest stutter source. |
| `CustomFrameRate` | `2` (60) | **`3`** (120) | Frame cap index. See [reference](02-settings-reference.md). |
| `NvidiaSuperSamplingFrameGenerate` | `1` | **`0`** | DLSS Frame Generation. |
| `NvidiaSuperSamplingEnable` | — | `1` | DLSS Super Resolution (keep ON, it's good). |

> 💡 **If `PcVsync = 1`, you have found your bug. Skip to step 3.**

---

## Step 2 — Confirm the cap is real (not just a leftover value)

A stored value doesn't always mean an active setting. Prove it with a 10-minute session:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\wu-telemetry.ps1
# go play for 10 minutes, then come back
python .\tools\analyze-telemetry.py .\wu-telemetry.csv
```

The analyzer prints a verdict line. Interpret it like this:

| Analyzer says | Meaning | Go to |
|---|---|---|
| `GPU-BOUND` | GPU at 95 %+ — lower resolution or quality | [Step 5](#step-5--if-you-are-gpu-bound) |
| `CPU-BOUND` | One core pegged at 90 %+, GPU idle | [Step 5](#step-5--if-you-are-cpu-bound) |
| `CAPPED` | GPU at 50–70 % *evenly*, never spikes | [Step 3](#step-3--fix-vsync-and-the-frame-cap) |
| `THERMAL` | Temperature pinned at your limit | [Step 6](#step-6--if-you-are-thermal-throttled) |

---

## Step 3 — Fix VSync and the frame cap

The in-game menu will not let you set the frame cap while Frame Generation is on. **Turn FG off first.**

### Option A — the normal way (recommended)

1. In game: **Graphics → DLSS → Frame Generation → OFF**
2. The **Frame Rate** option unlocks → set **120**
3. **VSync → OFF**
4. Quit the game, relaunch, confirm both stuck

### Option B — edit the database directly

Use this when the menu refuses, or when you want to script it.

```powershell
# 1. backup first
Copy-Item $Db "$Db.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# 2. write the values
python - <<'PY'
import sqlite3, os
db = os.environ['DB']
con = sqlite3.connect(db); cur = con.cursor()
for k, v in {
    "PcVsync": "0",                          # VSync OFF
    "CustomFrameRate": "3",                  # 120 FPS
    "NvidiaSuperSamplingFrameGenerate": "0", # Frame Gen OFF
    "NvidiaSuperSamplingEnable": "1",        # DLSS ON
}.items():
    cur.execute("UPDATE LocalStorage SET value=? WHERE key=?", (v, k))
con.commit(); con.close()
print("done")
PY
```

In plain PowerShell without a heredoc:

```powershell
$env:DB = $Db
```

Then launch the game and **verify in the menu** that VSync reads Off.

> 🔁 **Always re-read the values after playing.** The game writes them back on exit. If they reverted, something in-game is overriding you — repeat option A.

---

## Step 4 — Windows-level checks (2 minutes, free wins)

```powershell
# Game Mode — should be 1
Get-ItemProperty 'HKCU:\Software\Microsoft\GameBar' -Name AutoGameModeEnabled

# Hardware-accelerated GPU scheduling — 2 = on, 1 = off, absent = default
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode

# Power plan + power mode
powercfg /getactivescheme
```

- **Game Mode ON** → Settings → Gaming → Game Mode
- **Power plan** → plug in the laptop, choose *Best performance* or *Balanced*, never *Battery saver*
- **Fullscreen vs Borderless** → fullscreen usually has the cleanest frame pacing; borderless locks your resolution to the desktop (which is why the option greys out)

---

## Step 5 — If you are GPU-bound

Lower these first, they cost the most bandwidth per frame:

| Setting | Try |
|---|---|
| Resolution | one step down |
| DLSS mode | Quality → Balanced → Performance |
| Shadow Quality | −1 |
| Volumetric Fog / Light | −1 |

## Step 5b — If you are CPU-bound

Resolution and DLSS **will not help**. The GPU is already waiting. Cut CPU work instead:

| Setting | Try | Why |
|---|---|---|
| Shadow Quality | −1 | shadow casters are per-object CPU work |
| Niagara / Particle Quality | −1 | combat particles are the #1 combat cost |
| View Distance | −1 | more actors alive = more simulation |
| Crowd / NPC density | −1 | if present |

---

## Step 6 — If you are thermal throttled

Only relevant if the analyzer says `THERMAL` (temperature pinned at the limit).

1. Clean the fans and vents. A 3-year-old gaming laptop with dusty fins loses 20–30 % of its cooling capacity.
2. Raise the temperature target if your vendor tool allows it — throttling earlier than necessary costs performance for no benefit.
3. Undervolt the CPU if you know how — same performance, less heat.

> 🧊 **In our test machine the thermal cap never engaged** (max 72.9 °C against an 85 °C limit). Don't assume heat until you've measured it.

---

## Step 7 — Verify the fix

```powershell
python .\tools\analyze-telemetry.py .\wu-telemetry.csv
```

You want to see the verdict change, plus:

- `GPU util max` climbing toward 95 %+ *(the GPU is finally being asked to work)*
- `>=90%` share rising *(fewer idle frames)*
- Temperatures still sane (< 85 °C)

Then judge with your hands, not the menu badge. **Play 10 minutes and ask: does combat feel smooth?**

---

## The one-page summary

```
Stutter?
├─ First visit to a new zone only → shader/streaming. Ignore it.
├─ Combat only, GPU < 70 %        → VSync or a frame cap (steps 2–3)
├─ Combat only, one CPU core 90 %+ → CPU-bound (step 5b)
├─ Everywhere, GPU 95 %+           → GPU-bound (step 5)
└─ Temperature at your limit       → thermal (step 6)
```

---

**Next:** [settings reference →](02-settings-reference.md)
