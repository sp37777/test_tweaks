#!/usr/bin/env python3
"""Refresh autounattend.xml from the schneegans.de generator and rebuild variants.

Workflow
--------
1. Read the generator URL stored in the comment at the top of the current
   autounattend.xml. That URL holds the *complete* configuration (taskbar and
   Start menu XML/JSON, System / FirstLogon scripts, ...).
2. Request the same URL with ``download/`` appended to its path, which is what
   the generator's "Download .xml file" button does. If the generator rejects
   the saved settings (for example because an option is no longer supported)
   its message is logged, and the "updated settings" link it offers can be
   opened in the browser to review and download by hand.
   (``--browser`` forces the manual flow, ``--file`` uses a downloaded file.)
3. Validate the new file, compare its configuration with the old one and
   report anything that was removed or changed.
4. Back up the old autounattend.xml (next free ``_N`` number), install the new
   one, call builder.build() to regenerate the unattend_10_*.xml variants
   (builder makes its own ``_N`` backups) and prune old backups.

Other scripts can import this module and call ``update(...)``; every updater
is expected to expose ``NAME`` and ``update(**options)``. Progress is reported
through the ``log`` callable (default ``print``), so a caller can pass its own
logger.
Only Python's standard library is required.
"""

from __future__ import annotations

import argparse
import html
import os
import re
import sys
import tempfile
import time
import webbrowser
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
import urllib.error
import urllib.request
from urllib.parse import parse_qsl, urlsplit, urlunsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))  # builder.py lives next to this file
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
import builder  # noqa: E402

NAME = "unattend"
DESCRIPTION = "Update autounattend.xml from schneegans.de and rebuild unattend_10_*.xml"

UNATTEND_NS = "urn:schemas-microsoft-com:unattend"
GENERATOR_URL_PREFIX = "https://schneegans.de/windows/unattend-generator/"
DEFAULT_KEEP = 2
HTTP_TIMEOUT = 30.0
MAX_DOWNLOAD_BYTES = 5 * 1024 * 1024
USER_AGENT = "update_unattend.py (+Ventoy unattend updater)"
SCRIPT_DIR = Path(builder.__file__).resolve().parent


class UpdateError(Exception):
    """Raised when the update cannot be completed safely (nothing is lost)."""


class GeneratorRejected(UpdateError):
    """The generator answered with a message instead of an answer file."""

    def __init__(self, message: str, updated_url: str | None, status: int | None):
        super().__init__(message)
        self.message = message
        self.updated_url = updated_url
        self.status = status


# --------------------------------------------------------------------------
# Generator URL / configuration helpers
# --------------------------------------------------------------------------
def extract_generator_url(text: str) -> str | None:
    """Return the generator URL stored in an XML comment, if there is one."""
    for match in re.finditer(r"<!--(.*?)-->", text, re.S):
        comment = match.group(1).strip()
        if comment.startswith(GENERATOR_URL_PREFIX):
            return comment
    return None


def parse_config(url: str) -> dict[str, list[str]]:
    """Decode the query string of a generator URL into {name: [values]}."""
    config: dict[str, list[str]] = {}
    for key, value in parse_qsl(urlsplit(url).query, keep_blank_values=True):
        config.setdefault(key, []).append(value)
    return config


@dataclass
class ConfigDiff:
    added: list[str] = field(default_factory=list)
    removed: list[str] = field(default_factory=list)
    changed: list[str] = field(default_factory=list)

    @property
    def risky(self) -> bool:
        """Removed or changed settings need a human look; additions do not."""
        return bool(self.removed or self.changed)

    @property
    def empty(self) -> bool:
        return not (self.added or self.removed or self.changed)


def _short(values: list[str]) -> str:
    joined = ",".join(values)
    return repr(joined) if len(joined) <= 40 else f"<{len(joined)} chars>"


def diff_configs(old: dict[str, list[str]], new: dict[str, list[str]]) -> ConfigDiff:
    diff = ConfigDiff()
    for key in sorted(old.keys() - new.keys()):
        diff.removed.append(f"{key} (was {_short(old[key])})")
    for key in sorted(new.keys() - old.keys()):
        diff.added.append(f"{key} = {_short(new[key])}")
    for key in sorted(old.keys() & new.keys()):
        if sorted(old[key]) != sorted(new[key]):
            diff.changed.append(f"{key}: {_short(old[key])} -> {_short(new[key])}")
    return diff


