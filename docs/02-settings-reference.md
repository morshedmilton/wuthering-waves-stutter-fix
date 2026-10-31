# 📗 Settings Reference

> Everything this game stores, what it means, and how confident we are.
>
> **Confidence key:** ✅ verified on a real machine · 🟡 observed, mapping guessed · ⚪ unknown

---

## Two files, one truth

| File | Role | Trust it? |
|---|---|---|
| `...\Saved\Config\WindowsNoEditor\GameUserSettings.ini` | UE4's standard settings file. **The game rewrites it on exit.** | ❌ **No** — a decoy |
| `...\Saved\LocalStorage\LocalStorage.db` | SQLite key/value store. **The real thing.** | ✅ **Yes** |

### Why the `.ini` is a decoy

Look at what happened in our session:

```
14:38  ─ game exits, writes GameUserSettings.ini
         bUseVSync=True          ← my edit, reverted
         ResolutionSizeX=1280    ← my edit, reverted
         FrameRateLimit=60       ← my edit, reverted

         LocalStorage.db → PcVsync=1  ← the value that actually mattered
```

The `.ini` is written *from* the in-memory state. Change it before launch and it gets read, then immediately overwritten by whatever the database says. You are editing a printout, not the source.

---

## The database

### Schema

```sql
CREATE TABLE LocalStorage (
    key   TEXT PRIMARY KEY,
    value TEXT
);
```

188 rows on a fresh profile. Values are stored as strings; the game serialises booleans as `"___1B___"` / `"___0B___"`.

### Dump everything

```powershell
python -c "import sqlite3,sys;[print('%-42s %s'%(k,v)) for k,v in sqlite3.connect(sys.argv[1]).execute('SELECT key,value FROM LocalStorage ORDER BY key')]" "$Db"
```

---

## Graphics keys

### The four that matter ✅

| Key | Type | Values | Notes |
|---|---|---|---|
| `PcVsync` | `0` / `1` | `0` = OFF · `1` = ON | **Setting this to `0` is the single highest-value change in this guide.** Verified: the in-game toggle follows it. |
| `CustomFrameRate` | index | `2` = 60 · `3` = 120 | ✅ Both observed on the same machine. `0`/`1` not confirmed — probably 30 / 60. Only editable in-game **when Frame Generation is OFF**. |
| `NvidiaSuperSamplingFrameGenerate` | `0` / `1` | `0` = FG off · `1` = FG on | Turning this off **unlocks** the frame-rate option. |
| `NvidiaSuperSamplingEnable` | `0` / `1` | `0` = DLSS off · `1` = DLSS on | Super Resolution. Keep `1` — it's free performance. |

### Display ✅ / 🟡

| Key | Our value | Notes |
|---|---|---|
| `PcResolutionIndex` | `10` | 🟡 An index into the game's resolution list. **Mapping unknown** — don't guess, set resolution in-game. Index `10` corresponded to 720p in the `.ini` while the display showed 1920×1080, which suggests borderless mode ignores it. |
| `PcWindowMode` | `0` | 🟡 `0` = fullscreen or borderless. Resolution greys out in borderless because the desktop resolution wins. |

### Image quality 🟡

| Key | Our value | Notes |
|---|---|---|
| `IsUsingQualityPreset` | `"___0B___"` | `___1B___` = a preset is controlling everything. `___0B___` = custom. Presets can silently re-enable settings you turned off. |
| `ImageQuality` | `2` | overall image preset index |
| `ImageDetail` | `1` | geometry/detail level |
| `ShadowQuality` | `2` | **heaviest CPU + GPU cost in combat** |
| `NiagaraQuality` | `2` | particle effects — **the #1 combat cost** |
| `AntiAliasing` | `1` | AA mode |
| `MotionBlur` | `2` | motion blur level |
| `BloomEnable` | `1` | bloom on/off |
| `VolumeFog` | `1` | volumetric fog |
| `VolumeLight` | `1` | volumetric light |
| `RayTracedShadow` | `0` | keep `0` unless you have headroom to burn |
| `AnisoLevel` | `0` | anisotropic filtering level |
| `LoadingRangeScaleLevel` | `0` | streaming distance |
| `AutoAdjustImageQuality` | `0` | dynamic resolution — leave off for stable frametimes |

> ⚠️ Indices like `2` and `1` are **positions in a list**, not percentages. Changing `ShadowQuality` from `2` to `1` lowers it one step. Don't write `0` or `9` blindly — you may get a value the game doesn't handle.

### DLSS 🟡

| Key | Our value | Notes |
|---|---|---|
| `NvidiaSuperSamplingQuality` | `99` | 🟡 `99` appears to mean **Auto**. Other values unexplored — use the in-game dropdown. |
| `NvidiaSuperSamplingSharpness` | `0.2` | DLSS sharpening, `0.0`–`1.0` |

---

## The `.ini` — what's actually in it

Worth knowing, so you can tell stale values from live ones:

```ini
[/Script/Engine.GameUserSettings]
bUseVSync=True              # ← stale copy, ignore
ResolutionSizeX=1280        # ← stale copy, ignore
FrameRateLimit=60.000000    # ← stale copy, ignore
FullscreenMode=1            # 0=fullscreen 1=borderless 2=windowed

LastUserConfirmedResolutionSizeX=1920   # ← what the game will use at launch
LastConfirmedFullscreenMode=0
PreferredFullscreenMode=1
```

**The `LastUserConfirmed*` values are the interesting ones** — they're what the game intends to use next launch. But even they lose to `LocalStorage.db` when the two disagree.

---

## Other files you might be tempted to touch

| File / folder | What it is | Touch it? |
|---|---|---|
| `Saved\PSO\D3D12\*.ushaderprecache` | Compiled shader cache. Several hundred MB. | ❌ Leave it. Deleting it **causes** the new-area stutter until it rebuilds. |
| `Saved\PSOReport\` | Shader pipeline reports | ❌ Diagnostic output only |
| `Saved\SaveGames\KURO_PLAYER_PREFS.sav` | UE4 SaveGame, binary, per-player prefs | ❌ Not graphics settings |
| `Saved\Config\...\Engine.ini` | Engine plugin paths + `r.RayTracing.LoadConfig=0` | ❌ Leave it alone |
| `Saved\Logs\Client.log` | Encrypted / binary. Not greppable. | ❌ Dead end — don't waste time |

---

## Validation rules for any edit

1. **Back up first** — `Copy-Item $Db "$Db.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"`
2. **Game must be closed** — it holds the DB open
3. **Only change values you understand** — indices are not percentages
4. **Re-read after playing** — if it reverted, the game overrode you
5. **One change at a time** — or you'll never know what worked

---

**Next:** [measurements →](03-measurements.md)
