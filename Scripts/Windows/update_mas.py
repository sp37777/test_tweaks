#!/usr/bin/env python3
"""Update MAS_AIO.cmd from the official MAS Azure DevOps repository.

Uses the shared backup system and TargetResult format from update_github.py.
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

sys.dont_write_bytecode = True


def _add_utils_to_path() -> None:
    """Make Scripts/Utils importable from anywhere inside the repository."""
    for parent in Path(__file__).resolve().parents:
        utils = parent / "Scripts" / "Utils"
        if (utils / "backups.py").is_file():
            if str(utils) not in sys.path:
                sys.path.insert(0, str(utils))
            return
    raise ImportError("Scripts/Utils/backups.py not found in any parent folder")


_add_utils_to_path()

import update_github as gh  # noqa: E402
from backups import next_backup_path, prune_backups  # noqa: E402


NAME = "mas"
DESCRIPTION = "Update MAS_AIO.cmd from the official MAS repository"

SCRIPT_DIR = Path(__file__).resolve().parent
DEST = SCRIPT_DIR / "MAS_AIO.cmd"

SOURCE_URL = (
    "https://dev.azure.com/massgrave/"
    "Microsoft-Activation-Scripts/_apis/git/repositories/"
    "Microsoft-Activation-Scripts/items"
    "?path=/MAS/All-In-One-Version-KL/MAS_AIO.cmd&download=true"
)

USER_AGENT = "MAS-Updater (+https://github.com/sp37777/test_tweaks)"
HTTP_TIMEOUT = 60
MAX_SIZE = 10 * 1024 * 1024


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _download() -> bytes:
    """Download the official MAS_AIO.cmd file with a strict size limit."""
    request = urllib.request.Request(
        SOURCE_URL,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/octet-stream",
        },
    )

    try:
        with urllib.request.urlopen(
            request, timeout=HTTP_TIMEOUT
        ) as response:
            data = response.read(MAX_SIZE + 1)

    except urllib.error.HTTPError as exc:
        raise gh.GithubError(
            f"MAS download failed: HTTP {exc.code}."
        ) from exc
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise gh.GithubError(
            f"Cannot download MAS: {exc}"
        ) from exc

    if len(data) > MAX_SIZE:
        raise gh.GithubError(
            f"MAS download exceeds the {MAX_SIZE} byte limit."
        )

    if not data:
        raise gh.GithubError("MAS download is empty.")

    # Reject HTML error pages and unexpected responses.
    head = data[:1024].lower()
    if b"<html" in head or b"<!doctype html" in head:
        raise gh.GithubError(
            "The server returned an HTML page instead of MAS_AIO.cmd."
        )

    # Validate that this really looks like the MAS batch script.
    if b"@echo off" not in data[:4096].lower():
        raise gh.GithubError(
            "Downloaded file does not look like MAS_AIO.cmd."
        )

    return data



def update(
    keep: int = gh.DEFAULT_KEEP,
    dest: str | Path | None = None,
    log=print,
) -> gh.TargetResult:
    """Update MAS_AIO.cmd if its content has changed."""
    destination = (
        Path(dest).expanduser().resolve()
        if dest is not None
        else DEST
    )

    if not destination.is_absolute():
        raise gh.GithubError("Destination path must be absolute.")

    log(f"{NAME}: checking the official MAS source...")

    data = _download()
    remote_hash = _sha256(data)

    if destination.exists():
        if not destination.is_file():
            raise gh.GithubError(
                f"Destination is not a regular file: {destination}"
            )

        local_hash = _sha256(destination.read_bytes())

        if local_hash == remote_hash:
            return gh.TargetResult(
                NAME,
                "up-to-date",
                "latest",
                destination,
                message="identical content",
            )

    destination.parent.mkdir(parents=True, exist_ok=True)

    fd, temp_name = tempfile.mkstemp(
        prefix=f".{destination.name}.",
        suffix=".tmp",
        dir=destination.parent,
    )
    temp_path = Path(temp_name)

    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())

        if _sha256(temp_path.read_bytes()) != remote_hash:
            raise gh.GithubError(
                "Temporary file verification failed."
            )

        backup = None

        if destination.exists():
            backup = next_backup_path(destination)
            os.replace(destination, backup)

        try:
            os.replace(temp_path, destination)
        except OSError:
            if backup is not None:
                os.replace(backup, destination)
            raise

    except gh.GithubError:
        raise
    except OSError as exc:
        raise gh.GithubError(
            f"Cannot install MAS_AIO.cmd: {exc}"
        ) from exc
    finally:
        temp_path.unlink(missing_ok=True)

    pruned = prune_backups(
        destination.parent,
        [destination.name],
        keep,
    )

    return gh.TargetResult(
        NAME,
        "updated",
        "latest",
        destination,
        backup,
        pruned,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument(
        "--dest",
        metavar="PATH",
        help=f"where to put MAS_AIO.cmd (default: {DEST})",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=gh.DEFAULT_KEEP,
        metavar="N",
        help=f"backups to keep, newest first (default: {gh.DEFAULT_KEEP})",
    )

    args = parser.parse_args(argv)

    if args.keep < 0:
        parser.error("--keep cannot be negative")

    try:
        result = update(
            keep=args.keep,
            dest=args.dest,
        )
    except (gh.GithubError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for line in gh.format_result(result):
        print(line)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())