# --------------------------------------------------------------------------
# Getting the new file
# --------------------------------------------------------------------------
def download_url_for(url: str) -> str:
    """Same configuration, but pointing at the generator's download endpoint."""
    parts = urlsplit(url)
    path = parts.path.rstrip("/")
    if not path.endswith("/download"):
        path += "/download"
    return urlunsplit((parts.scheme, parts.netloc, path + "/", parts.query, ""))


def _readable_message(body: bytes) -> str:
    """Turn a rejection page (HTML or Markdown-ish text) into short plain text."""
    text = body.decode("utf-8", errors="replace")
    if re.search(r"<\s*(html|body|p|a|pre|code|div)\b", text, re.I):
        text = re.sub(r"(?is)<(script|style)\b.*?</\1>", "", text)
        text = re.sub(r"(?i)</?(p|br|div|pre|li|h\d)\b[^>]*>", "\n", text)
        text = re.sub(r"<[^>]+>", "", text)
        text = html.unescape(text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)  # [text](url) -> text
    text = text.replace("```", "")
    text = "\n".join(line.rstrip() for line in text.splitlines())
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return text[:1500] if text else "(empty response)"


def _find_updated_url(body: bytes) -> str | None:
    """The 'updated settings' link in a rejection message, if it is ours."""
    text = body.decode("utf-8", errors="replace")
    candidates = re.findall(r"\]\((https?://[^)\s]+)\)", text)
    candidates += [html.unescape(u) for u in re.findall(r"""href=["']([^"']+)["']""", text)]
    for candidate in candidates:
        if candidate.startswith(GENERATOR_URL_PREFIX):
            return candidate
    return None


def download_from_generator(url: str, timeout: float = HTTP_TIMEOUT) -> bytes:
    """Fetch the answer file for ``url`` (a saved generator URL).

    Raises GeneratorRejected if the server answers with something that is not
    an unattend file, UpdateError on network problems.
    """
    if not url.startswith(GENERATOR_URL_PREFIX):
        raise UpdateError("Refusing to request a URL outside the generator.")
    request = urllib.request.Request(
        download_url_for(url),
        headers={"User-Agent": USER_AGENT, "Accept": "application/xml, text/xml, */*"},
    )
    status: int | None
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = response.status
            body = response.read(MAX_DOWNLOAD_BYTES + 1)
    except urllib.error.HTTPError as exc:  # 4xx/5xx may still carry the message
        status = exc.code
        body = exc.read(MAX_DOWNLOAD_BYTES + 1)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise UpdateError(f"Cannot reach the generator: {exc}") from exc

    if len(body) > MAX_DOWNLOAD_BYTES:
        raise UpdateError("The response is unexpectedly large; refusing to use it.")
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        root = None
    if status == 200 and root is not None and root.tag == f"{{{UNATTEND_NS}}}unattend":
        return body
    raise GeneratorRejected(_readable_message(body), _find_updated_url(body), status)


def _confirm(prompt: str) -> bool:
    """Ask a yes/no question; non-interactive sessions always answer no."""
    if not sys.stdin or not sys.stdin.isatty():
        return False
    return input(prompt).strip().lower() in {"y", "yes"}


def _open_in_browser(url: str) -> Path:
    """Open ``url`` via a tiny local redirect page.

    The URL is several KB long; handing it directly to the OS shell can hit
    command-line / URL length limits, a short file:// URI never does.
    """
    escaped = html.escape(url, quote=True)
    page = (
        '<!doctype html><meta charset="utf-8">'
        f'<meta http-equiv="refresh" content="0; url={escaped}">'
        f'<a href="{escaped}">Open the unattend generator</a>'
    )
    fd, name = tempfile.mkstemp(prefix="open_unattend_generator_", suffix=".html")
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(page)
    path = Path(name)
    webbrowser.open(path.as_uri())
    return path


def _wait_for_download(directory: Path, since: float, timeout: float) -> Path:
    """Wait for a new autounattend*.xml whose size has stopped changing."""
    deadline = time.monotonic() + timeout
    previous: tuple[Path, int] | None = None
    while time.monotonic() < deadline:
        candidates = [
            p for p in directory.glob("autounattend*.xml") if p.stat().st_mtime >= since
        ]
        if candidates:
            newest = max(candidates, key=lambda p: p.stat().st_mtime)
            state = (newest, newest.stat().st_size)
            if state[1] > 0 and state == previous:
                return newest
            previous = state
        time.sleep(1.0)
    raise UpdateError(
        f"No new autounattend*.xml appeared in {directory} within {timeout:.0f} s."
    )


