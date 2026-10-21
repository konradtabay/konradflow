# KonradFlow documentation

KonradFlow is a **latency-optimized Wispr Flow alternative** for macOS: same hold-to-talk dictation model, open source, with measurable pipeline tuning.

## What “latency-optimized Wispr Flow” means

Wispr Flow optimizes for a smooth dictation loop: hotkey → listen → paste cleaned text. KonradFlow targets that same loop but makes every stage visible and tunable:

1. **Hold activated → first audio buffer** (`T_start`) — mic pipeline starts on key-down, not at app launch
2. **Release → paste** (`T_paste`) — realtime STT while speaking, parallel context + transcription after release
3. **Cleanup quality** — LLM post-processing with custom vocabulary (not sacrificed for speed)

## Metrics

| Metric | Typical baseline | Realtime OpenAI target |
|--------|------------------|-------------------------|
| T_start | ~13 ms | ~13 ms |
| T_paste (p50) | ~920 ms | ~350–500 ms |
| STT at release | ~430 ms batch | mostly while speaking |

Run live benchmarks:

```bash
./Scripts/latency-benchmark.sh
```

**Paste Light** (local Julia 1 + rule candidates): see [julia-paste-light.md](julia-paste-light.md). After enabling with `./Scripts/apply-paste-light-preset.sh`, traces include `candidatesBuilt`, `juliaDone`, and `pasteLightEnabled` in config.

Traces: `~/Library/Application Support/KonradFlow Dev/latency-traces.jsonl`

## Benchmark archive

| File | Description |
|------|-------------|
| [`benchmarks/baseline-2026-07-14.json`](benchmarks/baseline-2026-07-14.json) | Dev toggles off, live dictation |
| [`benchmarks/openai-pipeline-2026-07-14.json`](benchmarks/openai-pipeline-2026-07-14.json) | Realtime vs batch OpenAI on saved WAVs |
| [`benchmarks/replay-pipeline-2026-07-14.json`](benchmarks/replay-pipeline-2026-07-14.json) | Groq STT model replay |
| [`benchmarks/stt-latency-ab-2026-07-14.json`](benchmarks/stt-latency-ab-2026-07-14.json) | STT A/B timings |

## Scripts

| Script | Purpose |
|--------|---------|
| `Scripts/apply-realtime-openai-preset.sh` | OpenAI realtime + batch fallback |
| `Scripts/apply-fast-preset.sh` | Turbo STT + fast dictation toggles |
| `Scripts/latency-benchmark.sh` | Summarize trace JSONL |
| `Scripts/benchmark-openai-pipeline.py` | Offline realtime vs batch |
| `Scripts/preview-dictation-sounds.sh` | Preview bundled sound options |

## Architecture (high level)

```
Fn hold → AudioRecorder (+ optional RealtimeTranscriptionService WebSocket)
Fn release → stop WAV → parallel( batch STT fallback | context ) → PostProcessingService → paste Cmd+V
         └→ VocabularyLearningMonitor (20s correction watch)
```

Key source files:

- `Sources/AppState.swift` — orchestration, paste, learning hook
- `Sources/AudioRecorder.swift` — capture session lifecycle
- `Sources/RealtimeTranscriptionService.swift` — streaming STT
- `Sources/LatencyTrace.swift` — stage timestamps
- `Sources/VocabularyLearningMonitor.swift` — auto vocabulary from corrections

## Permissions (Dev build)

KonradFlow Dev uses bundle ID `com.konradtabay.konradflow.dev` — separate from any production KonradFlow install in System Settings. After each rebuild with ad-hoc signing, re-grant Accessibility once.

```bash
./Scripts/open-dev-permissions.sh
```
