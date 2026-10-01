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

sys.exit(1 if bad or escapes or merged or undeclared or render_bad else 0)
