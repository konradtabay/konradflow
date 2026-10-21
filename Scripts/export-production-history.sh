#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${KONRADFLOW_DB:-${HOME}/Library/Application Support/KonradFlow/PipelineHistory.sqlite}"
AUDIO_DIR="${HOME}/Library/Application Support/KonradFlow/audio"
OUTPUT_DIR="${ROOT_DIR}/docs/benchmarks"
OUTPUT_FILE="${OUTPUT_DIR}/production-pipeline-history-$(date +%Y-%m-%d).json"

if [[ ! -f "${DB_PATH}" ]]; then
  echo "Pipeline history database not found: ${DB_PATH}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

python3 - "${DB_PATH}" "${AUDIO_DIR}" "${OUTPUT_FILE}" <<'PY'
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

db_path, audio_dir, output_file = sys.argv[1:4]
audio_path = Path(audio_dir)

conn = sqlite3.connect(db_path)
conn.row_factory = sqlite3.Row
rows = conn.execute(
    """
    SELECT
        hex(ZID) AS id_hex,
        ZTIMESTAMP AS ts,
        ZRAWTRANSCRIPT AS raw_transcript,
        ZPOSTPROCESSEDTRANSCRIPT AS post_processed_transcript,
        ZPOSTPROCESSINGSTATUS AS post_processing_status,
        ZDEBUGSTATUS AS debug_status,
        ZAUDIOFILENAME AS audio_file_name,
        ZCONTEXTAPPNAME AS context_app_name,
        ZCONTEXTWINDOWTITLE AS context_window_title,
        length(ZRAWTRANSCRIPT) AS raw_len,
        length(ZPOSTPROCESSEDTRANSCRIPT) AS post_processed_len
    FROM ZPIPELINEHISTORYENTRY
    ORDER BY ZTIMESTAMP ASC
    """
).fetchall()
conn.close()

core_reference = 978307200  # Cocoa epoch offset

def cocoa_to_iso(ts):
    if ts is None:
        return None
    return datetime.fromtimestamp(float(ts) + core_reference, tz=timezone.utc).astimezone().isoformat()

entries = []
prev_ts = None
gaps_ms = []
for row in rows:
    ts = row["ts"]
    gap_ms = None
    if prev_ts is not None and ts is not None:
        gap_ms = (float(ts) - float(prev_ts)) * 1000
        gaps_ms.append(gap_ms)
    audio_name = row["audio_file_name"]
    audio_exists = bool(audio_name and (audio_path / audio_name).exists())
    entries.append(
        {
            "id": row["id_hex"],
            "timestamp": cocoa_to_iso(ts),
            "raw_transcript": row["raw_transcript"] or "",
            "post_processed_transcript": row["post_processed_transcript"] or "",
            "post_processing_status": row["post_processing_status"] or "",
            "debug_status": row["debug_status"] or "",
            "audio_file_name": audio_name,
            "audio_file_exists": audio_exists,
            "context_app_name": row["context_app_name"],
            "context_window_title": row["context_window_title"],
            "raw_len": row["raw_len"] or 0,
            "post_processed_len": row["post_processed_len"] or 0,
            "gap_since_previous_ms": gap_ms,
        }
    )
    prev_ts = ts


def percentile(values, p):
    if not values:
        return None
    values = sorted(values)
    idx = max(0, min(len(values) - 1, int(round(p * (len(values) - 1)))))
    return values[idx]

summary = {
    "source": str(db_path),
    "exported_at": datetime.now().astimezone().isoformat(),
    "entry_count": len(entries),
    "audio_files_present": sum(1 for e in entries if e["audio_file_exists"]),
    "note": (
        "Production KonradFlow stores pipeline run logs, not per-stage latency traces. "
        "gap_since_previous_ms is only time between saved runs, not T_start or T_paste."
    ),
    "gap_since_previous_ms": {
        "count": len(gaps_ms),
        "p50": percentile(gaps_ms, 0.50),
        "p95": percentile(gaps_ms, 0.95),
    },
    "entries": entries,
}

Path(output_file).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: summary[k] for k in summary if k != "entries"}, indent=2))
print(f"Wrote {output_file}")
PY
