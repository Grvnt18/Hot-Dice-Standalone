"""Scope-aware check: for every `Type.member` call, confirm `member` is
declared INSIDE that type's own brace range.

Replaces a plain substring grep, which happily reported `static func
stackSans` as resolving even though it lives in `extension Font`, not in
`enum AppFonts`.

Only types DECLARED in this module are checked. A type we merely extend
(Color, UIColor, Font) gets most of its members from the framework, which
isn't visible here, so checking those would be all false positives."""
import re, sys, os, glob, collections


def sources():
    """The Swift files, wherever this is run from.

    It used to be a bare glob('*.swift'), which meant running it from the
    project root — the obvious place — scanned NOTHING and printed a
    confident PASS. A check that cannot fail is worse than no check, so
    the path is now anchored to this script's own location and an empty
    result is a hard error rather than a pass."""
    if sys.argv[1:]:
        return sorted(sys.argv[1:])
    here = os.path.dirname(os.path.abspath(__file__))
    found = sorted(glob.glob(os.path.join(here, "SwiftFiles", "*.swift"))
                   or glob.glob(os.path.join(here, "*.swift")))
    if not found:
        sys.exit("qualcheck: found no .swift files to check — refusing to "
                 "report a pass over nothing")
    return found


SOURCES = sources()

def _keep_interpolations(match):
    """Blank a string literal but keep any \\(...) segments.

    Swift interpolation holds real code — FreeRollPool.maxDice appeared only
    inside "\\(pool.total) / \\(FreeRollPool.maxDice)", so blanking literals
    wholesale hid it from this check entirely."""
    body = match.group(0)
    parts = re.findall(r'\\\((.*?)\)', body)
    return '"" ' + ' '.join(parts) + ' ' if parts else '""'

