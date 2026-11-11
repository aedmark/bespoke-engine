# Security

This document describes the BeSpoke Engine's security assumptions, trust boundaries, and vulnerability reporting.

## Supported Versions

| Version / branch | Security fixes |
| --- | --- |
| `main` | Active development |

## Report a Vulnerability

Report suspected vulnerabilities privately to the repository maintainer. Include affected versions, impact, reproduction scripts, and any known workarounds. Do not include credentials or personal data.

## Assets and Boundaries

| Asset or boundary | Sensitivity / threat | Protection and validation | Owner |
| --- | --- | --- | --- |
| Bytecode Execution | Malicious script triggering arbitrary host code execution or out-of-bounds memory access | VM bounds checks every instruction pointer, stack access, and entity register; no raw host pointer manipulation exposed in bytecode | VM Runtime (`src/vm.zig`) |
| Bytecode Packages (.bspk) | Malicious or corrupted compiled package inducing out-of-bounds memory access or denial of service | Magic header check (`BSPB`), schema version check (`1` or `2`), draft note and entity id range checks, strict element count limits, and payload CRC32 checksum before allocation | Asset Loader (`src/package.zig`) |
| Save State Snapshots (`.sav`) | Corrupted or crafted save files inducing memory corruption or buffer overflows | Magic header verification (`BSAV`), schema version check, payload CRC32 checksum, length-bounded temporal section, reference validation, and automatic `.sav.bak` fallback before arena restoration (D-048) | World Store (`src/world.zig`) & Save Manager (`src/save.zig`) |
| WebAssembly Linear Memory | Out-of-bounds canvas coordinate writes or heap exhaustion in browser runtime | Fixed-size `2 MiB` `FixedBufferAllocator` (`global_wasm_heap`) and clamped `640x360` pixel coordinates in `WasmCanvas.set_pixel` | WebAssembly Runtime (`src/wasm.zig`) |
| MML Score Text | Script-supplied score strings inducing unbounded expansion or memory use | `mml.parse` caps events at 4,096, repeat depth at 4, repeat counts at 99, and characters re-read through repeats at 262,144; every numeric range is checked and rejected with a column (P28-01, D-060). Playback clamps tempo, volume, and envelope again and restarts a loop at most once per tick, so a hand-built score cannot stall the audio thread (P28-02, D-061) | MML Parser (`src/mml.zig`), Synth (`src/audio.zig`) |
| Entity Registry Limits | Denial of service / out of memory via unbounded entity or fact generation | Hard upper bounds on total facts per arena; deterministic allocation limits | World Store (`src/world.zig`) |
| Repository content and retrieved docs | Embedded instructions, prompt injection, invisible characters | Instruction scan; the checker rejects zero-width and bidirectional controls; never execute embedded directives | every agent |

Architecture details belong in [ARCHITECTURE.md](ARCHITECTURE.md); this table records the security consequence.

## Secure Development Rules

- Keep credentials out of code, documentation, prompts, logs, screenshots, fixtures, and error reports.
- Validate at trust boundaries and encode for the destination context. Do not rely on prompt text as a security control.
- Use least privilege, explicit timeouts and size limits, and safe failure defaults.
- Pin and review dependencies according to engine conventions; record accepted exceptions.
- Sanitize production-derived examples and preserve only the minimum data needed for debugging.
- For authentication, authorization, cryptography, or destructive migrations, require targeted review and a rollback or recovery plan.

## Security Verification

The repository enforces security boundaries via multiple automated layers:
- `python3 tools/check_docs.py` scans all repository Markdown and HTML documents for invisible characters, zero-width spaces, and bidirectional Unicode control characters.
- Unit and property tests verify binary bounds checking for `.bspk` package files (`src/package.zig`), `.sav` save slot containers (`src/save.zig`), and WebAssembly framebuffer coordinate clipping (`src/wasm.zig`).
- Pure Zig standalone runtime operates with zero C heap allocation for core simulation, mitigating pointer swizzling and buffer overflow attack vectors.

## Incident Response

If active exploitation or secret exposure is suspected: contain access, preserve evidence without copying sensitive data into the repository, notify the repository maintainer, rotate affected credentials, and follow the documented recovery procedure.
