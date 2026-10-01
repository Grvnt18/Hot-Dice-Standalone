# Rolls — Dice Game

Full project state. 72 Swift files, 119 resources.

## Setup

1. Swift Playgrounds → Create → App (blank template), saved "On My iPad."
2. Delete the default generated files.
3. Add all 72 files from `SwiftFiles/`.
4. Add all 119 files from `Resources/`.
5. Run.

## Audio

**Dice impact sounds are built and shipping.** 30 samples (10 each of
soft / medium / hard) were transient-sliced from raw dice recordings,
de-clicked, tier-normalized and included in Resources as
`sfx_impact_<tier>_NN.wav`.

Playback runs through `DiceAudioEngine` (AVAudioEngine, 16-voice pool,
preloaded PCM buffers) rather than AVAudioPlayer — it needs pitch
variation and low-latency polyphony that AVAudioPlayer can't provide.
Each hit gets a shuffled-bag round-robin variant, +/-6% varispeed pitch
jitter, continuous gain from impact velocity, and stereo pan from the
die's screen position.

`DiceContactAudio` derives impact strength from the two bodies' relative
velocity projected onto the contact normal (SCNPhysicsContact carries no
impulse), then gates hard: a velocity floor, a 60ms per-die cooldown and
a 12ms global cooldown. Without those, settling dice produce a burst of
micro-contacts that sounds like static.

**Still missing (all no-op silently):** `music_theme`, `sfx_dice_roll`,
`sfx_die_select`, `sfx_die_deselect`, `sfx_bank`, `sfx_turn_complete`,
`sfx_button_tap`. Drop files in with those base names (mp3/m4a/wav/caf/
aiff) and they activate with no code change.

Settings (gear icon, top-right) control music and SFX independently and
persist via UserDefaults. The session uses `.ambient` with
`.mixWithOthers`, so the game never interrupts the player's own music.

## Visual style

Four colours, flat, hard-edged. Materials use `.lambert` (flat matte, no
specular), lit by a hard directional key at ~60 degrees plus a strong
ambient fill.

**The rolling area is a shader**, and the only animated material in the
app — `SmokeFloor`. Domain-warped value noise, ordered-dithered against an
8x8 Bayer threshold and posterised to exactly four tones, moving on a
closed 30-second path so it loops perfectly rather than drifting forever.
The four tones are derived from whichever swatch the player picked, hung
downward from it so the brightest of the four IS that colour.

The same four-tone derivation posterises the **baseball turf**, snapped per
facet rather than per pixel — a facet is already a flat region, so the tone
boundary lands on a triangle edge, which is already hard, and there is
nothing for a dither to break up. The **dirt is deliberately left
unposterised**: it is the one surface on that pitch whose job is to be a
different material, and it is what makes the green read as grass.

The **dice** carry the same 8x8 Bayer stipple, but as a *shading* pass
rather than a quantiser: it sits in the body material's multiply channel, so
every texel is either the body colour or the body colour scaled by
`1 - ditherStrength`. The hue never moves and all fifteen colourways stay as
distinguishable as they were — the floor posterises to four tones and the
dice deliberately do not, because that palette is how you tell one die from
another.

The numerals are unreachable by it, and that is structural rather than
careful: `DieFaceLabels` puts each numeral on its own `SCNPlane` child node
with its own material, while `applyBodyMaterial` sets
`node.geometry?.materials = [material]` on the die body alone. There is no
path from that channel to a numeral, and `tools_dice_verify.py` asserts both
halves of it. That tool also guards the two settings that look like
nits and are not: `magnificationFilter = .nearest`, without which an 8x8 tile
magnified across a face arrives as a soft grey wash, and the multiply channel
itself, since the same texture in `diffuse` would replace the body colour
rather than shade it.