def strip(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    return re.sub(r'"(?:\\.|[^"\\])*"', _keep_interpolations, src)

def body_after(s, pos):
    i = s.find('{', pos)
    if i < 0: return ''
    depth, j = 0, i
    while j < len(s):
        if s[j] == '{': depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0: break
        j += 1
    return s[i:j]

members = collections.defaultdict(set)
declared = set()          # declared here, so its full surface is visible
conformances = collections.defaultdict(set)   # type -> protocols/bases it lists
# Capture any inheritance clause so protocol defaults can be credited to the
# conforming type. Without this, JackpotGame.lowestScoreWins looked
# unresolved: it is supplied by `extension SuiteGame`, not declared on the
# enum itself.
own_re  = re.compile(r'\b(?:struct|class|enum|protocol|actor)\s+([A-Za-z_]\w*)\s*(?::\s*([^{\n]+))?')
ext_re  = re.compile(r'\bextension\s+([A-Za-z_]\w*)')
# Backticks are allowed: `default`, `case`, `class` etc. are legal member
# names in Swift when escaped, and missing them produced a false positive on
# FreeRollPool.default.
mem_re  = re.compile(r'\b(?:static\s+)?(?:func|var|let)\s+`?([A-Za-z_]\w*)`?')
case_re = re.compile(r'\bcase\s+`?([A-Za-z_]\w*)`?')

for f in SOURCES:
    s = strip(open(f).read())
    for rx, is_own in ((own_re, True), (ext_re, False)):
        for m in rx.finditer(s):
            name = m.group(1)
            if is_own:
                declared.add(name)
                if m.lastindex and m.group(2):
                    for base in m.group(2).split(','):
                        base = base.strip().split('<')[0].strip()
                        if base: conformances[name].add(base)
            b = body_after(s, m.end())
            members[name] |= set(mem_re.findall(b)) | set(case_re.findall(b))

# Credit each type with whatever its protocols/bases provide, transitively.
for _ in range(4):   # depth cap; conformance chains here are 1-2 deep
    for name, bases in conformances.items():
        for base in bases:
            members[name] |= members.get(base, set())
            conformances[name] |= conformances.get(base, set()) - {name}

# Members the compiler synthesises or a stdlib protocol supplies.
SYNTH = {'allCases', 'rawValue', 'init', 'self', 'max', 'min', 'count',
         'hashValue', 'description', 'id'}

call_re = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\.([a-z][A-Za-z0-9_]*)')
bad = 0
for f in SOURCES:
    s = strip(open(f).read())
    for m in call_re.finditer(s):
        t, mem = m.group(1), m.group(2)
        if t not in declared or mem in SYNTH or mem in members[t]:
            continue
        line = s[:m.start()].count('\n') + 1
        have = ', '.join(sorted(members[t])[:8]) or '(nothing)'
        print(f"  UNRESOLVED  {os.path.relpath(f)}:{line}  {t}.{mem}\n"
              f"              {t} declares: {have}")
        bad += 1
print("qualified-call check:", "FAIL" if bad else "PASS", f"({bad} unresolved)")


# --- Non-escaping closure parameters captured by escaping closures ---------
#
# Swift refuses this, and nothing else in this tree could see it: it is a
# type-system rule rather than a shape or a name, so the balance scan and
# the resolver above both pass straight over it. It cost an iPad build once
# — RollbotsScreen.menuSheet called its @ViewBuilder parameter inside a
# GeometryReader, whose closure is stored and re-run on every layout pass,
# and so escapes.
#
# This is a textual heuristic, not a type checker. It finds the one shape
# that actually occurs here — a plain closure parameter invoked inside a
# nested closure in the same function — and claims nothing beyond that.

func_re = re.compile(r'\bfunc\s+\w+\s*(?:<[^>]*>)?\s*\(')
param_re = re.compile(r'(?:@ViewBuilder\s+)?(?:_\s+)?(\w+)\s*:\s*(@escaping\s+)?\(\s*\)\s*->')


def paren_span(src, i):
    """Text inside the parentheses opening at `i`, and the closing index."""
    depth = 0
    while i < len(src):
        if src[i] in '([':
            depth += 1
        elif src[i] in ')]':
            depth -= 1
            if depth == 0:
                return src[:i], i
        i += 1
    return '', i


escapes = 0
for f in SOURCES:
    s = strip(open(f).read())
    for m in func_re.finditer(s):
        open_paren = m.end() - 1
        sig, close = paren_span(s, open_paren)
        sig = sig[open_paren + 1:]
        # Only plain closure params: @escaping ones are allowed to be captured.
        names = [g[0] for g in param_re.findall(sig) if not g[1]]
        if not names:
            continue
        body = body_after(s, close)
        for name in names:
            for hit in re.finditer(r'\b%s\s*\(\s*\)' % re.escape(name), body):
                before = body[:hit.start()]
                # Brace depth 1 is the function body itself; deeper means the
                # call sits inside a closure the function hands to something
                # that may store it.
                depth = before.count('{') - before.count('}')
                if depth > 1:
                    line = s[:close].count('\n') + before.count('\n') + 1
                    print("  ESCAPING    %s:~%d  '%s' is non-escaping but is called "
                          "inside a nested closure" % (os.path.relpath(f), line, name))
                    escapes += 1
print("escaping-capture check:", "FAIL" if escapes else "PASS", "(%d captures)" % escapes)


# --- Half-merged files -----------------------------------------------------
#
# A merge can take half of a change and leave the rest, producing a file that
# references what it no longer declares. It happened twice to GameHubView.swift
# and nothing here saw it: the balance scan passes (braces still match), the
# resolver above passes (it only checks Type.member), and the result went to
# the device as three compiler errors.
#
# The signature is a name used in an element position but declared as a
# function that takes arguments — main's file said `title` on its own line
# while declaring `func title(width:)`. Zero hits across the tree when
# correct; one hit, at the exact line, on the broken file.

merged = 0
for f in SOURCES:
    s = strip(open(f).read())
    needs_args = {m.group(1) for m in
                  re.finditer(r'\bfunc\s+(\w+)\s*(?:<[^>]*>)?\s*\(\s*([^)])', s)}
    for m in re.finditer(r'^[ \t]*([a-z]\w*)[ \t]*$', s, re.M):
        if m.group(1) in needs_args:
            line = s[:m.start()].count('\n') + 1
            print("  HALF-MERGE  %s:%d  '%s' is used bare but declared with parameters"
                  % (os.path.relpath(f), line, m.group(1)))
            merged += 1
print("half-merge check:", "FAIL" if merged else "PASS", "(%d)" % merged)

# --- 4. Calls to something nothing declares --------------------------
#
# Deleting a function keeps every brace balanced, so the balance scan is
# blind to it — which is how `FloorMotif.polygon` went out with the old
# circuit tile it happened to sit next to, taking the whole file's
# geometry with it. Every builder still called it; nothing declared it.
#
# So: every lowercase name used as a call must be declared somewhere in
# the tree, or be one of the standard names below. The list is the price
# of the check and is meant to grow — a new standard-library call fails
# here once and is added, which is cheaper than a file that does not
# compile.
KNOWN = {
    # Swift keywords and contextual words that parse as `name(`
    "if", "for", "in", "case", "switch", "return", "init", "private",
    "fileprivate", "escaping",
    # standard library and Foundation
    "abs", "min", "max", "ceil", "floor", "round", "sqrt", "sin", "cos",
    "tan", "atan2", "pow", "stride", "zip", "print", "precondition",
    "assert", "fatalError", "withAnimation",
    # simd
    "simd_cross", "simd_dot", "simd_length", "simd_normalize",
    "simd_quatf", "simd_slerp", "simd_float3", "simd_float3x3",
    # UIKit and SwiftUI members reached without a receiver
    "getRed", "getHue", "dismiss", "overlay", "shadow", "content",
    # SwiftUI's ViewModifier plumbing. PixelPanel is the first thing here to
    # define one, which is exactly the case this list exists to absorb.
    "modifier", "inset",
    "selector", "build", "region", "special", "decided",
    # payload error cases, declared as `case name(...)` in their enums
    "scoreMismatch", "unknownGame", "unsupportedVersion",
    "valueOutOfRange", "wrongDieCount",
}

declared = set()
for f in SOURCES:
    text = open(f).read()
    declared |= set(re.findall(r'func\s+(\w+)\s*[(<]', text))
    declared |= set(re.findall(r'(?:let|var)\s+(\w+)\s*:\s*\(', text))
    declared |= set(re.findall(r'\bcase\s+(\w+)\s*\(', text))

undeclared = 0
for f in SOURCES:
    s = strip(open(f).read())
    for m in re.finditer(r'(?<![\w.$])([a-z]\w*)\s*\(', s):
        name = m.group(1)
        if name in declared or name in KNOWN:
            continue
        line = s[:m.start()].count('\n') + 1
        print("  UNDECLARED  %s:%d  '%s(' is called but nothing declares it "
              "(add it to KNOWN if it is a standard call)"
              % (os.path.relpath(f), line, name))
        undeclared += 1
print("undeclared-call check:", "FAIL" if undeclared else "PASS",
      "(%d)" % undeclared)


# --- render-thread delivery -------------------------------------------
#
# SceneKit calls renderer(_:updateAtTime:) on its OWN thread. Anything the
# roll controller raises from there reaches game code, and game code
# reaches SwiftUI: Rolls' recordSettledValue raises onStateChanged, which
# syncs a view's observed object.
#
# Touching SwiftUI or UIKit off the main thread raises no Swift error. It
# corrupts and dies with NOTHING printed — no "Fatal error" line, no
# exception, no console output at all. That silence is what made it cost
# several rounds: there was nothing to read.
#
# onRollComplete hopped to main from the start; onDieSettled did not,
# though the assembler describes the two as a pair "exactly that shape".
# This asserts they stay a pair.
#
# Checks DELIVERY, not subscribers, and that is the point. Nine places
# raise onStateChanged and two screens assign it — guarding subscribers
# means nine chances to forget. Guarding the one hand-off from the render
# thread means none.
RENDER_PATH_CALLBACKS = ["onDieSettled", "onRollComplete"]

render_bad = 0
_rc = [f for f in SOURCES if os.path.basename(f) == "DiceRollController.swift"]
if not _rc:
    print("  RENDER-THREAD  DiceRollController.swift is gone — this check "
          "no longer protects anything")
    render_bad += 1
else:
    _text = open(_rc[0]).read()
    for _name in RENDER_PATH_CALLBACKS:
        _idx, _seen = 0, 0
        while True:
            _at = _text.find("self?.%s?(" % _name, _idx)
            if _at < 0:
                break
            _idx, _seen = _at + 1, _seen + 1
            # Bounded look-back, so a hop belonging to an earlier and
            # unrelated block cannot be credited to this call.
            if "DispatchQueue.main.async" not in _text[max(0, _at - 700):_at]:
                print("  RENDER-THREAD  DiceRollController.swift:%d  %s is "
                      "raised on the render thread with no main-queue hop — "
                      "subscribers reach SwiftUI from it, and that dies "
                      "silently" % (_text[:_at].count("\n") + 1, _name))
                render_bad += 1
        if _seen == 0:
            print("  RENDER-THREAD  nothing raises %s any more — either it "
                  "is dead or this check names the wrong callback" % _name)
            render_bad += 1
print("render-thread check:", "FAIL" if render_bad else "PASS",
      "(%d)" % render_bad)


# --- static members resolve ------------------------------------------
#
# A fold deletes a file and moves its contents into another. If a LATER
# commit then modifies the deleted file, git applies the rest of that
# commit and drops that one hunk — no conflict, no marker, no warning.
# That is how PixelPanel.cellOutline and .cellBevel went missing: the
# re-fold was taken from the commit where the conflict surfaced rather
# than from the last commit that touched the file, and nothing anywhere
# said so until the device refused to compile.
#
# Silence is what makes that the worst failure mode this project has
# hit — worse than the crash, which at least had a trace once asked. So:
# every `Type.member` where Type is declared in this tree must resolve.
#
# STATICS ONLY, deliberately. Instance members arrive from protocol
# conformances — View, ViewModifier — and a check that tried to model
# Swift's conformance rules would be wrong often enough to be ignored,
# which is the one thing a guard must never be. Nothing here takes a
# static from a protocol, so statics resolve exactly.
#
# It cannot catch a wrong ARGUMENT LIST ("extra arguments at position
# #4") — that needs signature matching, which is a type-checker's job.
# But that error shares this root cause, so what this catches is enough
# to catch the cause.
member_bad = 0

# Swift builtins reachable on any metatype — not declared anywhere.
_BUILTIN_MEMBERS = {"self", "init", "type", "some"}

# Statics that standard-library protocols supply. The conformance walk
# below only sees protocols declared in this tree, so the handful that
# come from the stdlib are listed here rather than inferred — a short,
# honest list beats a clever rule that is wrong in a way nobody checks.
_STDLIB_STATICS = {
    "CaseIterable": {"allCases"},
}

_decls = {}          # type name -> set of static member names
_conforms = {}       # type name -> set of protocol/base names
for f in SOURCES:
    src = strip(open(f).read())
    for m in re.finditer(
            r'^(?:public |private |fileprivate |internal |final |@\w+ )*'
            r'(?:struct|class|enum|protocol|extension)\s+(\w+)'
            r'\s*(?::\s*([^{\n]+))?', src, re.M):
        name, inherits = m.group(1), (m.group(2) or "")
        body = body_after(src, m.end())
        members = set(re.findall(r'static\s+(?:let|var|func)\s+`?(\w+)`?', body))
        members |= set(re.findall(r'^\s*case\s+`?(\w+)`?', body, re.M))
        _decls.setdefault(name, set()).update(members)
        # `: Foo, Bar` after a type name is conformance (or a raw value).
        for base in re.findall(r'\b([A-Z]\w*)', inherits):
            _conforms.setdefault(name, set()).add(base)

def _statics(tname, seen=None):
    """Everything reachable as a static on this type.

    Includes what its protocols declare and what extensions on those
    protocols default — SuiteGame supplies floorTitle and
    lowestScoreWins that way, and treating them as missing was how the
    first draft of this check produced 49 false positives on a tree that
    compiles. A guard that cries wolf is one that gets ignored, so the
    conformance walk is the difference between this being useful and
    being noise.
    """
    seen = seen or set()
    if tname in seen:
        return set()
    seen.add(tname)
    out = set(_decls.get(tname, ()))
    for base in _conforms.get(tname, ()):
        out |= _STDLIB_STATICS.get(base, set())
        out |= _statics(base, seen)
    return out

for f in SOURCES:
    src = strip(open(f).read())
    for m in re.finditer(r'\b([A-Z]\w*)\.([a-z]\w*)', src):
        tname, member = m.group(1), m.group(2)
        if member in _BUILTIN_MEMBERS:
            continue
        if tname not in _decls:
            continue                      # not a type we declare
        known = _statics(tname)
        if not known or member in known:
            continue
        print("  MEMBER  %s:%d  '%s.%s' — %s declares no static '%s'"
              % (os.path.relpath(f), src[:m.start()].count("\n") + 1,
                 tname, member, tname, member))
        member_bad += 1
print("static-member check:", "FAIL" if member_bad else "PASS",
      "(%d)" % member_bad)

# ---------------------------------------------------------------------
# 7. Inference hazard: a generic `map` nested inside another closure's
#    `map`, in one expression.
#
# Stage D built on the iPad up to D2 and failed at D3 with an EMPTY
# diagnostics pane and an EMPTY console — no red line, no trap. The only
# novel type-inference shape in that delta was one line:
#
#     let toneKey = tones.map { $0.map(\.description).joined(separator: ",") } ?? "-"
#
# `tones` is `[UIColor]?`, so the outer `map` is Optional.map; the inner
# one is Sequence.map with a key-path-as-function whose root has to be
# inferred through it; `joined(separator:)` has two overloads that both
# admit the result; and `?? "-"` wraps the lot, with no annotation on
# `toneKey` to anchor any of it. Every one of those is cheap alone. In
# one expression they multiply.
#
# Why this check and not the type-check heuristic that already exists:
# `tools_typecheck_verify.py` scores `var body: some View` blocks only,
# and this line is in a plain static function, so that guard could never
# have seen it. Scored expressions and scored view bodies are different
# problems and want different checks.
#
# Key-path-as-function on its own is NOT flagged: the tree has fifteen of
# them and stage C, which builds, carries all fifteen. The nesting is
# what is new, and the nesting is what this looks for.
#
# The remedy is always the same and never changes behaviour: give the
# local an explicit type, or write the loop out. A loop whose element
# type is stated costs the solver nothing.
nested_bad = 0
NEST = re.compile(r'\.(?:map|compactMap|flatMap)\s*(?:\{|\()')
for f in SOURCES:
    raw = open(f).read()
    for n, line in enumerate(raw.split("\n"), 1):
        code = strip(line)
        # A closure opened and closed on this line, with a second
        # map-family call inside it.
        for m in re.finditer(r'\.(?:map|compactMap|flatMap)\s*\{', code):
            tail = code[m.end():]
            close = tail.find('}')
            if close == -1:
                continue                  # closure runs past this line
            if NEST.search(tail[:close]):
                print("  NESTED-MAP  %s:%d  a map-family call nested inside "
                      "another's closure in one expression — annotate the "
                      "local or write the loop out\n              %s"
                      % (os.path.relpath(f), n, code.strip()[:88]))
                nested_bad += 1
                break
print("inference-hazard check:", "FAIL" if nested_bad else "PASS",
      "(%d)" % nested_bad)

# ---------------------------------------------------------------------
# 8. Antialiasing: every scene must take its mode from SceneAntialiasing,
#    never from a literal.
#
# Two unrelated reasons want the same answer, which is exactly why the
# decision belongs in one enum rather than at three call sites:
#
#   * The LOOK. 4x MSAA smooths every die's silhouette, which is the one
#     thing that keeps a stippled, posterised, hard-outlined tray from
#     reading as pixel art. The faces were already chunky and the edges
#     were still soft, and the edges are what the eye reads first.
#   * The SIMULATOR, where any multisampling sets up a multisampled DEPTH
#     attachment it cannot resolve, and the validation layer aborts the
#     process mid-frame:
#         MTLStoreActionMultisampleResolve ... is not supported by device
#         MTLPixelFormatDepth32Float cannot be a MSAA resolve target
#
# Three call sites that must agree is how they stop agreeing — the lesson
# OverlayChromeButton taught when the restyle landed on ten screens and
# missed the eleventh. So: no file may write a multisampling literal, and
# every scene that sets a mode must route through the enum.
aa_bad = 0
AA_ENUM = "SceneAntialiasing"
for f in SOURCES:
    name = os.path.basename(f)
    src_f = strip(open(f).read())
    for m in re.finditer(r'\.multisampling\w*', src_f):
        if name == "DiceSceneEnvironment.swift":
            continue                  # the enum itself may name the modes
        print("  ANTIALIAS   %s:%d  '%s' written as a literal — take it from "
              "%s.mode instead, so three scenes cannot drift apart"
              % (os.path.relpath(f), src_f[:m.start()].count("\n") + 1,
                 m.group(0), AA_ENUM))
        aa_bad += 1
    if re.search(r'antialiasingMode\s*[:=]', src_f) and AA_ENUM not in src_f:
        print("  ANTIALIAS   %s  sets an antialiasing mode without going "
              "through %s" % (os.path.relpath(f), AA_ENUM))
        aa_bad += 1
print("antialiasing check:", "FAIL" if aa_bad else "PASS", "(%d)" % aa_bad)

# ---------------------------------------------------------------------
# 9. Render scale: every scene takes it from SceneRenderScale.
#
# The same shape as the antialiasing check above, and for the same reason —
# scenes that must agree are how they stop agreeing. It is worth its own
# check rather than folding into that one because the failure is different:
# antialiasing drifting makes one tray smoother than another, where this
# drifting makes one tray a DIFFERENT PIXEL SIZE than another, and a pixel
# grid that changes between screens is worse than no grid at all.
#
# Both halves of SceneRenderScale.apply are load-bearing and neither works
# alone: a low contentScaleFactor renders coarse and then the layer smooths
# it back up on display, which is blur rather than pixel art. So the check
# rejects a bare contentScaleFactor as firmly as it rejects a literal.
scale_bad = 0
for f in SOURCES:
    name = os.path.basename(f)
    src_f = strip(open(f).read())
    if name == "DiceSceneEnvironment.swift":
        continue                      # the enum itself
    for m in re.finditer(r'\.contentScaleFactor\s*=', src_f):
        print("  RENDERSCALE %s:%d  sets contentScaleFactor directly — take "
              "it from SceneRenderScale.apply(to:), which also sets the "
              "magnification filter the coarse pass is useless without"
              % (os.path.relpath(f), src_f[:m.start()].count("\n") + 1))
        scale_bad += 1
    if "antialiasingMode = SceneAntialiasing.mode" in src_f \
            and "SceneRenderScale.apply" not in src_f:
        print("  RENDERSCALE %s  is a scene view that takes the shared "
              "antialiasing but not the shared render scale — it would "
              "render at a different pixel size from every other tray"
              % os.path.relpath(f))
        scale_bad += 1
print("render-scale check:", "FAIL" if scale_bad else "PASS", "(%d)" % scale_bad)

sys.exit(1 if bad or escapes or merged or undeclared or render_bad or member_bad or nested_bad or aa_bad or scale_bad else 0)
