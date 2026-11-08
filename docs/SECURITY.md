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
| Bytecode Packages (.bspk) | Malicious or corrupted compiled package inducing out-of-bounds memory access or denial of service | Magic header check (`BSPB`), schema version check (`1`), strict element count limits, and payload CRC32 checksum before allocation | Asset Loader (`src/package.zig`) |
| Save State Snapshots (`.sav`) | Corrupted or crafted save files inducing memory corruption or buffer overflows | Magic header verification (`BSAV`), schema version check, payload CRC32 checksum, and automatic `.sav.bak` fallback before arena restoration | World Store (`src/world.zig`) & Save Manager (`src/save.zig`) |
| WebAssembly Linear Memory | Out-of-bounds canvas coordinate writes or heap exhaustion in browser runtime | Fixed-size `2 MiB` `FixedBufferAllocator` (`global_wasm_heap`) and clamped `640x360` pixel coordinates in `WasmCanvas.set_pixel` | WebAssembly Runtime (`src/wasm.zig`) |
| Entity Registry Limits | Denial of service / out of memory via unbounded entity or fact generation | Hard upper bounds on total facts per arena; deterministic allocation limits | World Store (`src/world.zig`) |
