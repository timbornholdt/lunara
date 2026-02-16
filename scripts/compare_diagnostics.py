#!/usr/bin/env python3
"""Compare Lunara diagnostics JSONL files between P0 baseline and P6."""

import json
import sys
from collections import defaultdict
from statistics import mean


def parse_jsonl(path):
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def group_by_session(events):
    sessions = defaultdict(list)
    for event in events:
        sid = event.get("playbackSessionId") or event.get("sessionId") or "unknown"
        sessions[sid].append(event)
    return sessions


def compute_latencies_p6(events):
    """Extract latency from explicit playbackLatency events (P6 format)."""
    latencies = defaultdict(list)
    for event in events:
        if event.get("event") == "playback.latency":
            data = event.get("data", {})
            operation = data.get("operation", "unknown")
            duration = data.get("durationMs")
            if duration is not None:
                latencies[operation].append(int(duration))
    return latencies


def compute_latencies_p0(events):
    """Compute latency from timestamp deltas between events (P0 format)."""
    latencies = defaultdict(list)
    pending_play = None
    pending_skip = None

    for event in events:
        name = event.get("event", "")
        ts = event.get("timestamp")
        if ts is None:
            continue
        try:
            ts_val = float(ts)
        except (ValueError, TypeError):
            continue

        if name == "playback.play":
            pending_play = ts_val
        elif name == "playback.skip_next" or name == "playback.skip_previous":
            pending_skip = ts_val
        elif name == "playback.audio_started":
            if pending_skip is not None:
                latencies["skip_to_audio"].append(int((ts_val - pending_skip) * 1000))
                pending_skip = None
            elif pending_play is not None:
                latencies["play_to_audio"].append(int((ts_val - pending_play) * 1000))
                pending_play = None

    return latencies


def has_latency_events(events):
    return any(e.get("event") == "playback.latency" for e in events)


def compute_latencies(events):
    if has_latency_events(events):
        return compute_latencies_p6(events)
    return compute_latencies_p0(events)


def format_table(p0_latencies, p6_latencies):
    operations = sorted(set(list(p0_latencies.keys()) + list(p6_latencies.keys())))
    if not operations:
        print("No latency data found in either file.")
        return

    header = f"{'Operation':<20} {'P0 avg ms':>12} {'P6 avg ms':>12} {'Delta':>12}"
    print(header)
    print("-" * len(header))

    for op in operations:
        p0_vals = p0_latencies.get(op, [])
        p6_vals = p6_latencies.get(op, [])
        p0_avg = mean(p0_vals) if p0_vals else None
        p6_avg = mean(p6_vals) if p6_vals else None

        p0_str = f"{p0_avg:.0f}" if p0_avg is not None else "N/A"
        p6_str = f"{p6_avg:.0f}" if p6_avg is not None else "N/A"

        if p0_avg is not None and p6_avg is not None:
            delta = p6_avg - p0_avg
            delta_str = f"{delta:+.0f}"
        else:
            delta_str = "N/A"

        print(f"{op:<20} {p0_str:>12} {p6_str:>12} {delta_str:>12}")

    print()
    for op in operations:
        p0_vals = p0_latencies.get(op, [])
        p6_vals = p6_latencies.get(op, [])
        print(f"{op}: P0 samples={len(p0_vals)}, P6 samples={len(p6_vals)}")


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <p0.jsonl> <p6.jsonl>")
        sys.exit(1)

    p0_events = parse_jsonl(sys.argv[1])
    p6_events = parse_jsonl(sys.argv[2])

    print(f"P0: {len(p0_events)} events")
    print(f"P6: {len(p6_events)} events")
    print()

    p0_latencies = compute_latencies(p0_events)
    p6_latencies = compute_latencies(p6_events)

    format_table(p0_latencies, p6_latencies)


if __name__ == "__main__":
    main()
