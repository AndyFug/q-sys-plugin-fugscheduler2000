#!/usr/bin/env python3
"""Small local include compiler for FugScheduler 2000.

This is not a replacement for the official Q-SYS Plugin Compiler; it only handles
recursive lines of the form:

  --[[ #include "file.lua" ]]

It lets us keep src/ as the source of truth in this dev container and generate a
single .qplug for review/testing. Official Windows/Q-SYS compiler validation is
still required before release.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

INCLUDE_RE = re.compile(r'^(\s*)--\[\[\s*#include\s+"([^"]+)"\s*\]\]\s*$')
VERSION_RE = re.compile(r'(\bVersion\s*=\s*")(\d+\.\d+\.\d+)(")')
BUILD_VERSION_RE = re.compile(r'(\bBuildVersion\s*=\s*")(\d+\.\d+\.\d+\.\d+)(")')
BUILD_DATE_RE = re.compile(r'(\bBuildDate\s*=\s*")([^"]+)(")')
BUILD_TIMESTAMP_RE = re.compile(r'(\bBuildTimestamp\s*=\s*)(\d+)')


def compile_file(path: Path, seen: list[Path] | None = None) -> str:
    path = path.resolve()
    seen = seen or []
    if path in seen:
        chain = " -> ".join(str(p) for p in [*seen, path])
        raise RuntimeError(f"Recursive include detected: {chain}")

    output: list[str] = []
    for line in path.read_text().splitlines(keepends=True):
        match = INCLUDE_RE.match(line)
        if match:
            indent = match.group(1)
            include_path = path.parent / match.group(2)
            included = compile_file(include_path, [*seen, path])
            if indent:
                included = "".join(
                    indent + included_line if included_line.strip() else included_line
                    for included_line in included.splitlines(keepends=True)
                )
            output.append(included)
            if output[-1] and not output[-1].endswith("\n"):
                output.append("\n")
        else:
            output.append(line)
    return "".join(output)


def replace_metadata_value(text: str, pattern: re.Pattern[str], value: str, label: str) -> str:
    """Replace exactly one Lua metadata value while preserving its surrounding syntax."""
    updated, count = pattern.subn(lambda match: match.group(1) + value + (match.group(3) if match.lastindex == 3 else ""), text, count=1)
    if count != 1:
        raise RuntimeError(f"Expected exactly one {label} field")
    return updated


def prepare_new_build(root: Path) -> tuple[str, str, int, tuple[Path, str], tuple[Path, str]]:
    """Increment the development build and synchronise canonical UTC metadata sources."""
    info_path = root / "src/info.lua"
    runtime_path = root / "src/runtime.lua"
    old_info = info_path.read_text()
    old_runtime = runtime_path.read_text()

    version_match = VERSION_RE.search(old_info)
    build_match = BUILD_VERSION_RE.search(old_info)
    if not version_match or not build_match:
        raise RuntimeError("src/info.lua must define Version and four-part BuildVersion fields")

    version = version_match.group(2)
    build_parts = build_match.group(2).split(".")
    if ".".join(build_parts[:3]) != version:
        raise RuntimeError("BuildVersion first three components must match Version")
    next_build = ".".join([*build_parts[:3], str(int(build_parts[3]) + 1)])

    now = datetime.now(timezone.utc).replace(microsecond=0)
    build_date = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    build_timestamp = int(now.timestamp())

    new_info = replace_metadata_value(old_info, BUILD_VERSION_RE, next_build, "BuildVersion")
    new_info = replace_metadata_value(new_info, BUILD_DATE_RE, build_date, "BuildDate")
    new_info = replace_metadata_value(new_info, BUILD_TIMESTAMP_RE, str(build_timestamp), "BuildTimestamp")
    new_runtime = replace_metadata_value(old_runtime, BUILD_DATE_RE, build_date, "runtime BuildDate")
    new_runtime = replace_metadata_value(
        new_runtime, BUILD_TIMESTAMP_RE, str(build_timestamp), "runtime BuildTimestamp"
    )

    info_path.write_text(new_info)
    runtime_path.write_text(new_runtime)
    return next_build, build_date, build_timestamp, (info_path, old_info), (runtime_path, old_runtime)


def default_deploy_dir() -> Path | None:
    env_dir = os.environ.get("QSYS_PLUGIN_DIR")
    if env_dir:
        return Path(env_dir).expanduser()

    mounted_dir = Path("/qsys-plugins")
    if mounted_dir.exists():
        return mounted_dir

    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Compile FugScheduler 2000 source includes into a .qplug file")
    parser.add_argument("--input", default="src/plugin.lua", help="Source plugin shell, relative to project root")
    parser.add_argument("--output", default="FugScheduler2000.qplug", help="Output qplug path, relative to project root")
    parser.add_argument(
        "--deploy",
        action="store_true",
        help="Copy the generated qplug to QSYS_PLUGIN_DIR, or /qsys-plugins if that mount exists",
    )
    parser.add_argument(
        "--new-build",
        action="store_true",
        help="Increment BuildVersion and set matching UTC BuildDate/BuildTimestamp before compiling",
    )
    parser.add_argument(
        "--deploy-dir",
        help="Copy the generated qplug to this directory after compiling; implies --deploy",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    source = root / args.input
    output = root / args.output

    metadata_backups: tuple[tuple[Path, str], tuple[Path, str]] | None = None
    if args.new_build:
        next_build, build_date, build_timestamp, info_backup, runtime_backup = prepare_new_build(root)
        metadata_backups = (info_backup, runtime_backup)
        print(f"Prepared build {next_build} at {build_date} ({build_timestamp})")

    try:
        output.write_text(compile_file(source))
    except Exception:
        if metadata_backups:
            for path, original in metadata_backups:
                path.write_text(original)
        raise
    print(f"Compiled {source.relative_to(root)} -> {output.relative_to(root)}")

    if args.deploy or args.deploy_dir:
        deploy_dir = Path(args.deploy_dir).expanduser() if args.deploy_dir else default_deploy_dir()
        if deploy_dir is None:
            raise SystemExit(
                "Deploy requested, but no deploy directory was provided. "
                "Set QSYS_PLUGIN_DIR, mount the host plugin directory at /qsys-plugins, "
                "or pass --deploy-dir."
            )
        deploy_dir.mkdir(parents=True, exist_ok=True)
        destination = deploy_dir / output.name
        shutil.copy2(output, destination)
        print(f"Deployed {output.name} -> {destination}")


if __name__ == "__main__":
    main()