Rollbots is the one arena in **steel** rather than timber —
`ArenaStyle.RimMaterial` is `.none`/`.wood`/`.steel`, and `pixelSteel` is
`pixelWood`'s sibling in the same grammar: four tones, hard seams, chamfered
edges, riveted plate in place of planks and knots. Its rim and the panels
above it share ONE image at ONE tile fraction, which is the same contract
the timber has and the same seam it prevents.

It arrives as a *string*, compiled by SceneKit at runtime, because this is
a Swift Playgrounds project: there is no target to add a `.metal` file to
and no build step to hook, so the only way a shader gets in is as data. A
still frame of the same maths is set as the diffuse texture first and the
shader layered over it — SceneKit reports a shader that fails to compile
asynchronously on the render thread, so there is nothing to catch, and
ordering it this way means the tray cannot end up black.

**Nothing behind or beside the tray is black.** The floor plane is painted
6% wider than the playfield so the camera cannot see past it at any aspect
(bounds, colliders, rim and spawn all still use the true bounds), and both
scene backgrounds take the field's darkest tone.

**The wood** (`LowPolyTextures.pixelWood`) is four tones as well: three
chunky boards with hard seams, chamfered edges, curved grain, knots and
studs. Its base `#AE7B5B` was measured off the low-poly reference art
rather than chosen. The 3D rim and the SwiftUI header and footer must call
it with identical arguments — the cache keys on them, so identical
arguments return the identical image and the three read as one piece of
timber.

**The chrome** goes through three files and only those: `Elevation` owns
depth (hard offsets, zero blur), `PieceSheen` owns the light (flat bands
with hard steps, no interpolation) and `PixelPanel` owns the edge.

`BaseballField` and Royal UR's board still use the older
`facetedSurface` generator, which is unchanged.

### Seeing any of it without an iPad

There is no Swift compiler or renderer in the container this was
developed in, so every visual decision was made against a Python port and
then checked against the Swift:

    python3 tools_smoke_preview.py            # stills, several swatches
    python3 tools_smoke_preview.py --gif      # the field at true speed
    python3 tools_smoke_preview.py --loop     # one whole cycle, fast
    python3 tools_smoke_preview.py --check    # loop closes, everything moves
    python3 tools_wood_preview.py             # the tile, and a tray using it

    python3 tools_smoke_verify.py             # Swift and Python agree
    python3 tools_wood_verify.py              # ...and the timber is one piece

## Latest round: physics tuning, labels, selection, layout

**Physics — repulsion is now time-escalating.** Gentle while dice are
still genuinely tumbling (won't fight the lively collisions), but past
3.5s into the roll the speed-gate is dropped entirely and the force ramps
up to 20x by the 5.0s hard cap — any remaining overlap should be
physically resolved well before force-settle, not just less likely.

**D8/D10/D12 labels — kept Stack Sans throughout, per correction.** The
previous round's switch to a bold system font was the wrong fix for the
wrong reason — the size request was aesthetic, not a workaround. The
actual issue: Stack Sans Notch's only registered instance is ExtraLight
(thin strokes), and the label texture's 128px source canvas didn't have
enough resolution for those thin strokes to survive minification onto
d8/d10/d12's smaller label planes. Raised the canvas to 512px (font size
scaled up to match) so the renderer has far more detail to work with
before any shrinking happens — genuinely Stack Sans throughout, not
abandoned for a different font.

**Selection indicator — replaced entirely, not retuned.** The glow
approach was confirmed invisible by direct testing across two attempts at
tuning it. Replaced with something structurally simpler: a repeating
opacity pulse (100% -> 20% -> 100%, one cycle per second) directly on the
die node. SceneKit inherits opacity down the node hierarchy, so this
fades face labels along with the body automatically.

**Score bar — redesigned, not just resized.** Cells were forced square
(sized to the smaller of available width/height), which wasted the wider
dimension every time. Switched to independently-sized rectangular cells
(8 columns x 2 rows instead of 5x3) — this is what actually let cells and
score text grow without needing more vertical space, not a height
increase.

