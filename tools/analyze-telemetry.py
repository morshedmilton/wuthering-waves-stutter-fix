#!/usr/bin/env python3
"""
Analyse a Wuthering Waves telemetry CSV and name the bottleneck.

Usage
-----
    python analyze-telemetry.py wu-telemetry.csv
    python analyze-telemetry.py wu-telemetry.csv --limit 90

Outputs a verdict (THERMAL / GPU-BOUND / CPU-BOUND / CAPPED / MIXED), a
per-minute table, and a short list of what to change.

Only standard library. Python 3.7+.
"""

import csv
import sys
import statistics as st

DEFAULT_THERMAL_LIMIT = 85.0


# --------------------------------------------------------------------------- #
# input helpers
# --------------------------------------------------------------------------- #
def load(path):
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as fh:
        for raw in csv.DictReader(fh):
            try:
                rows.append({
                    "ts":     raw["ts"],
                    "temp":   float(raw["gpu_temp_c"]),
                    "clk":    float(raw["gpu_clock_mhz"]),
                    "pw":     float(raw["gpu_power_w"]),
                    "util":   float(raw["gpu_util_pct"]),
                    "game":   int(raw.get("game_running", 0) or 0),
                    "tot":    as_float(raw.get("cpu_total_pct")),
                    "core":   as_float(raw.get("cpu_max_core_pct")),
                    "gcpu":   as_float(raw.get("game_cpu_pct")),
                })
            except (KeyError, ValueError, TypeError):
                continue
    return rows


def as_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def pct(values, share):
    ordered = sorted(values)
    if not ordered:
        return 0.0
    idx = int(len(ordered) * share / 100)
    return ordered[min(idx, len(ordered) - 1)]


def share(values, predicate):
    if not values:
        return 0.0
    return 100.0 * sum(1 for v in values if predicate(v)) / len(values)


# --------------------------------------------------------------------------- #
# verdict
# --------------------------------------------------------------------------- #
def classify(stats):
    """Return (verdict, explanation) from the aggregate numbers."""
    core = stats["core"]
    tmax = stats["temp_max"]

    if tmax >= stats["limit"]:
        return "THERMAL", (
            "The GPU held at or above %.0f C. Throttling is real." % stats["limit"]
        )

    if stats["p_hi"] >= 35:
        return "GPU-BOUND", (
            "GPU was at 90%%+ for %.0f%% of the session. The graphics card is the "
            "ceiling." % stats["p_hi"]
        )

    if core is not None and core >= 88 and stats["p_hi"] < 25:
        return "CPU-BOUND", (
            "A single CPU core hit %.0f%% while the GPU sat at %.1f%% average. "
            "The game thread cannot feed the GPU fast enough."
            % (core, stats["util_mean"])
        )

    if stats["p_hi"] < 12 and stats["p_lo"] >= 45:
        return "CAPPED", (
            "GPU never went above 90%% (max %.0f%%) and idled below 70%% for %.0f%% "
            "of the session. Something is limiting the frame rate - most often "
            "VSync or an FPS cap."
            % (stats["util_max"], stats["p_lo"])
        )

    return "MIXED", (
        "No single limiter dominates. Look at the per-minute table: whichever "
        "column moves when the stutter happens is your answer."
    )


def actions(verdict):
    table = {
        "THERMAL": [
            "Clean the fans and vents - dust costs 20-30% of cooling capacity.",
            "Raise the temperature target if your vendor tool allows it.",
            "Undervolt the CPU (same performance, less heat).",
        ],
        "GPU-BOUND": [
            "Lower resolution one step, or move DLSS Quality -> Balanced.",
            "Shadow Quality -1.",
            "Volumetric fog / light -1.",
        ],
        "CPU-BOUND": [
            "Shadow Quality -1 (per-object CPU cost).",
            "Niagara / Particle Quality -1 (the #1 combat cost).",
            "View Distance -1 (fewer simulated actors).",
            "Do NOT lower resolution - the GPU is already waiting.",
        ],
        "CAPPED": [
            "Turn VSync OFF.",
            "Turn Frame Generation OFF so the FPS cap unlocks, then set 120.",
            "Check for a second cap in NVIDIA App -> Max Frame Rate.",
        ],
        "MIXED": [
            "Re-read the game settings - a preset may have re-enabled something.",
            "Run a longer session with more combat for a clearer signal.",
        ],
    }
    return table.get(verdict, table["MIXED"])


