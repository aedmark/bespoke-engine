# Publish your first BeSpoke game

Make **Lantern Watch**, a small narrative game about visiting a lighthouse gallery, and publish it as one HTML file. Start in the root of the BeSpoke Engine checkout on Linux. You need Zig 0.17.1, SDL2 development headers, Bash, `patch`, Python 3, and Node.js 22 or later. The automated preview uses Chrome; set `CHROME` to its command or path if it is not named `google-chrome`.

## 1. Generate the game

Run the command blocks in order in the same Bash terminal. The commands use a fresh work directory so they leave your engine checkout and existing games alone.

<!-- tutorial:run -->

```bash
set -euo pipefail
BESPOKE_ENGINE="$PWD"
BESPOKE_TUTORIAL_DIR="${BESPOKE_TUTORIAL_DIR:-$(mktemp -d)}"
BESPOKE_UPLOAD_DIR="${BESPOKE_UPLOAD_DIR:-$BESPOKE_TUTORIAL_DIR/upload}"
zig build -j2
cd "$BESPOKE_TUTORIAL_DIR"
"$BESPOKE_ENGINE/zig-out/bin/bespoke" init lantern_watch --engine "$BESPOKE_ENGINE"
cd lantern_watch
```

`scripts/main.bespoke` is the game. The Hero follows the `Explore` routine to the gallery. Arriving there records the `Investigated` fact, which gives the Keeper a reason to intercept the Hero and offer a dialogue.

## 2. Write and check a line of the story

Add a line of speech just before the game records the visit. The patch applies the same edit you could make in a text editor.

<!-- tutorial:run -->

```bash
patch -p0 <<'PATCH'
--- scripts/main.bespoke
+++ scripts/main.bespoke
@@ -33,6 +33,7 @@
   walk Hero to Stair
   wait 4 ticks
   walk Hero to Gallery
+  say Hero: "The lantern still burns."
   remember Investigated(Hero, Gallery)
   wait 20 ticks
   remember LampLit(Lamp) for 30 ticks
PATCH
"$BESPOKE_ENGINE/zig-out/bin/bespoke" check scripts/main.bespoke
zig build test -j2
zig build run -j2 -- --headless --ticks 50 </dev/null | tee "$BESPOKE_TUTORIAL_DIR/story.log"
grep -F 'The lantern still burns.' "$BESPOKE_TUTORIAL_DIR/story.log"
```

`bespoke check` reports where a script error occurred. The starter tests check that the Keeper intercepts the Hero and the lit lamp changes the score. The last command confirms your new line actually plays.

## 3. Set the pace and score

At one tick per second, the Hero reaches the gallery in about ten seconds. Give the Tide and Storm scores sixteen bars each so the music has room to develop along with the scene. The soundtrack uses its own tempo in beats per minute; slowing the simulation does not slow the notes.

<!-- tutorial:run -->

```bash
patch -p0 <<'PATCH'
--- scripts/main.bespoke
+++ scripts/main.bespoke
@@ -14,5 +14,5 @@
 score Tide:
-  lead "t88 o5 l8 @1 e g a g e4 d4 L c4 e4 g2 e4 d4 c2"
-  bass "o3 l4 @0 c g a e L f c g c"
-  chords "o4 l2 v8 @7 e d L f e"
+  lead "t88 o5 l4 v9 @1 L e g a g e2 d c d f a f g2 e2 a g e d f2 a2 g e d c d2 r2 c e g e f a g f e2 g2 a2 g e f e d c d f e d c2 g2 c2 r2"
+  bass "o3 v7 @0 L c2 g2 a2 e2 d2 a2 g2 d2 f2 c2 d2 a2 g2 d2 g2 g2 c2 g2 f2 c2 a2 e2 a2 e2 f2 c2 g2 d2 c2 g2 c1"
+  chords "o4 v5 @7 L e1 e1 f1 b1 a1 f1 b1 d1 e1 f1 c1 e1 a1 b1 e1 r1"
   scene Lighthouse
@@ -20 +20,3 @@
-score Storm: "t150 o5 l16 @5 L [c d e d]2 [e f g f]2"
+score Storm:
+  lead "t108 o5 l4 v9 @5 L d f a g a2 f e d e f a g2 e2 f a b a g f e d e g f e d2 r2 a a g f e2 a2 g f e d f2 a2 b a g f e g a e d2 a2 d2 r2"
+  bass "o3 l4 v8 @0 L d a d a f c f c d a d a e b e b f c f c g d g d e b e b d2 a2 d a d a a e a e g d g d f c f c g d g d a e a e d a d a d1"
--- web/index.html
+++ web/index.html
@@ -18,5 +18,5 @@
 // Loads lantern_watch.wasm (the engine's browser runtime with the game's compiled script) and drives it:
-// 20 ticks a second, pointer and key events in, the RGBA framebuffer out. Serve this folder
+// One tick a second, pointer and key events in, the RGBA framebuffer out. Serve this folder
 // over HTTP; browsers refuse to fetch a module from a file:// page.
-const TICK_MS = 50;
+const TICK_MS = 1000;
 const canvas = document.getElementById('stage');
PATCH
zig build test -j2
```

## 4. Prepare and preview the upload

`zig build web` produces a browser page and a WebAssembly module. Neocities [omits .wasm from its free upload list](https://neocities.org/site_files/allowed_types), so pack the module into the page. The browser check serves only that HTML file at a subdirectory URL and verifies that Chrome renders the game.

<!-- tutorial:run -->

```bash
zig build web -j2
node web/smoke.js
python3 "$BESPOKE_ENGINE/tools/pack_game_page.py" zig-out/web "$BESPOKE_UPLOAD_DIR/index.html"
node "$BESPOKE_ENGINE/tools/browser_smoke.js" --starter "$BESPOKE_UPLOAD_DIR/index.html"
```

## 5. Upload to Neocities

In the Neocities dashboard, create a folder such as `lantern-watch` and upload the generated `index.html` into that folder. The pack command prints its full path. Keep it in its own folder so it does not replace your site's home page. The file includes both the module and the engine's license notice.

Visit `https://YOUR-SITE.neocities.org/lantern-watch/`. Click **Sound: off** to hear the Tide score. Give the Hero about ten seconds to reach the gallery, then use the number keys when the Keeper offers a choice.

CI runs the command blocks above through the browser preview. The upload and live-site check are manual; the build needs no hosting credentials.

Continue with the [authoring guide](AUTHORING.md) for scenes, dialogue, and puzzles.
