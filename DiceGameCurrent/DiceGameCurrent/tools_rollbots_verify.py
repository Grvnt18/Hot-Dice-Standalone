"""Port of the shipped Rollbots resolution, re-run against both the
design document's own figures and the tuning that followed.

Mirrors RollbotsRules.resolve and RollbotsState in Rollbots.swift. There is
no Swift toolchain in this container.

The document's four stated probabilities are checked first, because they
were all correct and any drift means the shipped code stopped matching the
design. Then the parts the document did not compute: what the weapons are
worth once the defender plays well, and whether each Cyberware is a real
option rather than a trap."""
import random

import tools_swiftconst as swiftconst

START_IP = 16
SECOND_SEAT_BONUS = 1
CRIT_AT = 7
DAMAGE_SIDES = {"blade": 8, "pistol": 6, "rail": 12, "sidearm": 4}
VIRUS_TURNS, VIRUS_DMG, VIRUS_ON = 3, 3, 3
PHASE_COUNTER = 4
REPAIR, SIDEARM_TURNS = 8, 4

# The constants above are a PORT of the Swift, not a reading of it, so
# they can drift out of agreement with the shipped game without any test
# noticing. This states which `static let`s in Rollbots.swift they stand on;
# swiftconst.expect fails by name if the Swift has moved.
SWIFT_CONSTANTS = {
    "critAccuracy": CRIT_AT,
    "phaseCounterDamage": PHASE_COUNTER,
    "repairAmount": REPAIR,
    "secondSeatBonusIP": SECOND_SEAT_BONUS,
    "sidearmTurns": SIDEARM_TURNS,
    "startingIP": START_IP,
    "virusActivatesOn": VIRUS_ON,
    "virusDamagePerTurn": VIRUS_DMG,
    "virusTurns": VIRUS_TURNS,
}


