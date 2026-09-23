#!/usr/bin/env python3
"""Validate SignatureGate JSON assets and release metadata."""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]


def validate_givebutter_workflow(path: pathlib.Path, data: dict, failures: list[str]) -> None:
    """Guard the provider-identity bind type used by the Givebutter webhook."""
    if data.get("name") != "SignatureGate - Givebutter - Webhook Transactions":
        return

    relative_path = path.relative_to(ROOT)
    nodes = {node.get("name"): node for node in data.get("nodes", [])}
    normalize = nodes.get("Normalize Transaction", {})
    postgres = nodes.get("PG - Insert Donation + Audit", {})
    normalize_code = normalize.get("parameters", {}).get("jsCode", "")
    query = postgres.get("parameters", {}).get("query", "")

    if "provider_identity" not in normalize_code or "data.contact_id.toString()" not in normalize_code:
        failures.append(
            f"{relative_path}: Givebutter contact_id must be normalized to a text provider_identity"
        )

    provider_identity_call = re.search(
        r"p_provider_identity\s*=>[^\n]*\$\d+::text", query
    )
    if not provider_identity_call:
        failures.append(
            f"{relative_path}: ingest_provider_donation provider identity bind must be explicitly cast to text"
        )


def validate_appsmith_export(path: pathlib.Path, data: dict, failures: list[str]) -> None:
    """Catch drift between Appsmith JS actions and their combined JS objects."""
    if not {"actionList", "actionCollectionList", "pageList"}.issubset(data):
        return

    collections = {
        collection.get("id"): collection
        for collection in data.get("actionCollectionList", [])
    }
    relative_path = path.relative_to(ROOT)

    for collection in collections.values():
        published = collection.get("publishedCollection", {})
        unpublished = collection.get("unpublishedCollection", {})
        if published.get("body") != unpublished.get("body"):
            failures.append(
                f"{relative_path}: published/unpublished JS collection drift for "
                f"{unpublished.get('pageId')}/{unpublished.get('name')}"
            )

    for action in data.get("actionList", []):
        if action.get("pluginType") != "JS":
            continue

        published = action.get("publishedAction", {})
        unpublished = action.get("unpublishedAction", {})
        page_id = unpublished.get("pageId")
        name = unpublished.get("name")
        collection_id = unpublished.get("collectionId")
        published_body = published.get("actionConfiguration", {}).get("body")
        unpublished_body = unpublished.get("actionConfiguration", {}).get("body")

        if published_body != unpublished_body:
            failures.append(
                f"{relative_path}: published/unpublished JS action drift for "
                f"{page_id}/{name}"
            )

        for label, variant, body in (
            ("published", published, published_body),
            ("unpublished", unpublished, unpublished_body),
        ):
            if body and variant.get("jsonPathKeys") != [body]:
                failures.append(
                    f"{relative_path}: stale {label} JS metadata for {page_id}/{name}"
                )

        if not collection_id:
            continue
        collection = collections.get(collection_id)
        if not collection:
            failures.append(
                f"{relative_path}: missing JS collection {collection_id} for "
                f"{page_id}/{name}"
            )
            continue

        method_pattern = re.compile(
            rf"^[ \t]*(?:async[ \t]+)?{re.escape(str(name))}[ \t]*\(",
            re.MULTILINE,
        )
        for label, variant_name in (
            ("published", "publishedCollection"),
            ("unpublished", "unpublishedCollection"),
        ):
            collection_body = collection.get(variant_name, {}).get("body", "")
            if not method_pattern.search(collection_body):
                failures.append(
                    f"{relative_path}: {label} JS collection is missing method "
                    f"{page_id}/{name}"
                )


def validate_assets() -> None:
    failures = []
    for path in sorted(ROOT.rglob("*.json")):
        if ".git" in path.parts:
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                validate_appsmith_export(path, data, failures)
                validate_givebutter_workflow(path, data, failures)
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