# --------------------------------------------------------------------------- #
# report
# --------------------------------------------------------------------------- #
def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    path = argv[1]
    limit = DEFAULT_THERMAL_LIMIT
    if "--limit" in argv:
        try:
            limit = float(argv[argv.index("--limit") + 1])
        except (IndexError, ValueError):
            pass

    rows = load(path)
    game = [r for r in rows if r["game"] == 1]

    print()
    print("Wuthering Waves - telemetry analysis")
    print("=" * 58)
    print("file            : %s" % path)
    print("rows            : %d total, %d during gameplay" % (len(rows), len(game)))

    if not game:
        print()
        print("NO GAMEPLAY CAPTURED.")
        print("The logger only saw idle time. Play with the game running and")
        print("make sure the process is Client-Win64-Shipping.")
        return 1

    print("gameplay window : %s -> %s" % (game[0]["ts"], game[-1]["ts"]))

    util = [r["util"] for r in game]
    temps = [r["temp"] for r in game]
    clocks = [r["clk"] for r in game]
    power = [r["pw"] for r in game]
    cores = [r["core"] for r in game if r["core"] is not None]

    stats = {
        "util_mean": st.mean(util),
        "util_max": max(util),
        "p_hi": share(util, lambda v: v >= 90),
        "p_lo": share(util, lambda v: v < 70),
        "temp_mean": st.mean(temps),
        "temp_max": max(temps),
        "clk_mean": st.mean(clocks),
        "clk_min": min(clocks),
        "pw_mean": st.mean(power),
        "pw_max": max(power),
        "core": max(cores) if cores else None,
        "limit": limit,
    }

    print()
    print("GPU")
    print("  utilisation   mean %5.1f%%   median %5.1f%%   max %5.1f%%"
          % (st.mean(util), pct(util, 50), max(util)))
    print("  >= 90%%        %5.1f%% of samples" % stats["p_hi"])
    print("  <  70%%        %5.1f%% of samples" % stats["p_lo"])
    print("  temperature   mean %5.1f C   max %5.1f C   (your limit %.0f C)"
          % (st.mean(temps), max(temps), limit))
    print("  clock         mean %5.0f MHz min %5.0f MHz" % (st.mean(clocks), min(clocks)))
    print("  power         mean %5.1f W   max %5.1f W" % (st.mean(power), max(power)))

    print()
    print("CPU")
    if cores:
        print("  busiest core  max %5.1f%%" % max(cores))
        tot = [r["tot"] for r in game if r["tot"] is not None]
        if tot:
            print("  total load    mean %5.1f%%" % st.mean(tot))
    else:
        print("  per-core data not present in this CSV (older logger format)")

    verdict, why = classify(stats)
    print()
    print("VERDICT: %s" % verdict)
    print("  %s" % why)

    print()
    print("What to change")
    for line in actions(verdict):
        print("  - %s" % line)

    # ------------------------------------------------------------- timeline
    print()
    print("Per-minute timeline")
    header = "  time    n   util(avg/max)   temp(avg/max)   clock(avg)   power(avg)"
    if cores:
        header += "   core(max)"
    print(header)
    print("  " + "-" * (len(header) - 2))

    buckets = {}
    for r in game:
        buckets.setdefault(r["ts"][:5], []).append(r)

    for minute in sorted(buckets):
        b = buckets[minute]
        if len(b) < 3:
            continue
        bu = [x["util"] for x in b]
        bt = [x["temp"] for x in b]
        bc = [x["clk"] for x in b]
        bp = [x["pw"] for x in b]
        line = ("  %s %3d   %5.1f/%5.1f    %4.1f/%4.1f     %5.0f      %5.1f"
                % (minute, len(b), st.mean(bu), max(bu),
                   st.mean(bt), max(bt), st.mean(bc), st.mean(bp)))
        bc_vals = [x["core"] for x in b if x["core"] is not None]
        if cores and bc_vals:
            line += "      %5.1f" % max(bc_vals)
        print(line)

    print()
    print("Rule of thumb: whichever column spikes when you feel the stutter")
    print("is the bottleneck. Temperature pinned = thermal, one core near 100%")
    print("= CPU, GPU near 100% = GPU, everything low = a cap.")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
