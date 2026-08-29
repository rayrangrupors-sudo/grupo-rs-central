#!/usr/bin/env python3
"""Remove nomenclatura legada de nuvem do código ativo e testes locais."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(r"C:\GRUPO RS CENTRAL\app")
SKIP_DIRS = {".git", ".godot", "backups", "outputs", "tmp", "dist", "build", "artifacts", "data", "runtime", "node_modules"}
TEXT_SUFFIXES = {".gd", ".tscn", ".godot", ".md", ".cfg", ".txt", ".ps1", ".py", ".cmd", ".html", ".uid"}


def improve_visible_text(line: str) -> str:
    def quoted(match: re.Match[str]) -> str:
        value = match.group(0)
        return value.replace("Banco local SQL", "Banco local SQL")

    line = re.sub(r'"(?:[^"\\]|\\.)*"', quoted, line)
    if "#" in line:
        code, comment = line.split("#", 1)
        line = code + "#" + comment.replace("Banco local SQL", "Banco local SQL")
    return line


def migrate_text(path: Path) -> bool:
    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False
    updated = original
    replacements = [
        ("banco SQLite local", "banco SQLite local"),
        ("banco SQLite local", "banco SQLite local"),
        ("LocalSQLiteDatabase", "LocalSQLiteDatabase"),
        ("SQLITE", "SQLITE"),
        ("SQLite", "SQLite"),
        ("sqlite", "sqlite"),
        ("BANCO_LOCAL_SQL", "BANCO_LOCAL_SQL"),
        ("Banco local SQL", "Banco local SQL"),
        ("local_database", "local_database"),
    ]
    for old, new in replacements:
        updated = updated.replace(old, new)
    updated = "\n".join(improve_visible_text(line) for line in updated.split("\n"))
    if updated == original:
        return False
    path.write_text(updated, encoding="utf-8", newline="")
    return True


def eligible(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    return not any(part in SKIP_DIRS for part in relative.parts[:-1]) and path.suffix.lower() in TEXT_SUFFIXES


def main() -> None:
    changed = []
    for path in ROOT.rglob("*"):
        if path.is_file() and eligible(path) and migrate_text(path):
            changed.append(str(path.relative_to(ROOT)))

    renamed = []
    candidates = [p for p in ROOT.rglob("*") if p.is_file() and eligible(p) and re.search("local_database|sqlite", p.name, re.I)]
    for source in sorted(candidates, key=lambda p: len(p.parts), reverse=True):
        new_name = re.sub("local_database", "local_database", source.name, flags=re.I)
        new_name = re.sub("sqlite", "sqlite", new_name, flags=re.I)
        target = source.with_name(new_name)
        if target.exists():
            raise RuntimeError(f"Destino já existe: {target}")
        source.rename(target)
        renamed.append(f"{source.relative_to(ROOT)} -> {target.relative_to(ROOT)}")

    print(f"changed_files={len(changed)} renamed_files={len(renamed)}")
    for item in renamed:
        print(item)


if __name__ == "__main__":
    main()
