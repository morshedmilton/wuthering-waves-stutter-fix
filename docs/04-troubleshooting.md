# 📕 Troubleshooting

> Symptom → cause → fix. Find your row, do the thing.

---

## Quick matrix

| Symptom | Most likely cause | Fix |
|---|---|---|
| FPS drops **only in combat**, smooth otherwise | VSync + frame cap | [→](#1-combat-stutter--the-classic) |
| Brief hitch **entering a new area**, then fine | shader compilation / streaming | [→](#2-first-time-in-a-new-zone) |
| Stutter **everywhere**, all the time | GPU-bound or a hard cap | [→](#3-stutter-everywhere) |
| FPS limit option is **greyed out** | Frame Generation is ON | [→](#4-the-frame-rate-option-is-greyed-out) |
| Resolution is **greyed out** | borderless windowed mode | [→](#5-resolution-is-greyed-out) |
| Settings **revert after quitting** | you edited the `.ini`, not the `.db` | [→](#6-settings-revert-after-every-launch) |
| Game shows **"Laggy"** next to 120 FPS | static heuristic, not a measurement | [→](#7-the-game-says-laggy) |
| Fine on AC, awful on battery | power limits | [→](#8-only-bad-on-battery) |
| Stutter after Alt-Tab | fullscreen / exclusive state | [→](#9-stutter-after-alt-tab) |
| Micro-stutter despite high FPS | frame pacing / VRR disabled | [→](#10-high-fps-but-still-juddery) |

---

## 1. Combat stutter — the classic

**Symptom.** Walking and story scenes are fine. The moment enemies appear, FPS falls and keeps falling for the whole fight.

**Cause.** VSync with a low frame cap. Every frame that misses its deadline is discarded, and the next one is shown a full refresh interval later. Combat pushes frame times just past the deadline, so you get a constant 60 ↔ 30 oscillation.

**Fix.** VSync **OFF**. Then set a cap your machine can actually hold (120 on this class of hardware).

**Verify.**

```powershell
python .\tools\analyze-telemetry.py .\wu-telemetry.csv
# want: verdict changes away from CAPPED, GPU util max climbs to 95 %+
```

If stutter survives with VSync off, you're CPU-bound — see [step 5b](01-playbook.md#step-5b--if-you-are-cpu-bound).

---

## 2. First time in a new zone

**Symptom.** Entering an area you've never visited: a second of hitching, then perfectly smooth. Coming back later: no hitch at all.

**Cause.** Unreal Engine compiles shaders and streams textures on first contact. This is **expected behaviour**, not a fault.

**Fix.** None needed. It improves permanently as the cache fills:

```
...\Saved\PSO\D3D12\*.ushaderprecache    ← the shader cache
```

**Do not delete that folder.** Deleting it re-creates the problem from scratch.

**If it never improves**, the drive is the bottleneck — check the game isn't on a spinning HDD or a network drive.

---

## 3. Stutter everywhere

Run the analyzer and read the verdict:

| Verdict | Do this |
|---|---|
| `GPU-BOUND` | Lower resolution, DLSS mode, shadows |
| `CPU-BOUND` | Lower shadows, particles, view distance — **not** resolution |
| `CAPPED` | Disable VSync, raise the frame cap |
| `THERMAL` | Clean the fans; only then consider undervolting |

More than one can be true at once.

---

## 4. The frame-rate option is greyed out

**Cause.** Frame Generation is ON. The game decides pacing for you and disables manual caps.

**Fix.**

1. Graphics → DLSS → **Frame Generation → OFF**
2. Set Frame Rate → **120**
3. Optional: turn FG back on — but note the cap locks again

**Trade-off.** FG at a 60 FPS base feels *worse* than native 120, even though both report "120". [Measured here.](03-measurements.md#the-ab-test)

---

## 5. Resolution is greyed out

**Cause.** Borderless windowed mode always uses the desktop resolution, so there's nothing to choose.

**Fix.** Either accept it (you're already running at desktop resolution — usually the sharpest option), or switch **Display Mode → Fullscreen**, which unlocks the resolution list.

> On a 1920×1080 laptop panel, borderless *is* native. Nothing is being lost.

---

## 6. Settings revert after every launch

**Cause.** `GameUserSettings.ini` is regenerated on exit from the game's internal state. Your edit is a printout, not the source.

**Fix.** Edit `LocalStorage.db` instead — see [settings reference](02-settings-reference.md).

**Then always re-read after playing:**

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\read-game-settings.ps1
```

If the value reverted anyway, something inside the game is enforcing it. Change it from the in-game menu instead.

---

## 7. The game says "Laggy"

That badge is a **static heuristic** — the game looks at your GPU model and shows a canned warning. It is not a measurement of your machine.

In our test, the game flagged 120 FPS as "Laggy" and 120-with-FG as fine. The opposite was true: native 120 measured better on every axis and felt dramatically smoother.

**Ignore the badge. Trust your hands and the telemetry.**

---

## 8. Only bad on battery

**Cause.** On battery the GPU drops to a fraction of its power budget and the CPU caps its boost.

**Fix.** Plug in. If you must play unplugged:

```powershell
powercfg /getactivescheme
# set Best performance, and check the NVIDIA control panel for battery-boost style features
```

Also check **NVIDIA App → Settings → Battery Boost / Whisper Mode** — both cap frame rate.

---

## 9. Stutter after Alt-Tab

**Cause.** Borderless windowed mode loses exclusive presentation when you switch away, and re-acquires it inconsistently.

**Fix.** Use **fullscreen** for the cleanest behaviour, or avoid Alt-Tabbing mid-fight. Windows 11's *Optimizations for windowed games* can help:

```
Settings → System → Display → Graphics → Change default graphics settings
  → Optimizations for windowed games = ON
```

---

## 10. High FPS but still juddery

**Symptom.** The counter says 100+ but motion looks uneven, especially when the frame rate fluctuates.

**Cause.** No variable refresh. A 120 → 105 dip without VRR is visible as a stutter even though nothing "dropped".

**Fix.** Enable **G-SYNC / VRR**:

```
NVIDIA Control Panel → Display → Set up G-SYNC → Enable
```

If the option doesn't appear, your panel doesn't support it — in that case pick a cap your machine holds *rock solid* rather than the highest number it can touch.

---

## 🚑 Emergency: restore from backup

Every script in this repo copies the file before writing:

```
LocalStorage.db.bak-20261031-144325
GameUserSettings.ini.bak-20261031-131145
```

To roll back:

```powershell
# close the game first!
Copy-Item "$Db.bak-20261031-144325" $Db -Force
```

**If the database is corrupt** (game crashes on launch, settings won't save):

1. Rename `LocalStorage.db` → `LocalStorage.db.broken`
2. Launch the game — it recreates a fresh database and a default profile
3. Re-apply the two settings you care about (`PcVsync = 0`, `CustomFrameRate = 3`)

You'll lose keybinds and UI prefs, but the account and progress are server-side and safe.

---

## 🔍 Things that look like the problem but aren't

| Suspicious thing | Why it's a red herring |
|---|---|
| `WHEA-Logger` event 17 — *"corrected hardware error"* | Normal Optimus PCIe link noise. Corrected by hardware. |
| `nvidia-smi` "SW Thermal Slowdown: 444000 us" | Inconsistent with uptime — unreliable on laptops |
| 5 × `NVIDIA Overlay.exe` processes | Normal: one per rendered app |
| `Client.log` full of unreadable bytes | Encrypted by the game — not a corruption |
| Old `Wuthering Waves` path in the registry | Stale launcher entry from a moved install |
| GPU clock dipping to 1110 MHz | Power management when the scene is light — not throttling |

---

## Still stuck?

Collect these three things and open an issue:

1. `read-game-settings.ps1` output
2. A 5-minute telemetry CSV
3. A one-line description of *when* it stutters

With those, the answer is usually one line.

---

**Back to:** [README](../README.md) · [playbook](01-playbook.md)
