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
from pathlib import Path

INCLUDE_RE = re.compile(r'^(\s*)--\[\[\s*#include\s+"([^"]+)"\s*\]\]\s*$')


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
        "--deploy-dir",
        help="Copy the generated qplug to this directory after compiling; implies --deploy",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    source = root / args.input
    output = root / args.output

    output.write_text(compile_file(source))
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
