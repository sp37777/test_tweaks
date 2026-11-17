#!/usr/bin/env python3
"""Library: keep a local file in sync with a file published on GitHub.

This module has no targets of its own; scripts such as update_winutil.py
describe *what* to update with a ``Target`` and call ``update_target()``
(raises on failure) or ``update_targets()`` (several targets, errors are
collected into the results). It can also be run directly (see "Command line").

Two kinds of target
-------------------
* release asset (``Target(name, repo, asset, dest)``): a file attached to the
  latest GitHub release. Skipped when the local file already has the SHA-256
  that GitHub publishes for the asset; size and SHA-256 are verified.
* repository file (``Target.repo_file(name, repo, path, dest, ref=...)``): a
  file inside the repository itself, for projects whose releases contain only
  source code. ``ref`` is "release" (default: the tag of the latest release),
  "HEAD" (tip of the default branch) or any branch/tag/commit name. Skipped
  when the local file has the git object id GitHub reports for that path, and
  the download is verified against that id.

Both kinds download to a temporary file, refuse HTML error pages, rename the
current file to the next free ``<name>_<N><ext>`` backup, install the new file
and prune old backups (see backups.py).

Command line
------------
    update_github.py OWNER/REPO --asset NAME --dest PATH
    update_github.py OWNER/REPO --file PATH/IN/REPO --dest PATH [--ref REF]

``--dest`` is a file path or an existing directory (the file keeps its name).
Add ``--prerelease`` to consider pre-releases when ``--ref release`` is used.

Unauthenticated GitHub API use is limited to 60 requests/hour; set the
GITHUB_TOKEN environment variable (read-only token is enough) or pass
``token=`` to raise it. The token is only ever sent to the API, never to the
download hosts.
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Iterable
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backups import next_backup_path, prune_backups  # noqa: E402
sys.dont_write_bytecode = True

API_BASE = "https://api.github.com"
GITHUB_BASE = "https://github.com"
RAW_BASE = "https://raw.githubusercontent.com"
HTTP_TIMEOUT = 30.0
MAX_API_BYTES = 5 * 1024 * 1024
DEFAULT_KEEP = 2
USER_AGENT = "update_github.py (+Ventoy collection updater)"

_REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


@dataclass(frozen=True)
class Target:
    """What to update. ``dest`` must be an absolute path: callers build it from
    their own location (e.g. ``Path(__file__).resolve().parent / "x.ps1"``).

    Set ``asset`` (release asset) or ``path`` (file in the repository), not
    both; ``Target.repo_file()`` is the convenient way to make the latter."""

    name: str          # short name used in log lines
    repo: str          # "owner/name"
    asset: str         # release asset file name; fnmatch patterns such as "x-*.zip" allowed
    dest: Path         # absolute path of the local file
    prerelease: bool = False   # True: newest release including pre-releases
    max_size: int = 50 * 1024 * 1024
    path: str = ""     # repository file mode: path of the file inside the repository
    ref: str = "release"       # repository file mode: "release", "HEAD" or a branch/tag/commit

    @classmethod
    def repo_file(cls, name: str, repo: str, path: str, dest: Path, ref: str = "release",
                  prerelease: bool = False, max_size: int = 50 * 1024 * 1024) -> "Target":
        return cls(name=name, repo=repo, asset="", dest=dest, prerelease=prerelease,
                   max_size=max_size, path=path, ref=ref)


class GithubError(Exception):
    """Raised for a problem with one target (nothing was changed for it)."""


@dataclass
class TargetResult:
    name: str
    status: str                      # "updated" | "up-to-date" | "error"
    tag: str | None = None
    dest: Path | None = None
    backup: Path | None = None
    pruned: list[Path] = field(default_factory=list)
    message: str = ""


# --------------------------------------------------------------------------
# GitHub API
# --------------------------------------------------------------------------
def _api_get(path: str, token: str | None):
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(API_BASE + path, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            raw = response.read(MAX_API_BYTES + 1)
    except urllib.error.HTTPError as exc:
        if exc.code in (403, 429) and exc.headers.get("X-RateLimit-Remaining") == "0":
            reset = exc.headers.get("X-RateLimit-Reset", "")
            when = (
                time.strftime("%H:%M:%S", time.localtime(int(reset)))
                if reset.isdigit()
                else "later"
            )
            raise GithubError(
                f"GitHub API rate limit reached (resets at {when}). "
                "Set GITHUB_TOKEN to raise the limit."
            ) from exc
        if exc.code == 404:
            raise GithubError("Repository or release not found (HTTP 404).") from exc
        raise GithubError(f"GitHub API error: HTTP {exc.code}.") from exc
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise GithubError(f"Cannot reach GitHub: {exc}") from exc
    if len(raw) > MAX_API_BYTES:
        raise GithubError("Unexpectedly large API response.")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise GithubError(f"GitHub returned invalid JSON: {exc}") from exc


def fetch_release(target: Target, token: str | None) -> dict:
    if not _REPO_RE.match(target.repo):
        raise GithubError(f"Invalid repository name: {target.repo!r}")
    if not target.prerelease:
        release = _api_get(f"/repos/{target.repo}/releases/latest", token)
    else:
        releases = _api_get(f"/repos/{target.repo}/releases?per_page=10", token)
        release = next((r for r in releases if not r.get("draft")), None)
        if release is None:
            raise GithubError("No published releases found.")
    if not isinstance(release, dict):
        raise GithubError("Unexpected release data from GitHub.")
    return release


def find_asset(release: dict, pattern: str) -> dict:
    assets = release.get("assets") or []
    matches = [a for a in assets if fnmatch.fnmatchcase(a.get("name", ""), pattern)]
    if len(matches) == 1:
        return matches[0]
    names = ", ".join(a.get("name", "?") for a in assets) or "none"
    if not matches:
        raise GithubError(f"Asset {pattern!r} not found in release. Available: {names}")
    raise GithubError(f"Asset pattern {pattern!r} is ambiguous. Matches: "
                      + ", ".join(a["name"] for a in matches))


def _published_sha256(asset: dict) -> str | None:
    digest = asset.get("digest")
    if isinstance(digest, str) and digest.lower().startswith("sha256:"):
        return digest.split(":", 1)[1].strip().lower()
    return None


# --------------------------------------------------------------------------
# Download / install
# --------------------------------------------------------------------------
def _sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _download(url: str, directory: Path, name: str, limit: int) -> tuple[Path, str, int]:
    """Stream ``url`` into a temp file; returns (path, sha256, size)."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    fd, temp_name = tempfile.mkstemp(prefix=f".{name}.", suffix=".tmp", dir=directory)
    temp_path = Path(temp_name)
    h = hashlib.sha256()
    size = 0
    try:
        with os.fdopen(fd, "wb") as out, urllib.request.urlopen(
            request, timeout=HTTP_TIMEOUT
        ) as response:
            while chunk := response.read(65536):
                size += len(chunk)
                if size > limit:
                    raise GithubError(f"Download exceeds the {limit} byte limit.")
                h.update(chunk)
                out.write(chunk)
            out.flush()
            os.fsync(out.fileno())
    except GithubError:
        temp_path.unlink(missing_ok=True)
        raise
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        temp_path.unlink(missing_ok=True)
        raise GithubError(f"Download failed: {exc}") from exc
    return temp_path, h.hexdigest(), size


