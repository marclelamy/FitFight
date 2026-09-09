"""Keep application database access behind the backend; native Auth remains direct."""

from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
forbidden = re.compile(r"\.(?:from|rpc|schema)\s*\(|/rest/v1|\bimport\s+PostgREST\b")
violations = []
for path in sorted((root / "FitFight").rglob("*.swift")):
    source = path.read_text()
    for match in forbidden.finditer(source):
        line = source.count("\n", 0, match.start()) + 1
        violations.append(f"{path.relative_to(root)}:{line}: {match.group()}")
if violations:
    print("Native database access must use FitFightAPI:\n" + "\n".join(violations), file=sys.stderr)
    sys.exit(1)
print("Native database access uses the backend")
