"""Checks the small-pool throw: the multiplier, the time it is given, and
that nothing tunnels through a wall at the new speed.

Three things can go wrong here, and only the first is visible by reading
the diff:

1. The multiplier misses the ends the user asked for — +25% at four dice,
   +100% at one.
2. The impulse is boosted and the time budget is not. That one is nastier
   than it sounds: a one-die roll is force-settled at its cap, so a die
   thrown twice as hard into an unchanged 1.0s budget freezes mid-bounce.
   The dice would be faster and look worse, which is the opposite of the
   ask. So the budget is asserted against the SAME function, from the same
   Swift, rather than trusted.
3. A die thrown harder than its collider is thick, at the physics step,
   passes straight through it. That is arithmetic, so it is computed here
   rather than assumed.

Every number below is read out of the shipped Swift. If a constant moves
and this does not, it says so by name.
"""
import os
import re
import sys

from tools_swiftconst import constant, source, swift_names

IMPULSE = "DiceRollImpulse.swift"
CONTROLLER = "DiceRollController.swift"
PHYSICS = "DiePhysicsFactory.swift"
LAYOUT = "PlayfieldLayout.swift"


def boost(count):
    """The Swift `smallPoolBoost(forDiceCount:)`, ported."""
    if count < 1 or count > 4:
        return 1.0
    return 1.0 + 0.25 * (5 - count)


def launch_boost(count, motion):
    """What `launch` actually multiplies linear and torque by.

    The small-pool boost AND the global one — the throw doubled for every
    game, and a small pool is still thrown harder than a full one on top
    of that."""
    return boost(count) * motion


def time_budget(count, min_d, max_d, max_pool):
    """The Swift `timeBudget(forDiceCount:)`, ported."""
    clamped = max(1, min(count, max_pool))
    progress = (clamped - 1) / float(max_pool - 1)
    return (min_d + progress * (max_d - min_d)) * boost(count)


def swift_float(text, name):
    m = re.search(
        r'let %s\s*:\s*Float\s*=\s*(-?\d+(?:\.\d+)?)' % re.escape(name), text)
    assert m, "no Float named %s" % name
    return float(m.group(1))


def check_collider_masks():
    """Every physics body names its category and what it collides with.

    This is the one failure in the physics that is completely silent. A
    body with a shape, a restitution and no masks compiles, renders, casts
    a shadow and sits exactly where it is drawn — and a die passes through
    it, because the die's own `collisionBitMask` is `die | playfield` and
    nothing told that body it was either. Nothing throws, nothing logs,
    and the object simply is not there.

    It has happened once: Baseball Dice's runner posts were built by hand
    rather than through `DiePhysicsFactory.staticCollider`, carried a shape
    and a restitution and nothing else, and were not obstacles at all. The
    posts were the whole reason the runners stand on the playfield instead
    of in a side panel.

    So: every `SCNPhysicsBody(` in the suite must have all three masks set
    within the function that builds it.
    """
    problems = []
    bodies = 0
    for filename in sorted(swift_names()):
        text = source(filename)
        for match in re.finditer(r'SCNPhysicsBody\(', text):
            # The enclosing function, near enough: from the previous `func`
            # to the next one. The masks are always set beside the body.
            start = text.rfind("func ", 0, match.start())
            end = text.find("\n    }", match.end())
            if start < 0 or end < 0:
                problems.append("%s: cannot read the function around an "
                                "SCNPhysicsBody" % filename)
                continue
            bodies += 1
            body = text[start:end]
            name = re.match(r'func (\w+)', body)
            name = name.group(1) if name else "?"
            for mask in ("categoryBitMask", "collisionBitMask",
                         "contactTestBitMask"):
                if mask not in body:
                    problems.append(
                        "%s %s() builds an SCNPhysicsBody without setting "
                        "%s — a die's own collisionBitMask is "
                        "die | playfield, so a body that does not name "
                        "its category is something dice can pass straight "
                        "through, silently"
                        % (filename, name, mask))
    # The count is printed, not decorative: a scan that silently matched
    # nothing would print the same "ok" as one that checked everything,
    # which is the shape tools_qualcheck.py once failed in.
    if not bodies:
        problems.append("found no SCNPhysicsBody anywhere — this check is "
                        "scanning nothing and would pass whatever the "
                        "physics did")
    if not problems:
        print("  %-30s ok (%d bodies, each naming its category and its "
              "collisions)" % ("collider masks", bodies))
    return problems


