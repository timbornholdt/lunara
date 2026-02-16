# Diagnostics Baseline Comparison Workflow

## Purpose
Capture and compare diagnostics between the P0 baseline and the P6 performance branch to measure latency improvements.

## Prerequisites
- iPhone 15 Pro running iOS 26.2
- Xcode with both branches available
- A large collection ("Key Albums") with thousands of tracks

## Step 1: Capture P0 Baseline

1. Checkout the P0 baseline commit: `git checkout e15e687`
2. Build and run on device.
3. Perform the test scenario:
   - Force-quit the app.
   - Launch the app and shuffle "Key Albums".
   - Skip forward 5 times.
   - Play a single album from the library.
   - Navigate: Collections -> Collection -> Album -> Back.
4. Go to Settings -> "Share Diagnostics Log".
5. AirDrop or save the file -> rename to `diagnostics-p0.jsonl`.

## Step 2: Capture P6 Measurements

1. Checkout the P6 branch: `git checkout codex/rewrite-p6-performance-polish`
2. Build and run on device.
3. Repeat the exact same test scenario from Step 1.
4. Export the diagnostics log -> rename to `diagnostics-p6.jsonl`.

## Step 3: Compare

```bash
python3 scripts/compare_diagnostics.py diagnostics-p0.jsonl diagnostics-p6.jsonl
```

## Expected Output

The script produces a side-by-side table:

```
Operation            P0 avg ms    P6 avg ms        Delta
------------------------------------------------------------
play_to_audio              850          320         -530
skip_to_audio              180           95          -85
```

## Notes

- P0 baseline does **not** have the explicit `playbackLatency` events from P6.5. The script computes latency from timestamp deltas (`playback.play` -> `playback.audio_started`) for P0 files.
- P6 files use the explicit `durationMs` field from `playback.latency` events.
- The script groups by playback session for accurate per-session measurements.
- Shuffle-specific metrics (`shuffle.started`, `shuffle.phase1_complete`, `shuffle.phase2_complete`) are only present in P6 logs.
