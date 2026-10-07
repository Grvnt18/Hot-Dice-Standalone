"""Checks the sources stay inside the SDK the Mac can actually build.

This project is written on an iPad, in Swift Playgrounds, against whatever
iOS that iPad runs — currently 18. The Messages extension, which is the
whole point of Step 5, cannot be built there at all; it needs Xcode. And
the Mac available runs **macOS 12 Monterey**, whose last Xcode is 14.2,
carrying the **iOS 16.2 SDK**.

So the two machines disagree about what compiles, and the iPad is the
permissive one. Code written there against an iOS 17 API builds happily,
ships to no Mac, and fails weeks later when someone opens Xcode — which is
the worst possible moment to find out.

This states the floor and fails anything above it. The list is spellings
rather than anything clever: there is no Swift toolchain in this container
to ask, and a list that catches the APIs somebody would actually reach for
costs one line each and is worth far more than nothing.

**The floor is permanent**, not a temporary accommodation. That Mac
cannot be updated past macOS 12, so Xcode 14.2 is the ceiling for as long
as it is the only one — and the Messages extension cannot be built
anywhere else, since Swift Playgrounds does not make app extensions.

`PLATFORM.txt` says all of this in plain words, including the part worth
remembering: the floor limits almost nothing. Every game in the suite is
already built from things far older than it.

If a newer Mac ever appears, lifting the floor is deleting entries from
the list below and nothing else — the older spellings all still compile
on newer SDKs, which is exactly why they were chosen.
"""
import os
import re
import sys

from tools_swiftconst import source, SWIFT

# What the Mac can build today: Monterey -> Xcode 14.2 -> iOS 16.2 SDK,
# and Swift 5.7. The SDK is the obvious gate; the LANGUAGE version is the
# one that would be missed, because nothing about a macro or an
# if-expression looks like a platform problem.
FLOOR = "iOS 16 / Swift 5.7"

# The ONE file allowed to name both spellings of `onChange`.
#
# It is SharedExtensions.swift rather than a file of its own, and that is
# deliberate: neither the Xcode project nor the Playgrounds project picks
# up a NEW file on its own, so every new file is a chance for a build to
# fail with "no member 'onValueChange'" on twelve lines at once. A small
# shared type goes in a file that already exists.
#
# It carries a `#if swift(>=5.9)` that picks the two-parameter form on a
# current toolchain and the one-parameter form under Xcode 14.2, so the
# Mac compiles what it has an SDK for and the iPad stops warning. The
# rule below rejects the two-parameter call everywhere else, and it has
# to let this file through or the fix fails its own check.
ONCHANGE_SHIM = "SharedExtensions.swift"