def _browser_download(
    url: str, downloads: str | os.PathLike[str] | None, timeout: float,
    open_browser: bool, log,
) -> Path:
    """Open ``url`` in the browser and wait for the downloaded file."""
    folder = Path(downloads).expanduser() if downloads else Path.home() / "Downloads"
    if not folder.is_dir():
        raise UpdateError(f"Downloads folder not found: {folder}")
    started = time.time() - 2  # small tolerance for coarse file timestamps
    launcher: Path | None = None
    if open_browser:
        log("Opening the generator in your browser...")
        launcher = _open_in_browser(url)
    log(f"Click the download button at the bottom of the page; waiting for the file in {folder} ...")
    try:
        path = _wait_for_download(folder, started, timeout)
    finally:
        if launcher is not None:
            launcher.unlink(missing_ok=True)
    log(f"Got {path.name}")
    return path


# --------------------------------------------------------------------------
# Backups
# --------------------------------------------------------------------------
def _install_new_source(source_path: Path, new_bytes: bytes) -> Path | None:
    """Move the current source to a numbered backup and put new_bytes in place.

    The bytes are written exactly as received (no newline translation).
    Returns the backup path, or None if there was no previous source.
    """
    fd, temp_name = tempfile.mkstemp(
        prefix=f".{source_path.name}.", suffix=".tmp", dir=source_path.parent
    )
    temp_path = Path(temp_name)
    backup: Path | None = None
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(new_bytes)
            stream.flush()
            os.fsync(stream.fileno())
        if source_path.exists():
            backup = next_backup_path(source_path)
            os.replace(source_path, backup)
        try:
            os.replace(temp_path, source_path)
        except OSError:
            if backup is not None:
                os.replace(backup, source_path)  # restore the old file
            raise
    finally:
        temp_path.unlink(missing_ok=True)
    return backup


# --------------------------------------------------------------------------
# Main entry point
# --------------------------------------------------------------------------
@dataclass
class UpdateResult:
    changed: bool
    source: Path
    source_backup: Path | None = None
    config_diff: ConfigDiff = field(default_factory=ConfigDiff)
    generated: list[Path] = field(default_factory=list)
    backups: list[tuple[Path, Path]] = field(default_factory=list)
    pruned: list[Path] = field(default_factory=list)


def _normalize_stem(base_name: str) -> str:
    stem = (base_name or "").strip()
    if stem.lower().endswith(".xml"):
        stem = stem[:-4]
    if not stem or Path(stem).name != stem or stem in {".", ".."}:
        raise UpdateError("Base name must be a plain filename stem.")
    return stem