def main():
    impulse = source(IMPULSE)
    controller = source(CONTROLLER)
    physics = source(PHYSICS)
    failed = []

    # --- 1. The multiplier is the one that was asked for. -------------
    #
    # Asserted against the Swift's own source rather than only against
    # this port: the expression is read back and evaluated, so a changed
    # coefficient in the Swift fails here instead of passing quietly.
    m = re.search(r'return 1\.0 \+ (\d+\.\d+) \* Double\(5 - count\)', impulse)
    assert m, "smallPoolBoost is no longer `1.0 + k * (5 - count)`"
    coefficient = float(m.group(1))
    if abs(coefficient - 0.25) > 1e-9:
        failed.append("the boost coefficient is %.3f, not 0.25" % coefficient)

    wanted = {1: 2.00, 2: 1.75, 3: 1.50, 4: 1.25, 5: 1.00, 15: 1.00, 20: 1.00}
    for count, want in sorted(wanted.items()):
        got = boost(count)
        if abs(got - want) > 1e-9:
            failed.append("%d dice: boost %.3f, wanted %.3f" % (count, got, want))
    if not failed:
        print("  %-30s ok (1 die 2.00x, 4 dice 1.25x, 5+ unchanged)"
              % "small-pool multiplier")
        print("  %-30s ok (every game x%.2f, worst launch x%.2f)"
              % ("global throw",
                 swift_float(impulse, "motionBoost"),
                 max(launch_boost(n, swift_float(impulse, "motionBoost"))
                     for n in (1, 2, 3, 4))))

    # --- 2. The launch actually applies it. ---------------------------
    for label, pattern in (
        ("linear", r'minLinearImpulse\.\.\.maxLinearImpulse\) \* boost'),
        # The line break is allowed because the torque now carries the
        # size term as well, and the pair is too long for one line.
        ("torque", r'minTorqueMagnitude\.\.\.maxTorqueMagnitude\)\s*\n?\s*\* boost'),
        ("upward", r'minUpwardImpulse\.\.\.maxUpwardImpulse\) \* upwardBoost'),
    ):
        if not re.search(pattern, impulse):
            failed.append("launch() does not boost %s" % label)
    if not re.search(r'let upwardBoost = sqrt\(boost\)', impulse):
        failed.append("upward no longer takes the square root of the boost")

    # --- 2b. And the torque carries the die's SIZE SQUARED. -----------
    #
    # An angular impulse buys angular velocity through the inertia
    # tensor, w = L / I, and I goes as m r². Every die has mass 1.0
    # whatever its size — deliberately, so a big die and a small one
    # collide sensibly — so the 1.5x die was handed the same L as the
    # rest and turned at 1/1.5², which is 44% of their rate. It crossed
    # the tray and rose off the throw exactly like its neighbours, since
    # linear velocity is impulse over mass, while barely tumbling.
    #
    # This is the half of the fix that could silently come undone: drop
    # the size term and the big die goes back to not turning over, which
    # reads as a feel problem rather than a missing multiplier.
    if not re.search(r'\* boost \* size \* size', impulse):
        failed.append("torque no longer scales with the die's size squared "
                      "— the oversized die's inertia is 2.25x a normal "
                      "one's, so the same angular impulse spins it at 44%")
    elif not re.search(r'DieMeshLibrary\.sizeMultiplier\(forSides:', impulse):
        failed.append("launch computes a size for the torque without asking "
                      "DieMeshLibrary what the node's scale means")
    else:
        print("  %-30s ok (%.2fx die gets %.2fx the angular impulse)"
              % ("torque vs inertia",
                 swift_float(source("DiceSceneBuilder.swift"), "oversizeMultiplier"),
                 swift_float(source("DiceSceneBuilder.swift"), "oversizeMultiplier") ** 2))

    # The global doubling rides in the same `boost`, which is what gives
    # upward its square root for free. If it is ever applied separately to
    # the linear impulse alone, upward would take the full 2x and peak
    # height would go up FOUR times, into a ceiling the dice already hit.
    if not re.search(r'smallPoolBoost\(forDiceCount: dice\.count\)\)\s*\* motionBoost',
                     impulse):
        failed.append("launch does not fold motionBoost into the same boost "
                      "upward takes the square root of")
    if not failed:
        print("  %-30s ok (linear and torque full, upward sqrt)"
              % "launch applies it")

    # --- 3. The time budget takes the same boost. ---------------------
    #
    # The failure this guards against is the budget being left behind, so
    # it is checked two ways: the Swift must READ the shared function, and
    # the resulting budgets must actually leave room for the harder throw.
    if not re.search(r'DiceRollImpulse\.smallPoolBoost\(forDiceCount: count\)',
                     controller):
        failed.append("timeBudget does not read DiceRollImpulse.smallPoolBoost")

    min_d = constant(controller, "minRollDuration")
    max_d = constant(controller, "maxRollDuration")
    max_pool = constant(controller, "maxDiceInPool")

    # The band moved again with the ENERGY BLEED, and what it measures is
    # worth restating: this is a CAP, not how long a roll takes. A die
    # settles when it stops moving for six frames, and the budget only
    # decides when one that has not stopped is settled by force.
    #
    # It was 2.5-3.0s, set when damping was a flat 0.08 and a die bled its
    # energy off in about two seconds. Damping now starts at 0.02 and
    # ramps up over the roll's second half, so the same throw stays live
    # roughly twice as long — and a budget left at 3.0 would have spent
    # the extra by force-settling mid-bounce, which is the failure this
    # band exists to catch rather than the one it would have caused.
    #
    # The top of the band is what stops "longer" from becoming "slow": a
    # single die that somehow never settles is still on the table at six
    # seconds, and that is the worst case anyone waits through.
    for count in (1, 2, 3, 4):
        after = time_budget(count, min_d, max_d, max_pool)
        if not 4.5 <= after <= 6.0:
            failed.append("%d dice: budget %.2fs is outside 4.5-6.0s"
                          % (count, after))
    for count in (5, 10, 20):
        before = (min_d + (min(count, max_pool) - 1) / float(max_pool - 1)
                  * (max_d - min_d))
        after = time_budget(count, min_d, max_d, max_pool)
        if abs(before - after) > 1e-9:
            failed.append("%d dice: the small-pool boost reached a pool of "
                          "%d (%.2f -> %.2f); it must not" % (count, count, before, after))
    if failed:
        for line in failed:
            print("  %-30s FAILED  %s" % ("impulse", line))
        sys.exit("impulse: FAILED (%d problem(s))" % len(failed))

    print("  %-30s ok (small pools %.2f-%.2fs, no small-pool boost past 4)"
          % ("time budget",
             min(time_budget(n, min_d, max_d, max_pool) for n in (1, 2, 3, 4)),
             max(time_budget(n, min_d, max_d, max_pool) for n in (1, 2, 3, 4))))

    # --- 3b. The energy bleed ramps the right way, and lands early. ---
    #
    # What this cannot check is physics: whether a die thrown this hard,
    # damped on this schedule, is actually still by 95% of its budget is a
    # simulation question, and the iPad answers it. What it can check is
    # the shape of the schedule, where the failure is silent — a ramp that
    # ends after the cap, or one whose ends are the wrong way round, gives
    # back exactly the force-settled roll the bleed was added to avoid,
    # and nothing about the code would look wrong.
    bleed = {}
    for name in ("rollingDamping", "rollingAngularDamping",
                 "settlingDamping", "settlingAngularDamping",
                 "bleedStartFraction", "bleedEndFraction"):
        m = re.search(r'static let %s: (?:Float|Double) = ([\d.]+)' % name,
                      controller)
        if not m:
            failed.append("SettleTuning no longer declares %s" % name)
        else:
            bleed[name] = float(m.group(1))

    if len(bleed) == 6:
        if bleed["rollingDamping"] >= bleed["settlingDamping"]:
            failed.append("the bleed runs backwards: dice are damped %.2f "
                          "while rolling and %.2f while settling"
                          % (bleed["rollingDamping"], bleed["settlingDamping"]))
        if bleed["rollingAngularDamping"] >= bleed["settlingAngularDamping"]:
            failed.append("the angular bleed runs backwards (%.2f -> %.2f)"
                          % (bleed["rollingAngularDamping"],
                             bleed["settlingAngularDamping"]))
        if not 0 < bleed["bleedStartFraction"] < bleed["bleedEndFraction"]:
            failed.append("the bleed window is not a window: %.2f to %.2f"
                          % (bleed["bleedStartFraction"], bleed["bleedEndFraction"]))
        if bleed["bleedEndFraction"] >= 1.0:
            failed.append("the bleed finishes at %.2f of the budget — at or "
                          "after the hard cap, so full damping never gets a "
                          "frame to work in and the roll ends by force"
                          % bleed["bleedEndFraction"])
        # The dice must be damped BEFORE they are shoved apart, or the
        # 40x separation force fights a roll that is still lively.
        if not re.search(r'escalationStart = maxDurationForThisRoll'
                         r'\s*\*\s*SettleTuning\.bleedStartFraction', controller):
            failed.append("the repulsion escalation no longer starts with "
                          "the bleed — a typed second schedule is how 3.5s "
                          "outlived two changes to the cap")
        if not failed:
            print("  %-30s ok (%.2f/%.2f -> %.2f/%.2f over %.0f-%.0f%% of "
                  "the budget)"
                  % ("energy bleed", bleed["rollingDamping"],
                     bleed["rollingAngularDamping"], bleed["settlingDamping"],
                     bleed["settlingAngularDamping"],
                     bleed["bleedStartFraction"] * 100,
                     bleed["bleedEndFraction"] * 100))

    # --- 3c. Nothing settles under the chrome. ------------------------
    #
    # The tray's top corners are the one place a 2D overlay and the 3D
    # playfield share pixels: a die that stops under the back or settings
    # button is unreadable AND untappable, because the button eats the
    # tap. Two mechanisms answer that and BOTH fail silently — a push
    # that no longer runs leaves dice in the corner with nothing to say
    # so, and a screen that never publishes the occupancy leaves a button
    # sitting opaque on top of a die it was supposed to defer to.
    radius = re.search(r'chromeCornerRadius: Float = ([\d.]+)', controller)
    force = re.search(r'chromeCornerForce: Float = ([\d.]+)', controller)
    if not radius or not force:
        failed.append("SettleTuning no longer states the chrome corner "
                      "radius and force")
    elif "pushOutOfChromeCorners(" not in controller:
        failed.append("applyRepulsion no longer pushes dice out of the "
                      "chrome corners")
    else:
        # The radius has to cover the button plus the biggest die, or a
        # die can rest half under it and still be clear of the push.
        oversize = swift_float(source("DiceSceneBuilder.swift"),
                               "oversizeMultiplier")
        needed = 1.07 + 0.5 * oversize
        if float(radius.group(1)) < needed:
            failed.append("the chrome corner radius is %s, under the %.2f a "
                          "40pt button (1.07 units on the narrowest tray) "
                          "plus an oversized die's half-extent needs"
                          % (radius.group(1), needed))
        else:
            print("  %-30s ok (%.2f units, force %s, against %.2f needed)"
                  % ("chrome corners", float(radius.group(1)),
                     force.group(1), needed))

    # And the fallback: every screen with a tray publishes the occupancy,
    # and the button reads it.
    chrome = source("ControlShapes.swift")
    if "trayCornersOccupied" not in chrome or "allowsHitTesting" not in chrome:
        failed.append("OverlayChromeButton no longer fades and stops "
                      "hit-testing when a die is under it")
    unwired = []
    for name in sorted(swift_names()):
        if not name.endswith("Screen.swift"):
            continue
        body = source(name)
        if "OverlayChromeButton(" not in body or "DiceTraySceneView(" not in body:
            continue
        if ("onChromeCornersChanged" not in body
                or "trayCornersOccupied" not in body):
            unwired.append(name)
    if unwired:
        failed.append("%s put chrome over a dice tray without publishing "
                      "whether a die is under it" % ", ".join(unwired))
    else:
        print("  %-30s ok (every tray screen publishes it)"
              % "chrome fallback")

    # --- 4. Nothing tunnels at the new speed. -------------------------
    #
    # A collider is only safe up to thickness / timeStep units per second:
    # move further than it is thick in one step and the sweep misses it.
    max_linear = swift_float(impulse, "maxLinearImpulse")
    max_upward = swift_float(impulse, "maxUpwardImpulse")
    motion = swift_float(impulse, "motionBoost")
    top = max(launch_boost(n, motion) for n in (1, 2, 3, 4))

    m = re.search(r'physicsWorld\.timeStep = 1\.0 / (\d+(?:\.\d+)?)', physics)
    assert m, "no timeStep in %s" % PHYSICS
    step = 1.0 / float(m.group(1))
    m = re.search(r'physicsWorld\.gravity = SCNVector3\(0, (-?\d+(?:\.\d+)?)', physics)
    assert m, "no gravity in %s" % PHYSICS
    gravity = abs(float(m.group(1)))

    wall = swift_float(physics, "wallThickness")
    m = re.search(r'boxSize: SCNVector3\(width, (\d+(?:\.\d+)?), depth\)', physics)
    assert m, "no floor collider in %s" % PHYSICS
    floor = float(m.group(1))
    ceiling = swift_float(source(LAYOUT), "ceilingHeight")

    # Mass is 1.0, so an impulse is a velocity. The worst horizontal speed
    # is the boosted maximum; the worst vertical is a die launched upward
    # and falling the full ceiling height back onto the floor.
    horizontal = max_linear * top
    launch_up = max_upward * (top ** 0.5)
    falling = (launch_up ** 2 + 2 * gravity * ceiling) ** 0.5

    # The ceiling is hit, not cleared — see the note under the print
    # below — so the speed that matters there is the speed on arrival,
    # not at launch. It uses the floor's thickness, being built with the
    # same treatment.
    at_ceiling = max(0.0, launch_up ** 2 - 2 * gravity * ceiling) ** 0.5

    checks = [
        ("horizontal into a wall", horizontal, wall),
        ("falling onto the floor", falling, floor),
        ("upward into the ceiling", at_ceiling, floor),
    ]
    margins = []
    for label, speed, thickness in checks:
        limit = thickness / step
        margin = limit / speed
        margins.append(margin)
        if margin < 2.0:
            failed.append("%s: %.1f u/s against a %.1f u/s limit (%.1fx)"
                          % (label, speed, limit, margin))
    print("  %-30s ok (worst margin %.1fx, all above 2x)"
          % ("tunneling margins", min(margins)))

    # The throw would carry a die well past the ceiling if nothing were
    # there — it already does today, at half this — so the ceiling
    # collider is what contains the roll, not the launch speed. Printed
    # rather than asserted, because "would reach X without a ceiling" is
    # not a failure; arriving faster than the collider can catch is, and
    # that is the check above.
    peak = launch_up ** 2 / (2 * gravity)
    print("  %-30s ceiling at %.2f catches a throw that would reach %.2f "
          "(arrives at %.1f u/s)"
          % ("ceiling containment", ceiling, peak, at_ceiling))

    failed.extend(check_collider_masks())

    for line in failed:
        print("  %-30s FAILED  %s" % ("impulse", line))
    if failed:
        sys.exit("impulse: FAILED (%d problem(s))" % len(failed))
    print("impulse: PASS")


if __name__ == "__main__":
    main()
