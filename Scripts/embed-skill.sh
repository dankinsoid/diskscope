#!/bin/sh
# Embeds skills/diskscope/SKILL.md into the binary, so an installed dscope can
# write it out with "dscope skill" without needing the repository.
set -e
cd "$(dirname "$0")/.."
python3 - <<'PY'
text = open('skills/diskscope/SKILL.md').read()
escaped = text.replace('\\', '\\\\').replace('"""', '\\"\\"\\"')
open('Sources/dscope/Generated/SkillContents.swift', 'w').write(
    '// Generated from skills/diskscope/SKILL.md by Scripts/embed-skill.sh\n'
    '// Edit that file, not this one.\n\n'
    'extension Skill {\n\n'
    '    /// The skill text, embedded so an installed binary carries it.\n'
    '    static let contents = """\n'
    + escaped + '"""\n}\n'
)
PY
echo "embedded $(wc -l < skills/diskscope/SKILL.md) lines"
