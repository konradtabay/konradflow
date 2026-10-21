#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRACE_FILE="${KONRADFLOW_TRACE_FILE:-${HOME}/Library/Application Support/KonradFlow Dev/latency-traces.jsonl}"
if [[ ! -f "${TRACE_FILE}" ]]; then
  TRACE_FILE="${HOME}/Library/Application Support/KonradFlow/latency-traces.jsonl"
fi
OUTPUT_DIR="${ROOT_DIR}/docs/benchmarks"
MIN_RUNS="${MIN_RUNS:-10}"

mkdir -p "${OUTPUT_DIR}"

if [[ ! -f "${TRACE_FILE}" ]]; then
  echo "No latency traces found at: ${TRACE_FILE}" >&2
  echo "Run ${MIN_RUNS}+ dictations in KonradFlow Dev, then re-run this script." >&2
  exit 1
fi

python3 - "${TRACE_FILE}" "${OUTPUT_DIR}" "${MIN_RUNS}" <<'PY'
import json
import sys
from datetime import date
from pathlib import Path

trace_file = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
min_runs = int(sys.argv[3])

records = []
for line in trace_file.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        records.append(json.loads(line))
    except json.JSONDecodeError:
        continue

if len(records) < min_runs:
    print(f"Need at least {min_runs} traces, found {len(records)}", file=sys.stderr)
    sys.exit(1)


def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    index = max(0, min(len(values) - 1, int(round(p * (len(values) - 1)))))
    return values[index]


def spans(record):
    ts = record.get("timestamps", {})
    def ms(a, b):
        if a not in ts or b not in ts:
            return None
        return (ts[b] - ts[a]) * 1000

    return {
        "t_start_ms": ms("holdActivated", "firstBuffer"),
        "t_paste_ms": ms("holdDeactivated", "pastePosted"),
        "stt_ms": ms("wavReady", "sttDone"),
        "context_ms": ms("sttDone", "contextReady"),
        "candidates_ms": ms("sttDone", "candidatesBuilt"),
        "julia_ms": ms("candidatesBuilt", "juliaDone"),
        "pp_ms": ms("contextReady", "ppDone"),
    }


metrics = {}
for record in records:
    for key, value in spans(record).items():
        if value is None:
            continue
        metrics.setdefault(key, []).append(value)

summary = {
    "generated_on": date.today().isoformat(),
    "trace_count": len(records),
    "latest_config": records[-1].get("config"),
    "metrics": {},
}

for key, values in metrics.items():
    summary["metrics"][key] = {
        "count": len(values),
        "p50": percentile(values, 0.50),
        "p95": percentile(values, 0.95),
        "p99": percentile(values, 0.99),
    }

output_path = output_dir / f"baseline-{date.today().isoformat()}.json"
output_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))
print(f"Wrote {output_path}")
PY