# (pattern, the SDK it needs, what to write instead)
#
# Every one of these compiles in Playgrounds on the iPad and fails under
# Xcode 14. Ordered roughly by how likely anyone is to reach for it.
ABOVE_THE_FLOOR = [
    (r'\.onChange\(of:[^)]*\)\s*\{\s*_?\w*\s*,',
     "iOS 17",
     "the one-parameter form — its closure takes the NEW value, which is "
     "what the second parameter was"),
    (r'@Observable\b', "iOS 17", "ObservableObject with @Published"),
    (r'@Bindable\b', "iOS 17", "@ObservedObject"),
    (r'\bContentUnavailableView\b', "iOS 17", "a VStack"),
    (r'\.symbolEffect\(', "iOS 17", "a plain Image"),
    (r'\.sensoryFeedback\(', "iOS 17", "UIImpactFeedbackGenerator"),
    (r'\.scrollTargetBehavior\(', "iOS 17", "a plain ScrollView"),
    (r'\.scrollTargetLayout\b', "iOS 17", "a plain ScrollView"),
    (r'\.scrollPosition\(', "iOS 17", "ScrollViewReader"),
    (r'\.containerRelativeFrame\(', "iOS 17", "GeometryReader"),
    (r'\bPhaseAnimator\b', "iOS 17", "withAnimation"),
    (r'\bKeyframeAnimator\b', "iOS 17", "withAnimation"),
    (r'\.inspector\(', "iOS 17", "a sheet"),
    (r'\bSwiftData\b|@Model\b', "iOS 17", "Codable and UserDefaults"),
    (r'\bMeshGradient\b', "iOS 18", "LinearGradient"),
    (r'\.onGeometryChange\(', "iOS 18", "GeometryReader"),
    (r'\bTabViewStyle\.sidebarAdaptable|\.sidebarAdaptable\b', "iOS 18",
     "a plain TabView"),
    (r'\.scrollEdgeEffect', "iOS 26", "nothing — it is decoration"),
    (r'\bglassEffect\b|\.glassBackgroundEffect\(', "iOS 26",
     "the material backgrounds already used"),

    # Language, not SDK. Xcode 14.2 is Swift 5.7, so everything the 5.9
    # compiler added is out — and none of it announces itself as a
    # platform problem, which is why it is listed rather than assumed.
    (r'#Preview\b', "Xcode 15 (Swift 5.9 macros)",
     "a PreviewProvider struct, or nothing — this project has no previews"),
    (r'=\s*if\s', "Swift 5.9 (if expressions)",
     "a var and an if statement"),
    (r'=\s*switch\s', "Swift 5.9 (switch expressions)",
     "a var and a switch statement"),
    (r'\beach\s+[A-Z]\w*', "Swift 5.9 (parameter packs)",
     "an array or an overload"),
    (r'~Copyable', "Swift 5.9 (noncopyable types)", "a struct"),
    (r'@attached\(', "Swift 5.9 (macros)", "a function"),
    (r'\b(?:consuming|borrowing)\s+\w+\s*:', "Swift 5.9 (ownership)",
     "a plain parameter"),
]


# The Simulator's Metal is a REDUCED FEATURE SET, which is a different
# problem from the SDK floor and needs its own check.
#
# Nothing here fails to compile. Each of these is a render target the
# Simulator cannot provide, and SceneKit asks for it mid-frame — so the
# validation layer aborts the process and the app presents as a black
# screen with dead buttons rather than as an error. Two have cost a build
# round each:
#
#   .multisampling4X  ->  a multisampled DEPTH attachment it cannot resolve
#   .deferred shadows ->  a single-channel (R8Unorm_sRGB) mask it cannot
#                         allocate
#
# Both are now one compile-time decision in one enum, and this check is
# what stops a third call site quietly setting the literal again. The
# enums live in DiceSceneEnvironment.swift, beside the light whose shadow
# mode they decide — not in files of their own, because a new file is not
# picked up by either hand-assembled project and has already broken a
# build on both machines at once. It says
# nothing about whether the value is right — only that the choice is made
# in the one place that knows about the Simulator.
#
# (setting, the enum that owns it, the file the enum lives in)
#
# The file now holds BOTH enums, so a check that only asked whether the
# FILE contained `#if targetEnvironment(simulator)` would pass on one
# enum's test while the other had lost its own. Shown happening: after
# the move, deleting SceneShadows' `#if` still passed. The check reads
# each enum's own body instead, which is what `enum_body` below is for.
# (setting, enum, owning file, values that are safe on EVERY platform)
#
# The fourth element is a deliberate widening, and it needs its reason on the
# record because it loosens the check below.
#
# The rule was "the enum must branch on targetEnvironment(simulator)", which
# assumed the device and the Simulator always want different answers. That
# stopped being true for antialiasing: it is off EVERYWHERE now, because the
# jaggies are the pixel-art look rather than a defect, and a compile-time
# branch whose two arms return the same value reads as though they differ.
#
# What the check actually cares about is that the Simulator never receives a
# value it cannot render — and an unconditional `.none` guarantees that more
# strongly than a branch does, since there is no arm to get wrong. So a branch
# OR a known-safe constant passes; anything else still fails.
#
# Shadows keep the branch, and the empty-by-design distinction matters:
# `.forward` would be safe on both, but the device wants `.deferred`, so there
# the two platforms genuinely differ and the branch is load-bearing.
SIMULATOR_RENDER_TARGETS = [
    ("antialiasingMode", "SceneAntialiasing", "DiceSceneEnvironment.swift",
     ("SCNAntialiasingMode.none",)),
    ("shadowMode", "SceneShadows", "DiceSceneEnvironment.swift",
     ()),
]


