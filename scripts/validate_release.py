#!/usr/bin/env python3
"""Validate SignatureGate JSON assets and release metadata."""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]


def validate_assets() -> None:
    failures = []
    for path in sorted(ROOT.rglob("*.json")):
        if ".git" in path.parts:
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            failures.append(f"{path.relative_to(ROOT)}: {exc}")
    if failures:
        raise SystemExit("Invalid JSON:\n- " + "\n- ".join(failures))


def validate_release() -> None:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    failures = []
    if not re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?", version):
        failures.append("VERSION is not semantic versioning")
    if f"Current version: **{version}**." not in (ROOT / "README.md").read_text(encoding="utf-8"):
        failures.append("README.md version does not match VERSION")
    changelog = (ROOT / "docs/CHANGELOG.md").read_text(encoding="utf-8")
    if not re.search(rf"^## \[v{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}$", changelog, re.M):
        failures.append("docs/CHANGELOG.md has no dated heading for VERSION")
    if not (ROOT / f"releases/v{version}/RELEASE_NOTES.md").exists():
        failures.append("versioned release notes are missing")
    if failures:
        raise SystemExit("Release check failed:\n- " + "\n- ".join(failures))


parser = argparse.ArgumentParser()
parser.add_argument("--assets", action="store_true")
args = parser.parse_args()
validate_assets()
if not args.assets:
    validate_release()
