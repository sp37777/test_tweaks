#!/usr/bin/env python3
"""Update winutil.ps1 from the latest ChrisTitusTech/winutil GitHub release.

Thin wrapper around update_github.py: it only says *what* to update. Download,
integrity checks, numbered backups (see backups.py) and pruning are done by the
library.

Other scripts can import this module and call ``update(...)``; like the other
updaters it exposes ``NAME`` and ``update(**options)`` and raises
``update_github.GithubError`` on failure (nothing is changed in that case).
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import dataclasses
import sys
from pathlib import Path

def _add_utils_to_path() -> None:
    """Make Scripts/Utils importable wherever this file sits inside the repo."""
    for parent in Path(__file__).resolve().parents:
        utils = parent / "Scripts" / "Utils"
        if (utils / "backups.py").is_file():
            if str(utils) not in sys.path:
                sys.path.insert(0, str(utils))
            return
    raise ImportError("Scripts/Utils/backups.py not found in any parent folder")


_add_utils_to_path()
import update_github as gh  # noqa: E402

NAME = "winutil"
DESCRIPTION = "Update winutil.ps1 from the latest ChrisTitusTech/winutil release"

SCRIPT_DIR = Path(__file__).resolve().parent
DEST = SCRIPT_DIR / "winutil.ps1"  # adjust to where the file lives in your collection

TARGET = gh.Target(
    name=NAME,
    repo="ChrisTitusTech/winutil",
    asset="winutil.ps1",
    dest=DEST,
)


def update(
    keep: int = gh.DEFAULT_KEEP,
    token: str | None = None,
    prerelease: bool = False,
    dest: str | Path | None = None,
    log=print,
) -> gh.TargetResult:
    """Update winutil.ps1 and return the TargetResult (raises GithubError)."""
    target = TARGET
    if prerelease or dest is not None:
        target = dataclasses.replace(
            TARGET,
            prerelease=prerelease,
            dest=Path(dest).expanduser().resolve() if dest is not None else TARGET.dest,
        )
    return gh.update_target(target, keep=keep, token=token, log=log)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("--dest", metavar="PATH",
                        help=f"where to put winutil.ps1 (default: {DEST})")
    parser.add_argument("--prerelease", action="store_true",
                        help="use the newest release including pre-releases")
    parser.add_argument("--keep", type=int, default=gh.DEFAULT_KEEP, metavar="N",
                        help=f"backups to keep, newest first (default: {gh.DEFAULT_KEEP})")
    args = parser.parse_args(argv)

    try:
        result = update(keep=args.keep, prerelease=args.prerelease, dest=args.dest)
    except (gh.GithubError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    for line in gh.format_result(result):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