def enum_body(text, name):
    """The text of one `enum Name { ... }`, brace-matched.

    Needed because several small shared types share a file now, so
    "is this string somewhere in the file" stopped being evidence about
    any particular one of them.
    """
    marker = "enum %s {" % name
    if marker not in text:
        return None
    i = text.index(marker) + len(marker)
    depth = 1
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j]
    return None


def strip(text):
    """Comments out, so a doc comment discussing an API is not a hit.

    Several of the comments in this tree name the very APIs below, saying
    why they are not used — which is exactly the note that would otherwise
    fail this check.
    """
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    text = re.sub(r'///[^\n]*', '', text)
    text = re.sub(r'(?<!:)//[^\n]*', '', text)
    return re.sub(r'/\*.*?\*/', '', text, flags=re.S)


def main():
    print("floor: %s (macOS 12 Monterey, Xcode 14.2)" % FLOOR)

    failures = []
    files = sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift"))
    for filename in files:
        text = strip(source(filename))
        for pattern, sdk, instead in ABOVE_THE_FLOOR:
            # The shim is where the two spellings are reconciled, so it
            # is the one place the newer one is allowed to appear. Only
            # that rule is waived, and only in that file — every other
            # entry below still applies to it.
            if filename == ONCHANGE_SHIM and "onChange" in pattern:
                continue
            for match in re.finditer(pattern, text):
                line = text[: match.start()].count("\n") + 1
                failures.append(
                    "%s:%d  %r needs %s — use %s"
                    % (filename, line, match.group(0).strip(), sdk, instead))

    for line in failures:
        print("  %-18s FAILED  %s" % ("platform", line))
    if failures:
        sys.exit("platform: FAILED (%d call(s) above the %s floor)"
                 % (len(failures), FLOOR))

    print("  %-18s ok (%d files, %d spellings checked)"
          % ("above the floor", len(files), len(ABOVE_THE_FLOOR)))

    check_onchange_goes_through_the_shim()
    check_simulator_render_targets()
    check_documents()
    print("platform: PASS (nothing the Mac cannot build, nothing the "
          "Simulator cannot render)")


def check_onchange_goes_through_the_shim():
    """`.onChange` is spelled once, in one file, for both toolchains.

    Exempting the shim from the two-parameter rule would otherwise leave
    a hole the other way: a screen could go back to the ONE-parameter
    form, build on both machines, and quietly put its deprecation
    warning back — which is the thing being fixed. The rule that closes
    it is not "which spelling" but "who is allowed to spell it at all".

    So every screen calls `.onValueChange(of:perform:)` and only
    `OnValueChange.swift` calls `.onChange`. That is the same shape as
    `ScriptText` owning the Aguafina font and `SceneAntialiasing` owning
    the multisampling mode: one door, checked, rather than a convention
    that holds until someone adds a screen.
    """
    failures = []
    files = sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift"))

    if ONCHANGE_SHIM not in files:
        sys.exit("platform: FAILED (%s is gone, so nothing reconciles the "
                 "two spellings of onChange)" % ONCHANGE_SHIM)

    # Scoped to the function, not the file, for the same reason the
    # enums above are: SharedExtensions.swift holds several unrelated
    # things, and "somewhere in this file" is not evidence about this one.
    whole = source(ONCHANGE_SHIM)
    if "func onValueChange" not in whole:
        sys.exit("platform: FAILED (onValueChange is gone from %s)"
                 % ONCHANGE_SHIM)
    shim = whole[whole.index("func onValueChange"):]
    shim = shim[: shim.index("\n    }") + 6]

    if "#if swift(" not in shim:
        failures.append("onValueChange no longer tests the compiler version "
                        "— one of the two machines is about to get the "
                        "wrong spelling")
    for spelling in ("{ _, newValue in", "{ newValue in"):
        if spelling not in shim:
            failures.append("onValueChange no longer carries the %r branch"
                            % spelling)

    for filename in files:
        if filename == ONCHANGE_SHIM:
            continue
        text = strip(source(filename))
        for match in re.finditer(r'\.onChange\(', text):
            line = text[: match.start()].count("\n") + 1
            failures.append(
                "%s:%d  calls .onChange directly — use "
                ".onValueChange(of:perform:), which is the one place that "
                "knows what each toolchain has" % (filename, line))

    for line in failures:
        print("  %-18s FAILED  %s" % ("onChange", line))
    if failures:
        sys.exit("platform: FAILED (%d onChange problem(s))" % len(failures))

    calls = sum(len(re.findall(r'\.onValueChange\(', strip(source(f))))
                for f in files)
    print("  %-18s ok (%d call(s) through %s)"
          % ("one onChange", calls, ONCHANGE_SHIM))


