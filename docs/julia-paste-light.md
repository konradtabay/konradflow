# Julia Paste Light

Paste Light builds up to 20 cleanup sentences locally while you hold Fn, then asks **Julia 1** once at release to pick one. If confidence is below the frozen threshold, KonradFlow falls back to Groq `gpt-oss-20b` (one paste either way).

## Requirements

- Python 3.11+ (3.13 recommended on Apple Silicon)
- Julia 1 runtime from [SupersonicLabs/Julia-1](https://huggingface.co/SupersonicLabs/Julia-1)

Homebrew Python is PEP 668–managed, so use a dedicated venv:

```bash
python3.13 -m venv "$HOME/Julia-1-venv"
"$HOME/Julia-1-venv/bin/pip" install huggingface_hub
"$HOME/Julia-1-venv/bin/python" -c "from huggingface_hub import snapshot_download; snapshot_download('SupersonicLabs/Julia-1', local_dir=\"$HOME/Julia-1\")"
"$HOME/Julia-1-venv/bin/pip" install -e "$HOME/Julia-1"
```

KonradFlow auto-uses `~/Julia-1-venv/bin/python` when present. Override with `JULIA_PYTHON` or set `JULIA_MODEL_PATH` if the weights are not in `~/Julia-1`.

## Helper

The app starts `Scripts/julia_cleanup_helper.py` at launch (non-blocking). Manual test:

```bash
export JULIA_MODEL_PATH="$HOME/Julia-1"
python3 Scripts/julia_cleanup_helper.py
```

## Settings (UserDefaults)

- `paste_light_enabled` — default **false** until threshold is fit
- `julia_confidence_threshold` — default **1.0** (always Groq until lowered by fit script)

Frozen threshold file: `~/Library/Application Support/KonradFlow/paste-light-threshold.json`

## Quality gate

```bash
Scripts/export-production-history.sh
Scripts/fit-julia-paste-light-threshold.py docs/benchmarks/production-pipeline-history-YYYY-MM-DD.json
```

## Latency benchmark

With realtime streaming and Paste Light enabled:

```bash
Scripts/apply-paste-light-preset.sh
Scripts/latency-benchmark.sh
```

Compare `juliaDone`, `pp_ms`, and `t_paste_ms` in exported traces.
