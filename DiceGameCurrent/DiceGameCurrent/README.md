# B*tches — Dice Game

Full project state. 25 Swift files, 43 resources.

## Setup

1. Swift Playgrounds → Create → App (blank template), saved "On My iPad."
2. Delete the default generated files.
3. Add all 25 files from `SwiftFiles/`.
4. Add all 43 files from `Resources/`.
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

Low-poly throughout: all materials use `.lambert` (flat matte, no
specular), lit by a hard directional key at ~60 degrees plus a strong
ambient fill. Floor and walls use procedurally generated faceted textures
(`LowPolyTextures`) rather than photographs — the floor must stay
geometrically flat to match the physics collider, so facets could only
differ in colour anyway, which a texture provides at a fraction of the
cost.

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
- **Fonts**: Stack Sans Notch (ExtraLight, the only registered weight of
  the bundled variable font) as the default everywhere, uppercase
  cascaded via `.textCase(.uppercase)`. Aguafina Script for the "ROLLS"
  floor text specifically. Both registered at runtime via CoreText as the
  first line of `DiceSceneAssembler.assemble` — not via `.onAppear` on a
  SwiftUI view, which raced against scene assembly and was the actual
  cause of a "gameplay area not rendering" bug in an earlier round.
- **Palette**: 15 colors computed directly from javier.xyz/cohesive-colors'
  documented blend algorithm (Overlay blend against #FF9C00 at 30%
  intensity), not eyeballed. Number colors computed per-body-color for
  WCAG contrast.

## Known limitations / judgment calls worth knowing about

- The bundled Stack Sans file is a variable font; only its ExtraLight
  instance is registered, since SwiftUI's `Font.custom` doesn't drive
  variable-font weight axes directly. Every size uses that same light
  weight.
- `.dae` mesh files are kept in Resources as a defensive last-resort
  fallback (`DieMeshLibrary` tries `.scn`, then `.obj`, then `.dae`) even
  though `.obj` is what's actually loading successfully — intentionally
  kept, unlike the numbered PNGs, since this fallback path is still live
  code, just not currently exercised.