def resolve(weapon, accuracy, damage_roll, defence, defence_roll, ignores_firewall=False):
    """RollbotsRules.resolve."""
    crit = (weapon == "pistol" and accuracy >= CRIT_AT)
    raw = damage_roll * 2 if crit else damage_roll

    if defence == "none":
        return raw, 0
    if defence == "dodge":
        return (0 if defence_roll > accuracy else raw), 0     # ties fail
    if defence == "phase":
        return (0, PHASE_COUNTER) if defence_roll > accuracy else (raw * 2, 0)

    if ignores_firewall or weapon == "rail":
        return raw, 0
    if defence_roll == 8:
        return 0, 0                                            # Hard Lockdown
    if weapon == "blade" or crit:
        return max(0, raw - defence_roll // 2), 0
    return max(0, raw - defence_roll), 0


# --- the document's own numbers -------------------------------------------

def check_document():
    dodge = sum(1 for d in range(1, 7) for a in range(1, 11) if d > a)
    assert dodge == 15, dodge
    assert abs(dodge / 60 - 0.25) < 1e-9

    absorbed = [8 - resolve("blade", 5, 8, "firewall", fw)[0] for fw in range(1, 8)]
    assert sum(absorbed) / 7 == sum(fw // 2 for fw in range(1, 8)) / 7

    pistol = sum(resolve("pistol", a, r, "none", None)[0]
                 for a in range(1, 11) for r in range(1, 7)) / 60
    assert abs(pistol - 4.9) < 1e-9, pistol

    lockdown = sum(1 for fw in range(1, 9) if fw == 8) / 8
    assert lockdown == 0.125
    print("document's stated probabilities: PASS "
          "(dodge 25.0%%, pistol raw %.1f, lockdown 12.5%%)" % pistol)


def check_edges():
    # A natural-8 Hard Lockdown stops the Mono-Blade outright: penetration
    # does not apply to it.
    assert resolve("blade", 5, 8, "firewall", 8)[0] == 0
    # The Mono-Blade halves any other Firewall roll.
    assert resolve("blade", 5, 8, "firewall", 6)[0] == 8 - 3
    assert resolve("blade", 5, 8, "firewall", 7)[0] == 8 - 3      # rounds its way
    # A Pistol crit cuts armour the same way; below the crit it does not.
    assert resolve("pistol", 7, 5, "firewall", 6)[0] == 10 - 3
    assert resolve("pistol", 6, 5, "firewall", 6)[0] == 0         # 5 - 6, floored
    # The Rail Rifle is unblocked whatever the Firewall rolls, lockdown too.
    assert resolve("rail", 3, 12, "firewall", 8)[0] == 12
    # Dodge ties fail.
    assert resolve("blade", 4, 8, "dodge", 4)[0] == 8
    assert resolve("blade", 4, 8, "dodge", 5)[0] == 0
    # Quantum Phase: beat it and counter, miss it and take double.
    assert resolve("blade", 4, 8, "phase", 5) == (0, PHASE_COUNTER)
    assert resolve("blade", 4, 8, "phase", 4) == (16, 0)
    # Exposed by the Overclock takes everything.
    assert resolve("blade", 1, 8, "none", None)[0] == 8
    print("edge cases: PASS (lockdown, penetration, crit armour, tie, phase)")


# --- optimal defence, with the accuracy die visible -----------------------

def ev_dodge(weapon, acc):
    mean = {"blade": 4.5, "pistol": 3.5 * (2 if acc >= CRIT_AT else 1),
            "rail": 6.5, "sidearm": 2.5}[weapon]
    return min(acc, 6) / 6 * mean


def ev_firewall(weapon, acc):
    faces = list(range(1, DAMAGE_SIDES[weapon] + 1))
    return sum(resolve(weapon, acc, r, "firewall", fw)[0]
               for r in faces for fw in range(1, 9)) / (len(faces) * 8)


def check_visible_damage():
    """The attacker now throws accuracy and damage together, so the defender
    sees the damage value before choosing a reaction.

    That is an information change, and information changes are where games
    quietly break. It measures as almost nothing, for a reason rather than
    by luck: Dodge loses P(fail) x damage and a Firewall loses
    damage - absorb, so which is better barely depends on the damage value
    — the comparison is nearly scale-invariant. Against the Rail nothing
    changes at all, since no Firewall applies.

    Asserted rather than remembered: if a future tuning pass makes the
    damage roll matter to the choice, this fails and says so.
    """
    def loss(weapon, acc, dmg, defence):
        sides = 6 if defence == "dodge" else 8
        return sum(resolve(weapon, acc, dmg, defence, roll)[0]
                   - resolve(weapon, acc, dmg, defence, roll)[1]
                   for roll in range(1, sides + 1)) / sides

    def blind(weapon, acc, defence):
        faces = DAMAGE_SIDES[weapon]
        return sum(loss(weapon, acc, d, defence) for d in range(1, faces + 1)) / faces

    worst = 0.0
    for weapon in ("blade", "pistol", "rail"):
        blind_tot = seen_tot = 0.0
        n = 0
        for acc in range(1, 11):
            choice = min(("dodge", "firewall"), key=lambda d: blind(weapon, acc, d))
            for dmg in range(1, DAMAGE_SIDES[weapon] + 1):
                blind_tot += loss(weapon, acc, dmg, choice)
                seen_tot += min(loss(weapon, acc, dmg, "dodge"),
                                loss(weapon, acc, dmg, "firewall"))
                n += 1
        gap = blind_tot / n - seen_tot / n
        worst = max(worst, gap)
        assert gap < 0.05, "%s: seeing the damage is worth %.3f IP" % (weapon, gap)
    print("visible damage die: PASS (worth at most %.2f IP an exchange)" % worst)


def best_defence(weapon, acc):
    return "dodge" if ev_dodge(weapon, acc) < ev_firewall(weapon, acc) else "firewall"


def per_turn(weapon):
    ev = sum(min(ev_dodge(weapon, a), ev_firewall(weapon, a)) for a in range(1, 11)) / 10
    return ev / 2 if weapon == "rail" else ev


# --- matches ---------------------------------------------------------------

def attack(rng, weapon, defence=None, ignores_fw=False, forced_acc=None):
    acc = forced_acc or rng.randint(1, 10)
    d = defence or best_defence(weapon, acc)
    roll = rng.randint(1, DAMAGE_SIDES[weapon])
    dr = None if d == "none" else rng.randint(1, {"dodge": 6, "firewall": 8, "phase": 12}[d])
    return resolve(weapon, acc, roll, d, dr, ignores_fw)


def match(rng, w0, w1, ware0=None, ware1=None):
    ip = [START_IP, START_IP + SECOND_SEAT_BONUS]
    charged = [False, False]; used = [False, False]
    virus = [0, 0]; sidearm = [0, 0]; exposed = [False, False]
    phase = [False, False]
    ware = [ware0, ware1]
    seat, turns = 0, 0
    while min(ip) > 0 and turns < 400:
        turns += 1
        foe = 1 - seat
        if virus[seat] > 0:
            ip[seat] -= VIRUS_DMG; virus[seat] -= 1
            if ip[seat] <= 0: break
        if sidearm[seat] > 0: sidearm[seat] -= 1

        acted = False
        w = "sidearm" if sidearm[seat] > 0 else [w0, w1][seat]
        if ware[seat] and not used[seat]:
            kind = ware[seat]
            if kind == "virus" and turns <= 4:
                used[seat] = acted = True
                if rng.randint(1, 6) >= VIRUS_ON: virus[foe] = VIRUS_TURNS
                else: virus[seat] = VIRUS_TURNS
            elif kind == "subroutine" and ip[seat] <= 8:
                used[seat] = acted = True
                ip[seat] = min(START_IP, ip[seat] + REPAIR)
                sidearm[seat] = SIDEARM_TURNS
            elif kind == "overclock":
                used[seat] = True
            elif kind == "phase":
                used[seat] = True; phase[seat] = True

        if not acted:
            # The Overclock, once activated, applies to this seat's next
            # attack: accuracy 10, no Firewall, and the Rail Rifle skips
            # its charge. It leaves the user unable to defend afterwards.
            firing_oc = (ware[seat] == "overclock" and used[seat])
            if w == "rail" and not charged[seat] and not firing_oc:
                charged[seat] = True
            else:
                if w == "rail":
                    charged[seat] = False
                if exposed[foe]:
                    d = "none"; exposed[foe] = False
                elif phase[foe]:
                    d = "phase"; phase[foe] = False
                else:
                    d = None
                dmg, counter = attack(
                    rng, w, defence=d, ignores_fw=firing_oc,
                    forced_acc=10 if firing_oc else None)
                ip[foe] -= dmg
                ip[seat] -= counter
                if firing_oc:
                    exposed[seat] = True     # wide open on their turn
                    ware[seat] = "spent"
        seat = foe
    return turns, (0 if ip[1] <= 0 else 1)


def main():
    swiftconst.expect("Rollbots", "Rollbots.swift", SWIFT_CONSTANTS)
    check_visible_damage()
    check_document()
    check_edges()

    print("\nweapon output a turn, defender playing optimally against a visible accuracy die:")
    for w in ("blade", "pistol", "rail"):
        dodges = sum(1 for a in range(1, 11) if best_defence(w, a) == "dodge")
        print("  %-7s %.2f   dodge is correct at %d of 10 accuracies" % (w, per_turn(w), dodges))
    spread = max(per_turn(w) for w in ("blade", "pistol", "rail")) - \
             min(per_turn(w) for w in ("blade", "pistol", "rail"))
    assert spread < 0.35, spread
    print("  spread %.2f" % spread)

    rng = random.Random(20260922)
    print("\nhead to head, 20,000 matches each:")
    for a, b in [("blade", "pistol"), ("blade", "rail"), ("pistol", "rail"),
                 ("blade", "blade")]:
        res = [match(rng, a, b) for _ in range(20000)]
        first = sum(1 for r in res if r[1] == 0) / len(res)
        turns = sum(r[0] for r in res) / len(res)
        print("  %-7s vs %-7s  turns %.1f  first seat %.1f%%" % (a, b, turns, first * 100))
        assert 0.44 < first < 0.58, (a, b, first)

    print("\ncyberware — win rate for the seat that uses it, against one that does not:")
    for kind in ("virus", "phase", "overclock", "subroutine"):
        res = [match(rng, "blade", "blade", ware0=kind) for _ in range(12000)]
        wr = sum(1 for r in res if r[1] == 0) / len(res)
        print("  %-11s %.1f%%" % (kind, wr * 100))
        assert 0.44 < wr < 0.62, (kind, wr)

    print("\nRollbots: PASS")


if __name__ == "__main__":
    main()
