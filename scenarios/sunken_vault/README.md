# The Sunken Vault

A classic turn-based parser adventure built on BeSpoke 1.x (`bespoke init --template text`) with six colour-cycled 320x180 PNG rooms, timed turn events, and multi-tier hints.

## Build and test

From the engine checkout:

```bash
python3 tools/build_sunken_vault.py --chrome /tmp/sunken-vault.html
```

The builder generates a temporary project via `bespoke init sunken_vault --template text`, runs `bespoke check`, `zig build test web`, `scenarios/sunken_vault/check_wasm.js`, `tools/pack_game_page.py`, and (with `--chrome`) `scenarios/sunken_vault/check_chrome.js` against the packed standalone HTML.

## Story checks (spoilers)

- `east`, `take flint`, `take torch`, `take key`, `read ledger`: equips light, the crypt key, and the sluice warning.
- `west`, `down`, `east`, `turn wheel`, `west`: drains the culvert before breaking the reliquary seal.
- `light torch` (18-turn TTL), `north`, `unlock gate with key`, `north`, `take crown` (triggers the 9-turn tide surge), `south`, `south`, `up`: escapes to the courtyard with the Crown of Tides.
