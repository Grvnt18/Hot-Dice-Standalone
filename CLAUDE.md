# Working notes

## Verification budget

**Keep checks cheap. This is a standing instruction, not a suggestion.**

The habit this file exists to correct: writing a fix, writing a guard for
it, deliberately breaking the fix to prove the guard catches it, restoring
it, and re-running the full sweep after every item. That is roughly 3x the
work per change and it burned most of a context window on a twelve-item
list.

What to do instead:

- **Run the full sweep ONCE, at the end.** Not after each item. If one
  verifier is obviously the relevant one, run just that one while working.
- **Do not break-and-restore to demonstrate a guard** unless asked, or
  unless the guard is the deliverable. Write the guard, run it, move on.
- **Sample, do not exhaust.** 20k Monte Carlo trials, not 200k. Three
  swatches, not 24. Enough to see the answer, not enough to publish it.
- **Add a guard only where the failure would be silent and costly.** Most
  changes do not need one. A visual tweak does not need a verifier.
- **Measure when a number is genuinely in question** — a contrast ratio, a
  payload size, a balance change. Not to decorate a decision already made.
- Prefer `grep`/`sed -n` over reading whole files. Never pipe a search
  through `head` when checking for ALL occurrences of something — that is
  how two compile errors were missed once.

Say what was and was not checked. A cheaper check honestly described beats
an exhaustive one.

## Build

There is no Swift toolchain in this container. **The iPad is the only
compiler.** Everything here is Python reading Swift source, so a "pass"
means the spelling is right, not that it builds.

Platform floor: iOS 16 SDK, Swift 5.7, Xcode 14.2 (last version running on
Monterey). `tools_typecheck_verify.py` scores SwiftUI body complexity
against that solver's limit.

## Git

**`Grvnt18/Hot-Dice-Standalone`, branch `main`, is the only repository.**
`Grvnt18/Rolls` is the lineage this came from and is long out of date —
do not read it, push to it, or compare against it.

That matters more than it sounds. A cloud container is rebuilt without
warning, and it comes back as a fresh clone of whatever the session was
started against, which has been the OLD repository. The tell is a
verifier reporting a number you know you changed — a ceiling of 2.5, a
`minRollDuration` of 1.4. Check `git log --oneline -1` before believing
anything, and if the tree is stale:

    git remote remove origin
    git remote add origin https://github.com/Grvnt18/Hot-Dice-Standalone.git
    git fetch origin main
    git checkout -B main refs/remotes/origin/main

Work lost that way is only lost if it was never pushed, so push often.

- Develop on `main` and push there. No pull request unless asked.
- Download links: read the full SHA with `git rev-parse` or `git ls-remote`
  and give
  `https://github.com/Grvnt18/Hot-Dice-Standalone/archive/<40-char-sha>.zip`.
  **Never construct a SHA** — a 7-character one padded out was given once
  and did not work.

## Guides

The in-game guides are generated verbatim from `GAME_RULES.txt` by
`tools_guides_export.py`. Do not reword, condense, or reformat them by
hand. Change the document, regenerate, and run `--check`.