def check_simulator_render_targets():
    """Every Simulator-hostile render target routed through its own enum.

    The SDK floor above is about what COMPILES. This is about what runs:
    the Simulator's Metal lacks render targets real hardware has, and
    SceneKit reaches for them without asking. The failure is a fatal
    validation assertion mid-frame, which looks like a blank screen and
    unresponsive buttons — so it gets diagnosed as a layout or lifecycle
    bug, twice now, before anyone reads the console carefully.

    Each such choice lives in one enum behind
    `#if targetEnvironment(simulator)`, so the device build is unchanged
    and the Simulator gets the thing it can actually allocate. This
    asserts the call sites go through that enum rather than setting the
    literal, and that the enum still carries the compile-time test — an
    enum that returns the device value unconditionally would pass a
    grep for its own name while fixing nothing.
    """
    failures = []
    files = sorted(f for f in os.listdir(SWIFT) if f.endswith(".swift"))

    for setting, enum_name, owner, safe_everywhere in SIMULATOR_RENDER_TARGETS:
        accessor = "%s.mode" % enum_name
        if owner not in files:
            failures.append("%s is gone, so nothing decides %s per platform"
                            % (owner, setting))
            continue

        # The enum has to actually branch on the platform — checked
        # against ITS OWN body, not merely somewhere in the file.
        body = enum_body(source(owner), enum_name)
        if body is None:
            failures.append("enum %s is gone from %s, so nothing decides "
                            "%s per platform" % (enum_name, owner, setting))
            continue
        branches = "#if targetEnvironment(simulator)" in body
        unconditional = any(v in body for v in safe_everywhere)
        if not branches and not unconditional:
            failures.append("enum %s neither tests "
                            "targetEnvironment(simulator) nor returns a value "
                            "the Simulator can render (%s) — it would hand "
                            "the Simulator something it aborts on"
                            % (enum_name,
                               ", ".join(safe_everywhere) or "none defined"))

        # And every assignment of the setting has to use it.
        #
        # The owner file is scanned too, not skipped. Since the enums
        # moved next to the light they configure, the owner IS one of the
        # call sites — skipping it made this check report the setting as
        # dead. The enum's own body never assigns the property, only
        # returns a value, so including the file costs nothing.
        seen = 0
        for filename in files:
            text = strip(source(filename))
            for match in re.finditer(r'\.%s\s*=\s*([^\n]+)' % setting, text):
                seen += 1
                value = match.group(1).strip()
                if accessor not in value:
                    line = text[: match.start()].count("\n") + 1
                    failures.append(
                        "%s:%d  sets %s to %s — use %s, which is the one "
                        "place that knows the Simulator cannot render it"
                        % (filename, line, setting, value, accessor))
        if seen == 0:
            failures.append("nothing assigns %s any more, so %s is dead — "
                            "delete it or restore the call site"
                            % (setting, accessor))

    for line in failures:
        print("  %-18s FAILED  %s" % ("simulator", line))
    if failures:
        sys.exit("platform: FAILED (%d Simulator render-target problem(s))"
                 % len(failures))

    print("  %-18s ok (%d setting(s) decided at compile time)"
          % ("simulator gaps", len(SIMULATOR_RENDER_TARGETS)))


