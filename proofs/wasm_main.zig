//! Root of `bespoke-proofs.wasm` (`zig build wasm-proofs`, P32-04, D-042): the engine's
//! browser runtime with the proofs' six decks, under the same `wasm_*` exports as the
//! engine's own module.
const bespoke = @import("bespoke");
const deck = @import("wasm_deck.zig");

comptime {
    bespoke.wasm.export_runtime(&deck.decks);
}