**Cell/button update reliability — added a defensive timer-based
refresh**, alongside (not replacing) the existing event-driven one. This
recurred across multiple rounds despite repeated code review finding the
event-driven wiring logically correct each time — rather than propose a
sixth unconfirmed theory, this guarantees the UI can't stay stale for
more than ~0.15s regardless of whatever gap actually exists.

**ROLLS text**: enlarged another 50% (now 0.45x playfield width, up from
0.3x last round, 0.2x originally).

## What changed in the prior review pass

**A real compile-breaking bug, found and fixed**: an earlier edit had
merged two statements onto one line with no separator in
`DiceSceneAssembler.swift` (`let round = DiceGameRound()        let
lifecycle = ...`) — this would have failed to compile. Fixed. The whole
codebase was then swept for the same pattern and brace-balance checked
file by file; nothing else turned up.

**Dead code removed**:
- `PlayfieldBoundsCalculator.swift` — entire file, explicitly marked
  superseded by `PlayfieldLayout.swift` months ago, confirmed unused. Not
  part of this package — if it's still sitting in your live Playgrounds
  project (it was, as of the last screenshot), delete it there too.
- `DiceGameRound.canRoll`, `DiceTurnController.isTurnOver`,
  `DicePoolLifecycleController.isPoolEmpty`, `DiceTurnController.startTurn()`
  — all confirmed unreferenced anywhere.
- `d6_Numbers.png` / `d8_Numbers.png` / `d10_Numbers.png` /
  `d12_Numbers.png` — the original numbered UV textures, orphaned since
  numerals moved to `DieFaceLabels`'s per-face plane approach. Only
  referenced in a code comment, not by any active path. Removed from
  Resources.
- `DiceTapHandler.onTapDiagnostic` and the `tapDebugStatus` state/binding
  chain it fed — this was a temporary diagnostic aid from tracking down
  an old tap-selection bug (long since fixed). It was still computing a
  status string on every tap, threading it through 3 files, into a
  SwiftUI `@State` var that — checked directly — was never actually
  displayed anywhere in the current view body. Removed the whole chain:
  `DiceTapHandler`'s tap handling logic is simpler as a result too.

**Redundant code consolidated**: `UIColor(hex:)` and `SCNVector3.simd`
were each independently, identically defined in two different files.
Both now live once in the new `SharedExtensions.swift`.

**Font consistency fix**: die face numerals (`DieFaceLabels`) were still
using the system font — switched to Stack Sans to match the "default
font for the entire program" instruction, falling back to system bold if
the custom font somehow isn't registered yet.

**Stale comment fixed**: `DicePhysicsWorldConfigurator` still referenced
the old "1-3.5s roll budget" after `maxRollDuration` was raised to 5.0 in
an earlier round. `AppFonts.registerIfNeeded()`'s doc comment also still
described the old (superseded, and actually buggy) `.onAppear`-based
call site instead of the current, correct one.

## Current architecture summary

- **Rendering**: die numerals are small flat planes per face
  (`DieFaceLabels`), not baked mesh textures — that approach only ever
  worked for d8 despite extensive debugging, so numerals were moved to a
  mechanism proven reliable on every shape. Position/size are per-shape
  computed values (verified against actual mesh geometry), not one
  uniform guess.
- **Physics**: `SCNPhysicsBody` rigid-body dynamics with `convexHull`
  collision shapes — the exact, not-approximated choice for a convex
  object like a die. Mass is 1.0 (not the earlier 0.01, which made the
  impulse-to-velocity relationship dangerously sensitive). Visible walls
  are a modest, reasonable height; the actual invisible physics boundary
  is far taller (60 units) — deliberately decoupled so containment is
  guaranteed regardless of roll energy without the visible walls looking
  absurd.
