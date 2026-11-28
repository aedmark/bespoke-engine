# Studio Hand-Test Pass

A hand test of BeSpoke Studio (`site/studio.html`, Phase 47) in real browsers, by mouse and by touch. The automated checks (`tools/studio_smoke.js`, see [TESTING.md](../TESTING.md)) drive every window through test hooks in headless Chrome; this pass covers what they cannot: dragging and painting by hand, the browser's folder and file pickers, its write prompt, downloads, and how the Studio feels to use.

Work through the sections in order. Each step says what to do and what you should see. Tick the box, or write the failure in the results table at the end. A failure does not stop the pass: note it and move on, unless it blocks the steps after it.

Time: about two hours for everything, or forty minutes for sections 1 to 6 and 11.

## 0. Before you start

- **Reload the page.** A browser tab keeps the page it first loaded. After pulling or rebuilding, press Ctrl+Shift+R (Cmd+Shift+R on a Mac) on the Studio tab, or a fixed bug will still show. The About window names the version; the build is current if `python3 tools/build_studio.py --check` says so.
- **Browsers.** A Chromium-based browser (Chrome, Chromium, or Edge) for the full pass: it can open a folder and write back to it. Firefox for section 10's second half: it has no folder access, so the Studio opens files and saves edits as downloads. A phone or tablet, if you have one, for the touch steps.
- **Work on copies, under git.** Every step that saves is judged by what changed on disk, so make two scratch projects and commit them first:

```bash
mkdir -p ~/studio-trial
cp -r scenarios/sunken_vault ~/studio-trial/vault
mkdir -p ~/studio-trial/yard
cd ~/studio-trial && git init -q && git add -A && git commit -qm base
```

  Then write `~/studio-trial/yard/main.bespoke` with this script and commit it too (`git add -A && git commit -qm yard`):

```bespoke
scene Yard:
  cast: Hero, Guide
  props: Bucket
  marks: Gate, Well

scene Hall:
  marks: Door, Hearth

relation Paid(who)

dialogue AskGuide:
  speaker Guide
  say "Well, traveller?"
  choice "Pay the toll." if not Paid(Hero):
    remember Paid(Hero)
    say "Thank you kindly."
  choice "Goodbye.":
    say "Come back soon."

routine Greet(Hero):
  wait 1 ticks
  talk AskGuide
```

  After every Save, run `git -C ~/studio-trial status --short` and `git -C ~/studio-trial diff`: only the lines the step names should change. `git -C ~/studio-trial checkout -- .` puts a project back.
- **Open the Studio.** Either open `site/studio.html` from the repository directly, or serve the folder and open `http://localhost:8765/studio.html`:

```bash
python3 -m http.server 8765 -d site
```

## 1. Automated baseline

Run these first, so that a hand-test failure cannot be a build that was already broken:

```bash
zig build studio
python3 tools/build_studio.py --check
CHROME=/usr/bin/google-chrome-stable node tools/studio_smoke.js
```

- [ ] `build_studio.py --check` says `site/studio.html is current`.
- [ ] The smoke check prints `ok` for every step and no `FAIL`.

## 2. The workspace

1. Load the page with no project.
2. Drag a window by its title bar; use its close, zoom, and depth gadgets.
3. Hold the right mouse button anywhere on the screen: the menu bar opens. Move to an item and release to pick it.
4. Try the command keys: Ctrl+O (open folder), Ctrl+K (check), Ctrl+G (play), Ctrl+E (export), Ctrl+S (save). Esc closes a requester.
5. Settings menu: switch the scale between 1x, 2x, and 3x, then reload.
6. On a phone or tablet, or at a narrow window: open a menu, move a window, press a button.

- [ ] The About window shows all its text without cutting off the last line.
- [ ] Windows move, close, zoom, and change depth; nothing leaves the screen for good.
- [ ] The held right-button menu picks items; each command key does what its item does.
- [ ] The chosen scale survives a reload.
- [ ] Touch: every control can be hit with a finger; menus and window drags work.

## 3. A new project and script text

