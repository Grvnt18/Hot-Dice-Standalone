"""Scope-aware check: for every `Type.member` call, confirm `member` is
declared INSIDE that type's own brace range.

Replaces a plain substring grep, which happily reported `static func
stackSans` as resolving even though it lives in `extension Font`, not in
`enum AppFonts`.

Only types DECLARED in this module are checked. A type we merely extend
(Color, UIColor, Font) gets most of its members from the framework, which
isn't visible here, so checking those would be all false positives."""
import re, sys, glob, collections

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
# conforming type. Without this, ChasingSixGame.lowestScoreWins looked
# unresolved: it is supplied by `extension SuiteGame`, not declared on the
# enum itself.
own_re  = re.compile(r'\b(?:struct|class|enum|protocol|actor)\s+([A-Za-z_]\w*)\s*(?::\s*([^{\n]+))?')
ext_re  = re.compile(r'\bextension\s+([A-Za-z_]\w*)')
# Backticks are allowed: `default`, `case`, `class` etc. are legal member
# names in Swift when escaped, and missing them produced a false positive on
# FreeRollPool.default.
mem_re  = re.compile(r'\b(?:static\s+)?(?:func|var|let)\s+`?([A-Za-z_]\w*)`?')
case_re = re.compile(r'\bcase\s+`?([A-Za-z_]\w*)`?')

for f in glob.glob('*.swift'):
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
for f in sorted(sys.argv[1:] or glob.glob('*.swift')):
    s = strip(open(f).read())
    for m in call_re.finditer(s):
        t, mem = m.group(1), m.group(2)
        if t not in declared or mem in SYNTH or mem in members[t]:
            continue
        line = s[:m.start()].count('\n') + 1
        have = ', '.join(sorted(members[t])[:8]) or '(nothing)'
        print(f"  UNRESOLVED  {f}:{line}  {t}.{mem}\n"
              f"              {t} declares: {have}")
        bad += 1
print("qualified-call check:", "FAIL" if bad else "PASS", f"({bad} unresolved)")
sys.exit(1 if bad else 0)