def _git_blob_sha1_of(path: Path) -> str:
    """Git object id of a file's content: sha1(b"blob <size>\\0" + content)."""
    h = hashlib.sha1(f"blob {path.stat().st_size}\0".encode())
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _looks_like_html(temp_path: Path, dest: Path) -> bool:
    """True if a download that should not be HTML is an HTML (error) page."""
    if dest.suffix.lower() in (".htm", ".html"):
        return False
    with open(temp_path, "rb") as stream:
        head = stream.read(512).lower()
    return b"<html" in head or b"<!doctype html" in head


def _install(temp_path: Path, dest: Path, keep: int) -> tuple[Path | None, list[Path]]:
    """Back up the current file (next free _N), put the new one in place, prune."""
    backup: Path | None = None
    if dest.exists():
        backup = next_backup_path(dest)
        os.replace(dest, backup)
    try:
        os.replace(temp_path, dest)
    except OSError:
        if backup is not None:
            os.replace(backup, dest)
        raise
    return backup, prune_backups(dest.parent, [dest.name], keep)


def _clean_repo_path(path: str) -> str:
    parts = PurePosixPath(path.strip("/")).parts
    if not parts or "\\" in path or any(part in (".", "..") for part in parts):
        raise GithubError(f"Invalid path inside the repository: {path!r}")
    return "/".join(parts)