1. New project from the Project menu, choose Text, and in the folder picker make a new folder `~/studio-trial/fresh`. Then do it again with a folder that already holds a file.
2. Play the new game for a few turns.
3. In the Project window, click `scripts/main.bespoke` in the list and press Edit (its button names the script), and change a `say` line's words. Apply. Then break a line (delete a colon) and Apply.
4. New script, name it `rooms`. In it, write `relation Rested(who)` and Apply. Save.

- [ ] The new folder holds only `scripts/main.bespoke`, written at once, and the project checks valid and plays.
- [ ] A folder that is not empty is refused, and nothing is written into it.
- [ ] The text area takes typing, selection, copy and paste, and Ctrl+Z; the window can be resized.
- [ ] A broken edit is not kept: the window names the line, puts the caret there, and keeps your text.
- [ ] After Save, `git -C ~/studio-trial diff` (after `git add -N fresh`) shows the changed `say` line, an `include "rooms.bespoke"` line, and the new file, and nothing else.

### 3b. Examples

1. Project > Open example. Open The Sunken Vault, then The Donkey of Lamp Point.
2. In the Donkey, open Art and paint on a backdrop; Play.
3. Save, and make a new empty folder for it in the picker.

- [ ] Every demo is listed; one whose showcase version runs Zig code says so when it opens.
- [ ] A proof with code-drawn art opens with its backdrops as PNGs, and Play shows them.
- [ ] Save writes the whole example into the new folder, and the Project window then names that folder.

## 4. Opening and saving

1. Open folder (Ctrl+O), choose `~/studio-trial/vault`. Accept the browser's permission prompt when it asks.
2. Without changing anything, Save (Ctrl+S).
3. In a text editor, add a blank line at the end of `vault/main.bespoke` and save it there. Back in the Studio, make any edit (section 7 has one) and Save.

- [ ] The Project window lists the scripts; the main script is marked `>`, and Check reports it valid.
- [ ] Clicking another script picks it: Edit opens it as text, and Make main makes it the main script (Check and Play use it).
- [ ] Save with no edits writes nothing: `git status` is clean.
- [ ] Save after another program changed a file writes nothing and says which file changed. Undo the outside edit with `git checkout -- .` and reopen the folder.

## 5. Check and the diagnostics

1. In a text editor, break `yard/main.bespoke` (delete the colon after `scene Yard`). Open the `yard` folder in the Studio.
2. Press Check (Ctrl+K), then Show line in the requester.
3. Fix the file in the text editor and reopen the folder.

- [ ] A broken project opens to a working Studio with the error's file, line, and column, and the Diagnostics window shows it.
- [ ] Show line opens the script at that line.
- [ ] Play on the broken project shows the same error and starts nothing.

## 6. Play

On the `vault` project:

1. Play (Ctrl+G). Click into the Play window's command bar and type `look`, then `east` (into the guardhouse), then `take torch`, then `xyzzy`.
2. Press Pause, Step, Rewind, Hint, Verb, and State. Turn Sound on, listen, and turn it off.
3. Open Facts. Pick a fact the script wrote (`At` or `Carries`) and press Show line.
4. Close the Play window, then Play again.

- [ ] The game draws its art and the window's title names the script.
- [ ] Each typed command advances one turn; a mistyped one does not.
- [ ] Every gadget does what its name says; Sound plays and stops.
- [ ] Facts lists the live facts; Show line opens the line that wrote one (or lists the candidates).
- [ ] Play after a close starts a fresh game.

## 7. Paint

On the `vault` project:

1. Art, then pick an image. Paint with Pencil in a palette colour; erase with Eraser; Fill an area; Pick a colour off the sheet.
2. Undo and Redo a few times; zoom in and out; step through the frames if the image has them.
3. New image: a small sheet with two frames. Import PNG: one PNG drawn in the game's palette, and one in other colours.
4. Play before saving, then Save.

- [ ] Strokes land where the pointer is, at every zoom; a drag paints a continuous line.
- [ ] Undo back to the start leaves the file unchanged (`git diff` empty for it).
- [ ] The off-palette import is refused with the pixel that is wrong; nothing is added.
- [ ] Play shows the painted pixels before Save.
- [ ] After Save, `git diff` shows only the painted PNG, the two new PNGs, and two new `image` lines after the script's last image.
- [ ] `zig-out/bin/bespoke check ~/studio-trial/vault/main.bespoke` passes.

## 8. Rooms and grids

