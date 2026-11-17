#!/usr/bin/env python3
"""Update portable antivirus scanners from their official download endpoints.

Downloads are staged beside the destination, checked as PE executables, and
compared by SHA-256. Existing files are backed up with the shared backups.py
helpers before replacement.

Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

sys.dont_write_bytecode = True


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

from backups import next_backup_path, prune_backups  # noqa: E402


NAME = "av_scanners"
DESCRIPTION = "Update portable antivirus scanners from official sources"

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_KEEP = 1
HTTP_TIMEOUT = 90
CHUNK_SIZE = 1024 * 1024
MAX_DOWNLOAD_SIZE = 100 * 1024 * 1024
USER_AGENT = "test_tweaks AV-Scanners Updater"

# The URLs below are direct download endpoints published by the vendors.
# HouseCall provides separate launchers for 64-bit and 32-bit Windows.
@dataclass(frozen=True)
class Target:
    name: str
    filename: str
    url: str
    expected_machine: int | None = None


TARGETS = (
    Target(
        name="AdwCleaner",
        filename="adwcleaner.exe",
        url="https://adwcleaner.malwarebytes.com/adwcleaner?channel=release",
    ),
    Target(
        name="ESET Online Scanner",
        filename="esetonlinescanner.exe",
        url=(
            "https://download.eset.com/com/eset/tools/online_scanner/"
            "latest/esetonlinescanner.exe"
        ),
    ),
    Target(
        name="Trend Micro HouseCall x64",
        filename="HousecallLauncher64.exe",
        url="https://go.trendmicro.com/housecall8/r2/HousecallLauncher64.exe",
        expected_machine=0x8664,  # IMAGE_FILE_MACHINE_AMD64
    ),
    Target(
        name="Trend Micro HouseCall x86",
        filename="HousecallLauncher.exe",
        url="https://go.trendmicro.com/housecall8/r2/HousecallLauncher.exe",
        expected_machine=0x014C,  # IMAGE_FILE_MACHINE_I386
    ),
)


class UpdateError(RuntimeError):
    """An error while downloading, validating, or installing a scanner."""


@dataclass
class UpdateResult:
    target: str
    status: str
    destination: Path
    backup: Path | None = None
    removed_backups: list[Path] | None = None
    message: str = ""


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _pe_machine(path: Path) -> int:
    """Return the PE COFF machine value, rejecting non-PE downloads."""
    size = path.stat().st_size
    if size < 64:
        raise UpdateError("Downloaded file is too small to be a Windows executable.")

    with path.open("rb") as stream:
        dos_header = stream.read(64)
        if dos_header[:2] != b"MZ":
            raise UpdateError("Downloaded file does not have an MZ executable header.")

        pe_offset = struct.unpack_from("<I", dos_header, 0x3C)[0]
        if pe_offset > size - 6:
            raise UpdateError("Invalid PE header offset.")

        stream.seek(pe_offset)
        header = stream.read(6)

    if len(header) != 6 or header[:4] != b"PE\0\0":
        raise UpdateError("Downloaded file does not contain a valid PE signature.")

    return struct.unpack_from("<H", header, 4)[0]


def _download(target: Target, destination_dir: Path) -> tuple[Path, str]:
    """Download one target to a temporary file and validate its PE header."""
    request = urllib.request.Request(
        target.url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/octet-stream, */*",
        },
    )

    fd, temp_name = tempfile.mkstemp(
        prefix=f".{target.filename}.",
        suffix=".download",
        dir=destination_dir,
    )
    temp_path = Path(temp_name)
    digest = hashlib.sha256()
    total = 0

    try:
        with os.fdopen(fd, "wb") as output:
            try:
                response = urllib.request.urlopen(
                    request, timeout=HTTP_TIMEOUT
                )
            except urllib.error.HTTPError as exc:
                raise UpdateError(f"HTTP error {exc.code}: {exc.reason}") from exc
            except (urllib.error.URLError, TimeoutError, OSError) as exc:
                raise UpdateError(f"Download failed: {exc}") from exc

            with response:
                final_url = response.geturl()
                if not final_url.lower().startswith("https://"):
                    raise UpdateError(
                        f"Refusing non-HTTPS redirect destination: {final_url}"
                    )

                status = response.getcode()
                if status != 200:
                    raise UpdateError(f"Unexpected HTTP status: {status}")

                content_length = response.headers.get("Content-Length")
                if content_length:
                    try:
                        expected_size = int(content_length)
                    except ValueError:
                        expected_size = None
                    if expected_size is not None and expected_size > MAX_DOWNLOAD_SIZE:
                        raise UpdateError(
                            f"Download exceeds the {MAX_DOWNLOAD_SIZE} byte limit."
                        )

                while True:
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > MAX_DOWNLOAD_SIZE:
                        raise UpdateError(
                            f"Download exceeds the {MAX_DOWNLOAD_SIZE} byte limit."
                        )
                    output.write(chunk)
                    digest.update(chunk)

            output.flush()
            os.fsync(output.fileno())

        if total == 0:
            raise UpdateError("The server returned an empty file.")

        machine = _pe_machine(temp_path)
        if (
            target.expected_machine is not None
            and machine != target.expected_machine
        ):
            actual = {
                0x014C: "x86",
                0x8664: "x64",
                0xAA64: "ARM64",
            }.get(machine, f"unknown PE machine 0x{machine:04X}")
            expected = "x64" if target.expected_machine == 0x8664 else "x86"
            raise UpdateError(
                f"Wrong architecture: expected {expected}, received {actual}."
            )

        return temp_path, digest.hexdigest()

    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def _update_one(
    target: Target,
    destination_dir: Path,
    keep: int,
    log: Callable[[str], None],
) -> UpdateResult:
    destination = destination_dir / target.filename
    log(f"{target.name}: downloading...")

    temp_path, remote_hash = _download(target, destination_dir)
    backup: Path | None = None

    try:
        if destination.exists():
            if not destination.is_file():
                raise UpdateError(f"Destination is not a regular file: {destination}")

            if _sha256_file(destination) == remote_hash:
                return UpdateResult(
                    target.name,
                    "up-to-date",
                    destination,
                    message="identical SHA-256",
                )

        if destination.exists():
            backup = next_backup_path(destination)
            os.replace(destination, backup)

        try:
            os.replace(temp_path, destination)
        except OSError:
            if backup is not None:
                os.replace(backup, destination)
                backup = None
            raise

        try:
            removed = prune_backups(
                destination_dir,
                [destination.name],
                keep,
            )
        except OSError as exc:
            # The new executable is already installed; pruning is housekeeping.
            removed = []
            log(f"{target.name}: warning: could not prune old backups: {exc}")

        return UpdateResult(
            target.name,
            "updated",
            destination,
            backup=backup,
            removed_backups=removed,
        )

    finally:
        temp_path.unlink(missing_ok=True)


def update(
    keep: int = DEFAULT_KEEP,
    dest_dir: str | Path | None = None,
    only: list[str] | tuple[str, ...] | None = None,
    log: Callable[[str], None] = print,
) -> list[UpdateResult]:
    """Update all scanners, or selected targets, and return individual results.

    A failure for one scanner does not prevent the remaining scanners updating.
    Target names accepted by ``only``: adwcleaner, eset, housecall64, housecall32.
    """
    if keep < 0:
        raise ValueError("keep cannot be negative")

    destination_dir = (
        Path(dest_dir).expanduser().resolve()
        if dest_dir is not None
        else SCRIPT_DIR
    )
    destination_dir.mkdir(parents=True, exist_ok=True)

    aliases = {
        "adwcleaner": TARGETS[0],
        "eset": TARGETS[1],
        "housecall64": TARGETS[2],
        "housecall32": TARGETS[3],
    }

    if only:
        unknown = set(only) - aliases.keys()
        if unknown:
            raise ValueError(f"Unknown target(s): {', '.join(sorted(unknown))}")
        selected = [aliases[name] for name in only]
    else:
        selected = list(TARGETS)

    results: list[UpdateResult] = []
    for target in selected:
        try:
            result = _update_one(target, destination_dir, keep, log)
        except (UpdateError, OSError) as exc:
            result = UpdateResult(
                target.name,
                "error",
                destination_dir / target.filename,
                message=str(exc),
            )
        results.append(result)

        if result.status == "updated":
            log(f"{target.name}: updated -> {result.destination.name}")
        elif result.status == "up-to-date":
            log(f"{target.name}: already up to date")
        else:
            log(f"{target.name}: ERROR: {result.message}")

    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument(
        "--dest-dir",
        metavar="PATH",
        help=f"directory for scanner executables (default: {SCRIPT_DIR})",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=DEFAULT_KEEP,
        metavar="N",
        help=f"number of backups to keep per executable (default: {DEFAULT_KEEP})",
    )
    parser.add_argument(
        "--only",
        action="append",
        choices=("adwcleaner", "eset", "housecall64", "housecall32"),
        help="update only this target; may be specified more than once",
    )
    args = parser.parse_args(argv)

    if args.keep < 0:
        parser.error("--keep cannot be negative")

    try:
        results = update(
            keep=args.keep,
            dest_dir=args.dest_dir,
            only=args.only,
        )
    except (OSError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 1 if any(result.status == "error" for result in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
