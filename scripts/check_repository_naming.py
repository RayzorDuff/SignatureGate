#!/usr/bin/env python3
"""Reject issue-numbered file/directory names and make targets, not code identifiers."""
import argparse
from pathlib import Path
import re
import subprocess

ISSUE_NUMBER = re.compile(r'issues?[-_ ]*\d', re.IGNORECASE)


def check(repository):
    root = Path(repository).resolve()
    paths = subprocess.check_output(
        ['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        text=True,
    ).split('\0')
    failures = []
    for name in sorted(set(filter(None, paths))):
        path = root / name
        if not path.is_file():
            continue  # A removed file may still be in the index until commit.
        if any(ISSUE_NUMBER.search(part) for part in Path(name).parts):
            failures.append(f'{name}: use a functional name without an issue number')
        if path.name.lower() in {'makefile', 'gnumakefile'} or path.suffix == '.mk':
            for number, line in enumerate(path.read_text().splitlines(), 1):
                rule = re.match(r'^([^#\s][^:=]*):(?!=)', line)
                if rule:
                    for target in rule.group(1).split():
                        if ISSUE_NUMBER.search(target):
                            failures.append(f'{name}:{number}: target {target} must describe its function')
    return failures


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', default=str(Path(__file__).resolve().parents[1]))
    args = parser.parse_args()
    failures = check(args.repository)
    for failure in failures:
        print(failure)
    raise SystemExit(bool(failures))