def update(
    base_name: str = "autounattend",
    file: str | os.PathLike[str] | None = None,
    downloads: str | os.PathLike[str] | None = None,
    timeout: float = 300.0,
    keep: int = DEFAULT_KEEP,
    assume_yes: bool = False,
    open_browser: bool = True,
    browser: bool = False,
    log=print,
) -> UpdateResult:
    """Update ``<base_name>.xml`` and rebuild the variants. See module docs."""
    stem = _normalize_stem(base_name)
    source_path = SCRIPT_DIR / f"{stem}.xml"

    old_bytes = source_path.read_bytes() if source_path.is_file() else None
    old_url = (
        extract_generator_url(old_bytes.decode("utf-8", errors="replace"))
        if old_bytes is not None
        else None
    )

    # 1. Obtain the new file.
    new_bytes: bytes
    label: str
    if file is not None:
        new_path = Path(file).expanduser()
        if not new_path.is_file():
            raise UpdateError(f"File not found: {new_path}")
        new_bytes, label = new_path.read_bytes(), new_path.name
    else:
        if old_url is None:
            raise UpdateError(
                f"No generator URL comment found in {source_path.name}; "
                "download the file manually and pass it with --file."
            )
        browser_url: str | None = old_url if browser else None
        if browser_url is None:
            log("Requesting the answer file from the generator...")
            try:
                new_bytes, label = download_from_generator(old_url), "generator download"
            except GeneratorRejected as exc:
                log(f"The generator did not return a file (HTTP {exc.status}):")
                for line in exc.message.splitlines():
                    if line.strip():
                        log(f"  {line}")
                if exc.updated_url and _confirm(
                    "Open the updated settings in the browser to review and download? [y/N] "
                ):
                    browser_url = exc.updated_url
                else:
                    hint = " Run interactively to open the updated settings in the browser." if exc.updated_url else ""
                    raise UpdateError("The generator rejected the saved settings; nothing was changed." + hint) from exc
        if browser_url is not None:
            new_path = _browser_download(browser_url, downloads, timeout, open_browser, log)
            new_bytes, label = new_path.read_bytes(), new_path.name

    # 2. Validate before touching anything.
    try:
        new_text = new_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise UpdateError(f"{label} is not valid UTF-8: {exc}") from exc
    try:
        root = ET.fromstring(new_bytes)
    except ET.ParseError as exc:
        raise UpdateError(f"{label} is not well-formed XML: {exc}") from exc
    if root.tag != f"{{{UNATTEND_NS}}}unattend":
        raise UpdateError(f"{label} is not an unattend answer file.")
    try:  # dry run: the new source must be processable by the builder
        for _, key in builder.OUTPUTS:
            builder.prepare_variant(new_text, key)
    except builder.BuildError as exc:
        raise UpdateError(f"The new file cannot be processed (nothing changed): {exc}") from exc

    if old_bytes is not None and new_bytes == old_bytes:
        log("The new file is identical to the current source; nothing to do.")
        return UpdateResult(changed=False, source=source_path)

    # 3. Compare configurations so nothing is lost silently.
    new_url = extract_generator_url(new_text)
    diff = ConfigDiff()
    needs_confirmation = False
    if old_url is not None:
        if new_url is None:
            diff.removed.append("generator URL comment (the new file cannot be re-imported later)")
            needs_confirmation = True
        else:
            diff = diff_configs(parse_config(old_url), parse_config(new_url))
            needs_confirmation = diff.risky
    for title, items in (("Added", diff.added), ("Removed", diff.removed), ("Changed", diff.changed)):
        for item in items:
            log(f"  {title}: {item}")
    if needs_confirmation and not assume_yes:
        if not sys.stdin or not sys.stdin.isatty():
            raise UpdateError(
                "Settings were removed or changed (see above). "
                "Review them and re-run with --yes to accept."
            )
        if not _confirm("Apply these changes? [y/N] "):
            raise UpdateError("Cancelled; nothing was changed.")

    # 4. Install, rebuild, prune.
    source_backup = _install_new_source(source_path, new_bytes)
    generated, backups = builder.build(stem)
    managed = [f"{stem}.xml"] + [name for name, _ in builder.OUTPUTS]
    pruned = prune_backups(SCRIPT_DIR, managed, keep)

    return UpdateResult(
        changed=True,
        source=source_path,
        source_backup=source_backup,
        config_diff=diff,
        generated=generated,
        backups=backups,
        pruned=pruned,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("--base-name", default="autounattend", metavar="NAME",
                        help="source XML filename without .xml (default: autounattend)")
    parser.add_argument("--file", metavar="PATH",
                        help="use this already downloaded file instead of contacting the generator")
    parser.add_argument("--browser", action="store_true",
                        help="skip the direct download; review and download in the browser instead")
    parser.add_argument("--downloads", metavar="DIR",
                        help="folder to watch in browser mode (default: ~/Downloads)")
    parser.add_argument("--timeout", type=float, default=300.0, metavar="SEC",
                        help="how long to wait for a browser download (default: 300)")
    parser.add_argument("--keep", type=int, default=DEFAULT_KEEP, metavar="N",
                        help=f"backups to keep per file, newest first (default: {DEFAULT_KEEP})")
    parser.add_argument("--no-open", action="store_true",
                        help="browser mode: do not open the browser, just wait for the download")
    parser.add_argument("--yes", action="store_true",
                        help="accept removed/changed settings without asking")
    args = parser.parse_args(argv)

    try:
        result = update(
            base_name=args.base_name,
            file=args.file,
            downloads=args.downloads,
            timeout=args.timeout,
            keep=args.keep,
            assume_yes=args.yes,
            open_browser=not args.no_open,
            browser=args.browser,
        )
    except (UpdateError, builder.BuildError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if not result.changed:
        return 0
    if result.source_backup:
        print(f"Backup:    {result.source.name} -> {result.source_backup.name}")
    print(f"Updated:   {result.source.name}")
    for original, backup in result.backups:
        print(f"Backup:    {original.name} -> {backup.name}")
    for path in result.generated:
        print(f"Generated: {path.name}")
    for path in result.pruned:
        print(f"Deleted:   {path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
