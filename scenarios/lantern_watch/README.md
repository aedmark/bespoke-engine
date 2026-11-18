# Lantern Watch

A ship is coming in through rain. You're on watch at the bell landing. Up in the gallery, something knocks at the glass.

The opening prose is already in the transcript. Choose **Start watch** (Enter also works) to start the clock and focus the command field. Type `look`, `listen`, or `talk to keeper` and press Enter. Both `go to watch room` and `go watch room` work; the narrator confirms arrival. The transcript retains the opening and recent commands, narration, and parser replies. **Show map** reveals the interactive stage, but no route requires it. Reload to start over. Sound is optional and starts at 30% volume when enabled.

## Build and test

From the engine checkout:

```bash
python3 tools/build_lantern_watch.py dist/lantern-watch-story/index.html
```

The tool generates a temporary project with `bespoke init`, tests the script through the command parser, and builds a browser deck using the supported Wasm host API. Both routes run through its WebAssembly keyboard bridge. Add `--chrome` to check the exact standalone HTML over local HTTP, including the command form and optional map. Set `CHROME` to the browser command if needed. The game runs at one simulation tick per second. The export includes its WebAssembly and the engine license; upload just the new HTML file. The tool refuses to overwrite an existing export.

The [first-game tutorial](../../docs/FIRST_GAME.md) remains a separate, smaller example.

## Story checks (spoilers)

- `ring bell` discovers the jam. `examine bell` tells you what is stuck. For the solo route, `go watch room`, `take oilcan`, `go bell landing`, `oil bell`, then `ring bell` with the beacon dark. The knocks continue without repeated narration; use `listen` to check. A hand lamp is safe.
- `go to gallery` and `open shutter` exposes the beacon. On a rainy watch, the next knock is inside. `close shutter` in time prevents entry. The dry-weather test removes only the initial rain fact and proves the beacon alone is not enough.
- `go to watch room`, `read logbook`, and `show logbook to keeper` earn the Keeper's help. Return to the landing and wait until he tells you to take the rope, then `ring bell`. He refuses `ask keeper to open shutter` even after helping.