def _update_asset(target: Target, dest: Path, keep: int, token: str | None, log) -> TargetResult:
    release = fetch_release(target, token)
    tag = release.get("tag_name") or "?"
    asset = find_asset(release, target.asset)
    expected = _published_sha256(asset)

    url = asset.get("browser_download_url", "")
    allowed = f"{GITHUB_BASE}/{target.repo}/releases/download/"
    if not url.startswith(allowed):
        raise GithubError("Refusing a download URL outside the repository's releases.")

    local_hash = _sha256_of(dest) if dest.is_file() else None
    log(f"{target.name}: release {tag}, asset {asset['name']} ({asset.get('size', '?')} bytes)")

    if expected and local_hash == expected:
        return TargetResult(target.name, "up-to-date", tag, dest, message="already the published file")

    dest.parent.mkdir(parents=True, exist_ok=True)
    limit = min(target.max_size, int(asset["size"]) if asset.get("size") else target.max_size)
    temp_path, new_hash, size = _download(url, dest.parent, dest.name, limit)
    try:
        if asset.get("size") and size != int(asset["size"]):
            raise GithubError(f"Size mismatch: got {size} bytes, expected {asset['size']}.")
        if expected is None:
            log(f"{target.name}: GitHub published no SHA-256 for this asset; only the size was checked.")
        elif new_hash != expected:
            raise GithubError("SHA-256 of the download does not match the published digest.")
        if _looks_like_html(temp_path, dest):
            raise GithubError("The download is an HTML page, not the expected file.")

        if local_hash == new_hash:
            temp_path.unlink(missing_ok=True)
            return TargetResult(target.name, "up-to-date", tag, dest, message="content identical")

        backup, pruned = _install(temp_path, dest, keep)
    finally:
        temp_path.unlink(missing_ok=True)
    return TargetResult(target.name, "updated", tag, dest, backup, pruned)


def _resolve_ref(target: Target, token: str | None) -> str | None:
    """Branch/tag to read the file from; None means the default branch's tip."""
    ref = target.ref or "release"
    if ref == "HEAD":
        return None
    if ref != "release":
        return ref
    try:
        release = fetch_release(target, token)
    except GithubError as exc:
        hint = ""
        if "404" in str(exc):
            hint = (" If the repository has no releases, set ref='HEAD' (default branch) "
                    "or a branch/tag name.")
        raise GithubError(f"Cannot resolve the latest release of {target.repo}: {exc}{hint}") from exc
    tag = release.get("tag_name")
    if not tag:
        raise GithubError("The latest release has no tag name.")
    return tag


def _update_repo_file(target: Target, dest: Path, keep: int, token: str | None, log) -> TargetResult:
    path = _clean_repo_path(target.path)
    ref = _resolve_ref(target, token)
    label = ref or "HEAD"
    query = f"?ref={quote(ref, safe='')}" if ref else ""
    info = _api_get(f"/repos/{target.repo}/contents/{quote(path, safe='/')}{query}", token)

    if isinstance(info, list):
        raise GithubError(f"{path!r} is a directory, not a file.")
    if not isinstance(info, dict) or info.get("type") != "file":
        raise GithubError(f"{path!r} is not a regular file in {target.repo}@{label}.")
    blob = str(info.get("sha", "")).lower()
    size_expected = info.get("size")
    url = str(info.get("download_url") or "")
    if not re.fullmatch(r"[0-9a-f]{40}", blob) or not isinstance(size_expected, int):
        raise GithubError("Unexpected file data from the GitHub API.")
    if not url.lower().startswith(f"{RAW_BASE}/{target.repo}/".lower()):
        raise GithubError("Refusing a download URL outside the repository.")
    log(f"{target.name}: {target.repo}@{label}:{path} ({size_expected} bytes)")

    local_blob = _git_blob_sha1_of(dest) if dest.is_file() else None
    if local_blob == blob:
        return TargetResult(target.name, "up-to-date", label, dest, message="same as the repository file")

    dest.parent.mkdir(parents=True, exist_ok=True)
    temp_path, _, size = _download(url, dest.parent, dest.name, min(target.max_size, size_expected))
    try:
        if size != size_expected:
            raise GithubError(f"Size mismatch: got {size} bytes, expected {size_expected}.")
        if _git_blob_sha1_of(temp_path) != blob:
            raise GithubError("The download does not match the git object id GitHub reported "
                              "(the file may have changed meanwhile); try again.")
        if _looks_like_html(temp_path, dest):
            raise GithubError("The download is an HTML page, not the expected file.")
        backup, pruned = _install(temp_path, dest, keep)
    finally:
        temp_path.unlink(missing_ok=True)
    return TargetResult(target.name, "updated", label, dest, backup, pruned)


