#!/usr/bin/env python3
"""Block migrations that can wipe hosted data unless Marc explicitly allows them."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"
ALLOW_MARKER = "-- allow-destructive"

FORBIDDEN = re.compile(
    r"""
    \b(
        drop\s+table\b
        | drop\s+schema\b
        | drop\s+database\b
        | drop\s+column\b
        | truncate\s+
    )
    """,
    re.IGNORECASE | re.VERBOSE,
)


def without_comments(sql: str) -> str:
    sql = re.sub(r"--.*?$", "", sql, flags=re.MULTILINE)
    return re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)


def first_line_allows_destructive(text: str) -> bool:
    if not text:
        return False
    first = text.lstrip("\ufeff").splitlines()[0].strip()
    return first == ALLOW_MARKER


def is_blocked(text: str) -> bool:
    if first_line_allows_destructive(text):
        return False
    return FORBIDDEN.search(without_comments(text)) is not None


def selftest() -> None:
    assert is_blocked("drop table public.fights;")
    assert is_blocked("TRUNCATE public.fights;")
    assert is_blocked("alter table public.fights\n\n  drop column name;")
    assert not is_blocked(f"{ALLOW_MARKER}\ndrop table public.fights;")
    assert is_blocked(f"select 1;\n{ALLOW_MARKER}\ndrop table public.fights;")
    assert is_blocked(f"/* {ALLOW_MARKER} */\ndrop table public.fights;")
    assert not is_blocked("create table public.fights (id uuid);")


def main() -> int:
    selftest()
    if not MIGRATIONS.is_dir():
        print("no supabase/migrations directory", file=sys.stderr)
        return 1

    blocked: list[str] = []
    paths = [*MIGRATIONS.glob("*.sql"), *(ROOT / "supabase" / "deferred-migrations").glob("*.sql")]
    for path in sorted(paths):
        if is_blocked(path.read_text()):
            blocked.append(path.name)

    if blocked:
        print("Destructive SQL is blocked:", ", ".join(blocked))
        print(
            "Use an additive migration. If Marc asked to drop data in this chat, "
            f"the file must start with: {ALLOW_MARKER}"
        )
        return 1

    print("migrations ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