def check_documents():
    """The two documents for the Mac, against the thing they describe.

    `PLATFORM.txt` tells a person what not to write; this file stops it
    happening. If those two lists drift apart, the document is worse than
    nothing — it would name an API the checker allows, or miss one it
    rejects, and the person reading it would trust it either way.

    `MAC_SETUP.txt` carries a file count for the build, and the whole
    reason it does is that a missing resource makes NO error, just a
    quiet hole. A stale count in that document is the one thing that
    would send someone hunting for a file that does not exist, or worse,
    stop them noticing one that is missing.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    failures = []

    # --- 1. PLATFORM.txt and this file name the same things -----------
    platform_path = os.path.join(here, "PLATFORM.txt")
    if not os.path.exists(platform_path):
        sys.exit("platform: FAILED (PLATFORM.txt is gone — the floor has "
                 "a checker but nothing a person can read)")
    platform = open(platform_path).read()

    for spelling in ("@Observable", "@Bindable", "ContentUnavailableView",
                     "symbolEffect", "sensoryFeedback", "MeshGradient",
                     "SwiftData", "#Preview", "scrollTargetBehavior",
                     "scrollPosition", "containerRelativeFrame",
                     "PhaseAnimator", "KeyframeAnimator"):
        if spelling not in platform:
            failures.append("PLATFORM.txt does not mention %s, which this "
                            "file rejects — the document is incomplete"
                            % spelling)
    for phrase in ("iOS 16", "Swift 5.7", "Monterey", "Xcode 14.2"):
        if phrase not in platform:
            failures.append("PLATFORM.txt no longer states %r" % phrase)

    # --- 2. MAC_SETUP.txt's counts against the folders ----------------
    setup_path = os.path.join(here, "MAC_SETUP.txt")
    if not os.path.exists(setup_path):
        sys.exit("platform: FAILED (MAC_SETUP.txt is gone)")
    setup = open(setup_path).read()

    resources = os.listdir(os.path.join(here, "Resources"))
    actual = {}
    for name in resources:
        actual[name.rsplit(".", 1)[-1]] = actual.get(
            name.rsplit(".", 1)[-1], 0) + 1

    for count, ext in re.findall(r'^\s+(\d+)\s+\.(\w+)\s', setup, re.M):
        if actual.get(ext, 0) != int(count):
            failures.append("MAC_SETUP.txt says %s .%s files, Resources has "
                            "%d" % (count, ext, actual.get(ext, 0)))

    if str(len(resources)) not in setup:
        failures.append("MAC_SETUP.txt's total is not %d, which is what "
                        "Resources actually holds" % len(resources))

    swift = len([f for f in os.listdir(SWIFT) if f.endswith(".swift")])
    if str(swift) not in setup:
        failures.append("MAC_SETUP.txt's Swift count is not %d" % swift)

    # --- 3. And the numbers beside the commands that print them -------
    #
    # The two checks above are "does this number appear anywhere in the
    # file", which is weaker than it looks and let a real error through:
    # MAC_SETUP told the reader to run `ls Resources | wc -l` and
    # annotated it `# 113`, four lines under a prose total of 162. The
    # prose satisfied the substring test, so this file passed while the
    # document said two different things about the same command.
    #
    # 113 was right before the sound effects landed. That is how these go
    # wrong — not typed wrong, but true once.
    #
    # So the annotation on each command is read as the claim it is, and
    # compared against what the command would actually print.
    expected = {"Resources": len(resources), "SwiftFiles": swift}
    for folder, claimed in re.findall(
            r'ls \S*?(Resources|SwiftFiles)\S*?\s*\|\s*wc -l\s*#\s*(\d+)',
            setup):
        if int(claimed) != expected[folder]:
            failures.append(
                "MAC_SETUP.txt annotates its %s count command `# %s`, but "
                "that command prints %d" % (folder, claimed, expected[folder]))

    for line in failures:
        print("  %-18s FAILED  %s" % ("documents", line))
    if failures:
        sys.exit("platform: FAILED (%d document problem(s))" % len(failures))

    print("  %-18s ok (PLATFORM.txt agrees, MAC_SETUP.txt counts %d "
          "resources and %d sources)"
          % ("for the Mac", len(resources), swift))


if __name__ == "__main__":
    main()