def update_target(
    target: Target,
    keep: int = DEFAULT_KEEP,
    token: str | None = None,
    log=print,
) -> TargetResult:
    """Update one target. Raises GithubError if anything is wrong; in that case
    the local file and its backups are left untouched."""
    token = token if token is not None else os.environ.get("GITHUB_TOKEN")
    dest = Path(target.dest)
    if not dest.is_absolute():
        raise GithubError(f"Target {target.name!r}: dest must be an absolute path.")
    if bool(target.asset) == bool(target.path):
        raise GithubError(f"Target {target.name!r}: set exactly one of asset or path.")
    if not _REPO_RE.match(target.repo):
        raise GithubError(f"Invalid repository name: {target.repo!r}")
    if target.path:
        return _update_repo_file(target, dest, keep, token, log)
    return _update_asset(target, dest, keep, token, log)


# --------------------------------------------------------------------------
# Several targets / reporting
# --------------------------------------------------------------------------
def update_targets(
    targets: Iterable[Target],
    keep: int = DEFAULT_KEEP,
    token: str | None = None,
    log=print,
) -> list[TargetResult]:
    """Update several targets; a failure of one does not stop the others."""
    results: list[TargetResult] = []
    for target in targets:
        try:
            results.append(update_target(target, keep, token, log))
        except (GithubError, OSError) as exc:
            log(f"{target.name}: ERROR: {exc}")
            results.append(TargetResult(target.name, "error", message=str(exc)))
    return results


def format_result(result: TargetResult) -> list[str]:
    """Console lines describing a result, in the same style as the other updaters."""
    if result.status == "updated":
        lines = []
        if result.backup and result.dest:
            lines.append(f"Backup:    {result.dest.name} -> {result.backup.name}")
        lines.append(f"Updated:   {result.name} ({result.tag}) -> {result.dest}")
        lines += [f"Deleted:   {path.name}" for path in result.pruned]
        return lines
    if result.status == "up-to-date":
        return [f"Up to date: {result.name} ({result.tag}) - {result.message}"]
    return [f"Error:      {result.name}: {result.message}"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Update a local file from a GitHub release asset or a repository file."
    )
    parser.add_argument("repo", metavar="OWNER/REPO")
    what = parser.add_mutually_exclusive_group(required=True)
    what.add_argument("--asset", metavar="NAME", help="release asset name (patterns like 'x-*.zip' allowed)")
    what.add_argument("--file", metavar="PATH", help="file path inside the repository")
    parser.add_argument("--dest", required=True, metavar="PATH",
                        help="local file path, or an existing directory (the file keeps its name)")
    parser.add_argument("--ref", default="release", metavar="REF",
                        help="with --file: 'release' (latest release tag, default), 'HEAD' "
                             "(default branch) or a branch/tag/commit")
    parser.add_argument("--prerelease", action="store_true", help="consider pre-releases")
    parser.add_argument("--keep", type=int, default=DEFAULT_KEEP, metavar="N",
                        help=f"backups to keep, newest first (default: {DEFAULT_KEEP})")
    args = parser.parse_args(argv)

    dest = Path(args.dest).expanduser().resolve()
    remote_name = Path(args.file).name if args.file else args.asset
    if dest.is_dir():
        if any(ch in remote_name for ch in "*?["):
            print("Error: --dest must be a file path when the asset name is a pattern.", file=sys.stderr)
            return 1
        dest = dest / remote_name

    if args.file:
        target = Target.repo_file(remote_name, args.repo, args.file, dest, ref=args.ref,
                                  prerelease=args.prerelease)
    else:
        target = Target(remote_name, args.repo, args.asset, dest, prerelease=args.prerelease)
    try:
        result = update_target(target, keep=args.keep)
    except (GithubError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    for line in format_result(result):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())