On the `yard` project:

1. Rooms, then the Yard. With Move, drag Gate and Well to new places on the backdrop.
2. With Walkway, join Gate to Well. With Exit, make Well lead to the Hall at Door. With Area, drag out a clickable area for the Bucket.
3. With Grid, open the settings form, set a size, paint a few cells, and place a mark on a cell.
4. Undo everything once, then redo it. Save.

- [ ] Drags follow the pointer and snap to the same places each time.
- [ ] Undo to the start gives back the script's exact bytes.
- [ ] After Save, `git diff` changes only the Yard's `room` and grid blocks.
- [ ] `zig-out/bin/bespoke check ~/studio-trial/yard/main.bespoke` passes on the saved script. In Play, clicking Well walks the Hero there and on into the Hall.

## 9. Cast, values, and dilemmas

On the `yard` project:

1. Cast: Add cast, Add prop, and Add mark; Set name on the Guide (a display name with a space); declare a value axis; Set values for the Hero.
2. Dilemmas: New dilemma from the template, fill in its lines, Preview two pairs of values, Apply. In Cast, tick a red line.
3. Save.

- [ ] Each change is one checked line; a bad value is refused with the reason, and nothing is written.
- [ ] The preview's tier matches what the game does when it plays the dilemma.
- [ ] After Save, `git diff` shows only those lines and the new dilemma block.

## 10. Dialogue

On the `yard` project:

1. Dialogue. Click a box and a choice on the map: the script opens at each line.
2. Edit AskGuide: change a `say` line and watch the map redraw; indent and outdent a line with `>` and `<`; Add line; Remove a line; Apply.
3. New dialogue: rename it, write a speaker, a say, and a choice with a line under it, then Apply.
4. Open the `vault` project (it has no dialogue at all) and press New dialogue there too, then Apply one.
5. Save.

- [ ] The map shows every choice, with each guard on its arrow; a guard nothing writes is marked.
- [ ] A refused edit names the line and keeps what you typed.
- [ ] New dialogue works in a script with no dialogue, without a window error.
- [ ] After Save, `git diff` changes only the edited and the new `dialogue` blocks, and Play shows the edited lines when the Guide speaks.

## 11. Export

On the `vault` project:

1. Export page (Ctrl+E), choose Text. Then again, choose Stage.
2. Open each downloaded `.html` file from the downloads folder by double-clicking it (a `file://` page, no server).
3. On the text page, type `look` and a few moves; on the stage page, click around and use the keys.
4. In Firefox: Open files instead of a folder, make an edit, Save (it offers downloads), and Export page.

- [ ] Each export downloads one `.html` file of about 850 KB, and `git status` shows the project unchanged.
- [ ] Both pages open from disk and play; the text page's turn count goes up with each command.
- [ ] Viewing the page source shows the license near the end, in a `bespoke-license` template.
- [ ] Firefox saves edits as downloads and exports the same pages.

## 12. Failures

1. Close the tab with unsaved edits.
2. Play a game until it ends or fails, and press Run again.
3. Anything that shows the orange "A Studio window stopped on an error" panel: note what you clicked just before, then click the panel.

- [ ] Closing with unsaved edits asks first.
- [ ] After any error panel, the rest of the Studio keeps working and your files are untouched.

## 13. Recording results

Copy this table into HANDOFF's session log, fill it in, and date it.

| Section | Result | Notes (browser, OS, device, what you clicked) |
| --- | --- | --- |
| Commit tested | | |
| 1. Automated baseline | | |
| 2. Workspace (mouse / touch) | | |
| 3. New project and script text | | |
| 4. Opening and saving | | |
| 5. Check and diagnostics | | |
| 6. Play | | |
| 7. Paint | | |
| 8. Rooms and grids | | |
| 9. Cast, values, and dilemmas | | |
| 10. Dialogue | | |
| 11. Export (Chromium / Firefox) | | |
| 12. Failures | | |

For each failure:

- A defect with a clear fix becomes a fix with a check that fails without it (the smoke check, where the step can be driven through a test hook).
- Anything larger becomes a roadmap item with its origin (`found during the Studio hand test`) and an acceptance line.
- A failure you cannot reproduce goes in HANDOFF under Corrections, with what you saw and where.
