# Lantern Watch: The Harbour

The dawn packet waits outside the shoals. Follow the ten connected harbour stops, read the handover papers, collect the wick and flag, and clear the packet from the outer beacon house. Six people at the quay continue their work while you travel. The dispatcher has to finish the watch handover before the signal can clear the ship.

## Run it

```bash
zig build harbour
```

Open `zig-out/harbour/index.html` and choose **Start the harbour watch**. The transcript and command field are sufficient; the map is optional. Try `read tide board`, then `go forward`. Each arrival gives the next local action. You can also `go back`.

The build compares a full native playthrough against [the golden transcript](golden.txt), checks a file save and restore at Customs, tests all ten stops through the actual browser form in headless Chrome, and reports native and Chrome tick rates. Node.js and Chrome or Chromium are required; set `CHROME` to override discovery. The single HTML file stays under the standalone page budget.

For the native transcript and a real save file, pass a new path:

```bash
zig build harbour-native -- /tmp/harbour-customs.sav
```

The native check saves at Customs, starts the pump, and restores the earlier scene, pump state, and dispatcher pay. The browser version does not offer persistent saves. The [original Lantern Watch](../lantern_watch/README.md) is a separate game.
