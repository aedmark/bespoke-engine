# Simulation benchmarks and browser budgets

## Measure the headless simulation

From the engine checkout on Linux, run:

```bash
zig build bench
```

This needs Zig, Node.js, and Chrome or Chromium. The runner looks for `google-chrome`, `google-chrome-stable`, or `chromium`; set `CHROME=/path/to/chrome` to override it. It runs the same workload as a native executable and as freestanding Wasm in real headless Chrome. Both builds use ReleaseFast. The disposable GitHub runner uses the same sandbox setting as the existing browser smoke check; local runs leave Chrome's sandbox enabled.

Each row reports actual live facts, registered entities, scheduled fibers, and native and Chrome ticks per second. After 16 warm-up ticks, the harness measures three samples of 256 ticks and reports the median rate. The cases vary fact count, entity count, and fiber count separately, then combine the heavy settings.

Each fiber performs a late matching fact query, a miss, and a refresh of the same expiring heartbeat fact. The ballast facts and entity registry stay fixed during measurement. Both hosts verify the final tick, counts, fiber state, and heartbeat. Only engine ticks are timed; fixture setup, script compilation, browser startup, rendering, and audio do not enter the sample.

The workload makes linear scans visible. It does not represent a full game or prove that normal play is fast enough on every device. Linux and Chrome rates are informational, not CI timing gates. P41-02 uses a larger reference game to revisit Q-002.

### First baseline

2026-11-17, Linux x86_64, Ryzen 9 7900X, Zig 0.17.1, Chrome 157.0.8103.78, `zig build bench --summary all -j2`. Times are local observations, not targets.

| Case | Facts | Entities | Fibers | Linux ticks/s | Chrome ticks/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 1,026 | 262 | 16 | 93,707 | 48,302 |
| Fact-heavy | 7,170 | 262 | 16 | 14,952 | 8,232 |
| Entity-heavy | 1,026 | 2,054 | 16 | 96,363 | 54,468 |
| Fiber-heavy | 1,026 | 262 | 256 | 6,036 | 3,526 |
| Combined | 7,170 | 2,054 | 256 | 967 | 523 |

### Reference game

`zig build harbour` verifies the native save and golden, plays ten scenes via the text form in Chrome, and then times the same completed route with the six-member society still active. Each rate is the median of three 8,192-tick samples after a 16-tick warm-up. Setup, rendering, and browser input processing do not enter the sample. The ballast case adds 4,096 unrelated archive facts to the actual game state.

2026-11-17, same machine and toolchain:

| Harbour workload | Initial facts | Linux ticks/s | Chrome ticks/s |
| --- | ---: | ---: | ---: |
| Story state | 33 | 1,614,373 | 655,360 |
| Story state + archive ballast | 4,129 | 44,220 | 25,144 |

The numbers support keeping linear fact scans for 1.0 (D-117). They do not measure a graphical frame or every gameplay path.

## Enforce browser artifact budgets

```bash
zig build wasm wasm-proofs
python3 tools/build_site.py --check
python3 tools/check_web_budgets.py
```

Use `--lantern-page /path/to/index.html` to include a freshly packed Lantern Watch export (`site/sunken-vault.html`, `site/harbour.html`, and the nineteen standalone proof pages are always checked). CI also includes Lantern Watch.

| Artifact | Limit per file |
| --- | ---: |
| Engine and proof WebAssembly modules | 1.5 MiB (D-159) |
| Showcase `site/index.html` | 1.25 MiB |
| Individual proof pages, Harbour, Sunken Vault, and Lantern Watch | 2 MiB (D-157) |

Limits are raw file bytes, before HTTP compression. Standalone HTML counts its embedded module; that makes it possible to detect growth in both the module and the export wrapper. A page embeds the module as base64, so the page budget of 2 MiB carries a module of up to 1.5 MiB, the module limit (D-141, D-157, D-159). Missing files and files over budget fail the check. [The budget manifest](../tools/web_budgets.json) is the single source of limits (D-115).
