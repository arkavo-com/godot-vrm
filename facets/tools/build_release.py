#!/usr/bin/env python3
"""Builds FACETS release archives into build/.

  facets-addon-<version>.zip     addons/facets only (core + editor plugin)
  facets-ai-<version>.zip        optional addons/facets_ai
  facets-combat-<version>.zip    optional addons/facets_combat
  facets-examples-<version>.zip  example project (all addons, demo, tests, docs)

Caches and build output are never included. The development-only editor
self-test plugin ships only in the example project (which also contains the
tests and tools that use it), never in the addon archives. No publishing
happens here.
Usage: python3 tools/build_release.py
"""
import configparser
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
EXCLUDE_DIRS = {".godot", ".import", "build", "__pycache__", ".tmp"}
EXCLUDE_SUFFIXES = {".pyc", ".tmp", ".bak"}


def version():
    parser = configparser.ConfigParser()
    parser.read(ROOT / "addons" / "facets" / "plugin.cfg")
    return parser["plugin"]["version"].strip('"')


def files_under(relative):
    base = ROOT / relative
    for path in sorted(base.rglob("*")):
        parts = set(path.relative_to(ROOT).parts)
        if path.is_dir() or parts & EXCLUDE_DIRS or path.suffix in EXCLUDE_SUFFIXES:
            continue
        yield path


def write_zip(name, entries, extra=()):
    BUILD.mkdir(exist_ok=True)
    target = BUILD / name
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in entries:
            info = zipfile.ZipInfo(str(path.relative_to(ROOT)), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
        for arcname, data in extra:
            info = zipfile.ZipInfo(arcname, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    count = len(zipfile.ZipFile(target).namelist())
    print("%-32s %4d files  %8d bytes" % (name, count, target.stat().st_size))
    return target


def main():
    v = version()
    notice = (ROOT / "docs" / "release-notice.txt").read_bytes()
    write_zip("facets-addon-%s.zip" % v, files_under("addons/facets"), [("addons/facets/RELEASE-NOTICE.txt", notice)])
    write_zip("facets-ai-%s.zip" % v, files_under("addons/facets_ai"), [("addons/facets_ai/OPTIONAL.txt", b"Optional FACETS AI adapter. Requires addons/facets.\n")])
    write_zip("facets-combat-%s.zip" % v, files_under("addons/facets_combat"), [("addons/facets_combat/OPTIONAL.txt", b"Optional FACETS combat package. Requires addons/facets.\n")])
    project = []
    for relative in ["project.godot", "README.md", "CHANGELOG.md", ".gitignore"]:
        project.append(ROOT / relative)
    for relative in ["addons/facets", "addons/facets_ai", "addons/facets_combat", "addons/facets_editor_selftest", "examples", "schemas", "tests", "docs", "tools"]:
        project.extend(files_under(relative))
    write_zip("facets-examples-%s.zip" % v, project)


if __name__ == "__main__":
    main()
