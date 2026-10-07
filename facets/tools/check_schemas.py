#!/usr/bin/env python3
"""Validates FACETS JSON Schemas and their positive/negative fixtures.

Development-only check (requires the `jsonschema` package, 4.18+).
Every file in tests/fixtures/schemas/<type>/valid must validate against
schemas/<type>.schema.json and every file in .../invalid must fail.
Usage: python3 tools/check_schemas.py
"""
import json
import pathlib
import sys

from jsonschema import Draft202012Validator
from referencing import Registry, Resource

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
FIXTURES = ROOT / "tests" / "fixtures" / "schemas"


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def main():
    schemas = {path.name: load(path) for path in sorted(SCHEMAS.glob("*.schema.json"))}
    registry = Registry()
    for schema in schemas.values():
        Draft202012Validator.check_schema(schema)
        registry = registry.with_resource(schema["$id"], Resource.from_contents(schema))
    ai_copy = load(ROOT / "addons" / "facets_ai" / "proposal.schema.json")
    failures = []
    if ai_copy != schemas["proposal.schema.json"]:
        failures.append("addons/facets_ai/proposal.schema.json differs from schemas/proposal.schema.json")
    checked = 0
    for kind_dir in sorted(p for p in FIXTURES.iterdir() if p.is_dir()):
        schema = schemas.get(kind_dir.name + ".schema.json")
        if schema is None:
            failures.append("no schema for fixture directory %s" % kind_dir.name)
            continue
        validator = Draft202012Validator(schema, registry=registry)
        for expectation in ("valid", "invalid"):
            files = sorted((kind_dir / expectation).glob("*.json"))
            if not files:
                failures.append("%s/%s has no fixtures" % (kind_dir.name, expectation))
            for path in files:
                checked += 1
                errors = list(validator.iter_errors(load(path)))
                if expectation == "valid" and errors:
                    failures.append("%s should be valid: %s" % (path.relative_to(ROOT), errors[0].message[:300]))
                if expectation == "invalid" and not errors:
                    failures.append("%s should be invalid but passed" % path.relative_to(ROOT))
    for message in failures:
        print("FAIL", message)
    print("check_schemas: %d schemas, %d fixtures, %d failures" % (len(schemas), checked, len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