- **Fonts**: **Poppins** everywhere, in five bundled static weights
  (Regular, Medium, SemiBold, Bold, Black), uppercase cascaded via
  `.textCase(.uppercase)`. **Lobster** for four ornamental places only: the
  hub wordmark, the floor title, the "ROLLS" die face, and the short praise
  words on the turn-complete overlay. All registered at runtime via CoreText
  as the first line of `DiceSceneAssembler.assemble` — not via `.onAppear`
  on a SwiftUI view, which raced against scene assembly and was the actual
  cause of a "gameplay area not rendering" bug in an earlier round.

  The script face is kept off anything a player has to read. The largest
  case was the ballpark: `BaseballField` funnelled the *entire scoreboard*
  — inning numbers, run totals, the V/H rows and OUTS — through the script
  at 2.4-3.0% of texture width. Also moved to Poppins: the guide-bubble
  game names, the baseball turn prompts, option-card titles and at-bat
  result banner, the pass-and-play handover and match result, the Generals
  scorecard title, and the one praise caption that is a sentence rather
  than a word. The tell was mechanical — every site with a
  `minimumScaleFactor` at or below 0.6 was text expected to shrink, and a
  script fails first under shrink.
- **Palette**: 15 colors computed directly from javier.xyz/cohesive-colors'
  documented blend algorithm (Overlay blend against #FF9C00 at 30%
  intensity), not eyeballed. Number colors computed per-body-color for
  WCAG contrast.

## Scaling, and what is tight on a phone

Measured against a 375pt-wide phone (iPhone SE 3rd gen, 13 mini — the
narrowest the app runs on), with roughly 620pt of usable height.

**Structurally sound, nothing to do:**

- The shell derives header/scene/button from `geo.size` with a
  `minButtonHeight` floor, and clamps `sceneHeight` to `min(width, …)` so
  the tray can never exceed the width.
- `BaseballField` expresses every constant as a fraction of the texture
  width through `px()`/`py()` — including the scoreboard's outline and
  bevel — so the panel scales natively rather than by a second set of rules.
- `RoyalUrLayout` derives everything from one `tile`, and the frame and
  grout are sized from `margin`/`gap`, so they hold their proportion.
- Dynamic Type is deliberately pinned to `.large` on every screen, with
  `AppFonts` using the `relativeTo:` overload so shrink-to-fit still works
  inside the pin. Fixed-geometry game screens are the case where pinning is
  correct rather than lazy.

**Fixed in this pass:**

- **Rollbots rails took half the phone.** `railWidth` clamped at a 92pt
  floor, and `0.22 x 375` is 82.5, so the floor won on every phone: two
  rails were 184pt of 375. The floor existed to stop a *fixed* 12pt weapon
  name collapsing; the labels derive from the rail width now, so the floor
  came down to 78.
- **Score cells spent a quarter of themselves on chrome.** A cell is about
  30 x 34pt on a phone and `PixelPanel` put 2pt of outline plus 2pt of
  bevel on every side. `cellRadius`'s doc comment had promised a thinner
  outline for cells since it was written; only the corner was ever
  implemented. `cellOutline`/`cellBevel` at 1pt now exist and are used.
- Two 10pt labels raised to 11, the floor the rest of the app respects.
- `GuideBubbles` and `PassAndPlayHost` were the only two surfaces not
  pinned to `.large`.

**Noted, not changed:**

- **Royal UR's finest markings are about 3pt across on a phone.** At 375pt
  the tile is 42pt, so `dottedField`'s dots (`tile * 0.035`) land near 3pt.
  Legible at the limit rather than wrong, and the one item here that wants
  a device rather than a number.

## Known limitations / judgment calls worth knowing about

- Poppins is bundled as five separate static files rather than one
  variable font, because SwiftUI's `Font.custom` does not drive variable
  weight axes — which is exactly why the previous face shipped at a single
  ExtraLight weight at every size. A weight is now a file.
- `.dae` mesh files are kept in Resources as a defensive last-resort
  fallback (`DieMeshLibrary` tries `.scn`, then `.obj`, then `.dae`) even
  though `.obj` is what's actually loading successfully — intentionally
  kept, unlike the numbered PNGs, since this fallback path is still live
  code, just not currently exercised.
