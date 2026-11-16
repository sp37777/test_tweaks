#!/usr/bin/env python3
"""Download the current retail Windows 11 ISO from Microsoft without a browser.

Works on any OS (pure Python, standard library only). It repeats what
Microsoft's download page does, the same sequence Fido.ps1 uses:

1. open the download page (and read the current product edition id from it),
2. register ("whitelist") a random session id at vlscppe.microsoft.com,
3. complete the ov-df.microsoft.com challenge for that session (fetch mdt.js,
   extract two values, send them back with the current time),
4. getskuinformationbyproductedition -> language SKUs,
5. GetProductDownloadLinksBySku -> a signed, time-limited ISO link,
6. download the ISO (resumable), then prune older ISOs of the same kind.

Browser cookies are not needed: Mido (dockur/windows) does the same without
any. Steps 2 and 3 are what Microsoft's anti-abuse system ("Sentinel") checks;
if it still answers "Sentinel marked this request as rejected", the request or
the IP address was flagged. Reports say repeated attempts make this worse, so
wait before retrying instead of running the script in a loop.

The ISO keeps Microsoft's own file name (it contains the build number, e.g.
Windows11_Client_x64_uk-ua_26300_9457.iso), so "is there a newer image?" is
simply "does a file with that name already exist?".

These are undocumented endpoints and Microsoft changes them from time to
time, so use --debug when something breaks: it prints every step and status.
Too many requests can get an IP temporarily blocked by Microsoft.

Exposes ``NAME`` and ``update(**options)`` like the other updaters and raises
``MsDownloadError`` on failure (nothing is replaced in that case).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field
from http.cookiejar import CookieJar
from pathlib import Path
from urllib.parse import unquote, urlencode, urlsplit

NAME = "windows-iso"
DESCRIPTION = "Download the current retail Windows 11 ISO from Microsoft"

MS_BASE = "https://www.microsoft.com"
VLS_URL = "https://vlscppe.microsoft.com/tags"
OVDF_BASE = "https://ov-df.microsoft.com"
OVDF_INSTANCE = "560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175"
ORG_ID = "y6jn8c31"
PROFILE = "606624d44113"
DEFAULT_EDITION_ID = 3813  # only a fallback; the current id is read from the download page
ARCH_DOWNLOAD_TYPE = {"x64": 1, "arm64": 2}  # DownloadType values in Microsoft's answer
# A non-Windows browser string: Microsoft redirects Windows visitors to the
# Media Creation Tool instead of offering the ISO.
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:160.0) Gecko/20100101 Firefox/160.0"
HTTP_TIMEOUT = 30.0
MAX_BODY = 5 * 1024 * 1024
DEFAULT_KEEP = 2


class MsDownloadError(Exception):
    """Raised when the link or the ISO cannot be obtained."""


# --------------------------------------------------------------------------
# Web session
# --------------------------------------------------------------------------
class _Web:
    def __init__(self, debug=None):
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(CookieJar())
        )
        self.debug = debug or (lambda message: None)

    def request(self, url: str, method: str = "GET", headers: dict | None = None):
        merged = {"User-Agent": USER_AGENT, "Accept-Language": "en-US,en;q=0.9"}
        merged.update(headers or {})
        request = urllib.request.Request(
            url, headers=merged, method=method, data=b"" if method == "POST" else None
        )
        try:
            with self.opener.open(request, timeout=HTTP_TIMEOUT) as response:
                status, body = response.status, response.read(MAX_BODY + 1)
        except urllib.error.HTTPError as exc:
            status, body = exc.code, exc.read(MAX_BODY + 1)
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise MsDownloadError(f"Cannot reach {urlsplit(url).netloc}: {exc}") from exc
        self.debug(f"{method} {url.split('?')[0]} -> HTTP {status}, {len(body)} bytes")
        return status, body


def _api(web: _Web, name: str, params: dict, referer: str, post_fallback: bool = False) -> dict:
    url = f"{MS_BASE}/software-download-connector/api/{name}?{urlencode(params)}"
    headers = {"Referer": referer}  # without it Microsoft's servers may deny the request
    status, body = web.request(url, "GET", headers)
    if post_fallback and status in (403, 405):
        web.debug(f"{name}: GET refused, retrying with POST")
        status, body = web.request(url, "POST", headers)
    if status != 200:
        hint = " (the session id was probably not accepted)" if status == 403 else ""
        raise MsDownloadError(f"{name}: HTTP {status}{hint}.")
    try:
        data = json.loads(body.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise MsDownloadError(f"{name}: response is not valid JSON.") from exc
    if not isinstance(data, dict):
        raise MsDownloadError(f"{name}: unexpected response.")
    errors = list(data.get("Errors") or [])
    container = data.get("ValidationContainer")
    if isinstance(container, dict):
        errors += list(container.get("Errors") or []) + list(container.get("ErrorList") or [])
    if errors:
        text = "; ".join(
            str(e.get("Value") or e) if isinstance(e, dict) else str(e) for e in errors
        )
        advice = (
            "Microsoft's anti-abuse system rejected the request. Reports tie this to the IP "
            "address's recent request history and say repeated attempts make it worse: wait "
            "before retrying, or download the ISO in a browser."
            if "sentinel" in text.lower() or "715-123130" in text
            else "Try again later or download the ISO in a browser."
        )
        raise MsDownloadError(f"Microsoft refused the request ({name}): {text} -- {advice}")
    return data


# --------------------------------------------------------------------------
# Resolving the download link
# --------------------------------------------------------------------------
def complete_ovdf_challenge(web: _Web, session_id: str) -> None:
    """ov-df.microsoft.com handshake, the way Mido/Fido do it: fetch mdt.js,
    read the token (w=...) and ticks (rticks="...") from it, send them back
    together with the current time in milliseconds."""
    status, body = web.request(f"{OVDF_BASE}/mdt.js?" + urlencode(
        {"instanceId": OVDF_INSTANCE, "PageId": "si", "session_id": session_id}))
    if status != 200:
        raise MsDownloadError(f"ov-df challenge: HTTP {status}.")
    text = body.decode("utf-8", errors="replace")
    token = re.search(r"[?&]w=([A-Fa-f0-9]+)", text)
    ticks = re.search(r'rticks="\+?([0-9]+)', text)
    if not token or not ticks:
        raise MsDownloadError("Could not extract the ov-df challenge values (Microsoft changed it?).")
    time.sleep(0.2)
    status, _ = web.request(f"{OVDF_BASE}/?" + urlencode({
        "session_id": session_id, "CustomerId": OVDF_INSTANCE, "PageId": "si",
        "w": token.group(1), "mdt": int(time.time() * 1000), "rticks": ticks.group(1)}))
    if status >= 400:
        raise MsDownloadError(f"ov-df reply: HTTP {status}.")


_OPTION_RE = re.compile(r'<option[^>]*\bvalue="(\d+)"[^>]*>([^<]*)</option>', re.I)


def discover_edition_id(page_html: str) -> int | None:
    """Product edition id of the Windows 11 ISO, read from the download page."""
    for value, text in _OPTION_RE.findall(page_html):
        low = text.lower()
        if "windows 11" in low and "arm" not in low:
            return int(value)
    return None


def _skus_of(data: dict) -> list[dict]:
    skus = data.get("Skus")
    if isinstance(skus, list):
        return [s for s in skus if isinstance(s, dict)]
    raise MsDownloadError("Language list not found in Microsoft's response.")


def pick_sku(skus: list[dict], language: str) -> dict:
    wanted = language.strip().lower()
    for sku in skus:
        names = (str(sku.get("Language", "")), str(sku.get("LocalizedLanguage", "")))
        if wanted in (n.lower() for n in names):
            return sku
    available = ", ".join(sorted(str(s.get("Language", "?")) for s in skus))
    raise MsDownloadError(f"Language {language!r} not offered. Available: {available}")


@dataclass
class IsoLink:
    url: str
    filename: str
    expires: str | None = None


def filename_from_url(url: str) -> str:
    name = unquote(Path(urlsplit(url).path).name)
    if not name.lower().endswith(".iso"):
        raise MsDownloadError(f"The link does not point to an .iso file: {name!r}")
    if "/" in name or "\\" in name or name.startswith("."):
        raise MsDownloadError("Suspicious file name in the download link.")
    return name


def resolve_iso(
    language: str = "Ukrainian",
    arch: str = "x64",
    locale: str = "en-US",
    edition_id: int | None = None,
    debug=None,
) -> IsoLink:
    web = _Web(debug)
    session_id = str(uuid.uuid4())
    page_url = f"{MS_BASE}/{locale.lower()}/software-download/windows11"

    status, body = web.request(page_url)
    if status != 200:
        raise MsDownloadError(f"Download page: HTTP {status}.")
    if edition_id is None:
        edition_id = discover_edition_id(body.decode("utf-8", errors="replace"))
        if edition_id is None:
            edition_id = DEFAULT_EDITION_ID
            web.debug(f"edition id not found on the page; using fallback {edition_id}")
        else:
            web.debug(f"edition id from the page: {edition_id}")

    status, _ = web.request(f"{VLS_URL}?{urlencode({'org_id': ORG_ID, 'session_id': session_id})}")
    if status >= 400:
        raise MsDownloadError(f"Session registration failed: HTTP {status}.")
    complete_ovdf_challenge(web, session_id)
    web.debug("session registered, ov-df challenge completed")

    skus = _skus_of(_api(web, "getskuinformationbyproductedition", {
        "profile": PROFILE, "ProductEditionId": edition_id, "SKU": "undefined",
        "friendlyFileName": "undefined", "Locale": locale, "sessionID": session_id,
    }, page_url, post_fallback=True))
    sku = pick_sku(skus, language)
    web.debug(f"SKU {sku.get('Id')} for {sku.get('Language')}")

    links = _api(web, "GetProductDownloadLinksBySku", {
        "profile": PROFILE, "ProductEditionId": "undefined", "SKU": sku.get("Id"),
        "friendlyFileName": "undefined", "Locale": locale, "sessionID": session_id,
    }, page_url)
    options = [o for o in links.get("ProductDownloadOptions") or [] if isinstance(o, dict) and o.get("Uri")]
    if not options:
        raise MsDownloadError("Microsoft returned no download links.")
    wanted_type = ARCH_DOWNLOAD_TYPE.get(arch.lower())
    chosen = (
        next((o for o in options if wanted_type is not None and o.get("DownloadType") == wanted_type), None)
        or next((o for o in options if f"_{arch.lower()}_" in str(o["Uri"]).lower().split("?")[0]), None)
        or (options[0] if len(options) == 1 else None)
    )
    if chosen is None:
        names = ", ".join(filename_from_url(o["Uri"]) for o in options)
        raise MsDownloadError(f"No {arch} image among the offered files: {names}")
    return IsoLink(chosen["Uri"], filename_from_url(chosen["Uri"]), links.get("DownloadExpirationDatetime"))


# --------------------------------------------------------------------------
# Downloading
# --------------------------------------------------------------------------
def download_file(url: str, dest: Path, log=print, _retry: bool = True) -> int:
    """Download ``url`` to ``dest`` via ``dest.name + '.part'`` (resumable)."""
    part = dest.with_name(dest.name + ".part")
    offset = part.stat().st_size if part.exists() else 0
    headers = {"User-Agent": USER_AGENT}
    if offset:
        headers["Range"] = f"bytes={offset}-"
        log(f"Resuming {dest.name} at {offset / 2**20:.0f} MiB")
    try:
        response = urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=HTTP_TIMEOUT)
    except urllib.error.HTTPError as exc:
        if exc.code == 416 and offset and _retry:  # stale/complete partial file: start over
            part.unlink(missing_ok=True)
            return download_file(url, dest, log, _retry=False)
        raise MsDownloadError(f"Download failed: HTTP {exc.code}.") from exc
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise MsDownloadError(f"Download failed: {exc}") from exc

    with response:
        length = response.headers.get("Content-Length")
        if offset and response.status == 206:
            if not (response.headers.get("Content-Range") or "").startswith(f"bytes {offset}-"):
                raise MsDownloadError("Unexpected Content-Range in the resumed download.")
            mode, expected = "ab", (offset + int(length)) if length else None
        else:  # fresh download, or the server ignored the Range header
            offset, mode, expected = 0, "wb", int(length) if length else None
        size, started, last_report = offset, time.monotonic(), 0.0
        try:
            with open(part, mode) as out:
                while chunk := response.read(1024 * 1024):
                    out.write(chunk)
                    size += len(chunk)
                    now = time.monotonic()
                    if now - last_report >= 10:
                        last_report = now
                        pct = f"{size * 100 / expected:.0f}%" if expected else f"{size / 2**20:.0f} MiB"
                        speed = (size - offset) / max(now - started, 1e-6) / 2**20
                        log(f"  {dest.name}: {pct} ({speed:.1f} MiB/s)")
                out.flush()
                os.fsync(out.fileno())
        except (OSError, TimeoutError, urllib.error.URLError) as exc:
            raise MsDownloadError(f"Download interrupted at {size} bytes: {exc} (run again to resume)") from exc
    if expected is not None and size != expected:
        raise MsDownloadError(f"Incomplete download: {size} of {expected} bytes (run again to resume).")
    os.replace(part, dest)
    return size


def prune_isos(directory: Path, filename: str, keep: int) -> list[Path]:
    """Keep the ``keep`` newest ISOs of the same product; delete older ones.

    "Same product" = the file name with the trailing ``_<build>_<revision>``
    replaced by wildcards (Windows11_Client_x64_uk-ua_*_*.iso).
    """
    match = re.match(r"^(.*)_\d+_\d+(\.iso)$", filename, re.I)
    if not match:
        return []
    family = sorted(
        directory.glob(f"{match.group(1)}_*_*{match.group(2)}"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    removed = []
    for path in family[max(keep, 1):]:
        path.unlink()
        removed.append(path)
    return removed


# --------------------------------------------------------------------------
# Entry points
# --------------------------------------------------------------------------
@dataclass
class IsoResult:
    status: str  # "downloaded" | "up-to-date" | "url"
    filename: str
    path: Path | None = None
    url: str | None = None
    pruned: list[Path] = field(default_factory=list)


def update(
    dest_dir: str | os.PathLike[str] | None = None,
    language: str = "Ukrainian",
    arch: str = "x64",
    locale: str = "en-US",
    edition_id: int | None = None,
    keep: int = DEFAULT_KEEP,
    url_only: bool = False,
    debug: bool = False,
    log=print,
) -> IsoResult:
    """Resolve the current ISO and download it unless it is already present."""
    folder = Path(dest_dir).expanduser() if dest_dir else Path(__file__).resolve().parent
    if not folder.is_dir():
        raise MsDownloadError(f"Destination folder not found: {folder}")

    link = resolve_iso(language, arch, locale, edition_id, (lambda m: log(f"debug: {m}")) if debug else None)
    log(f"Current image: {link.filename}" + (f" (link valid until {link.expires})" if link.expires else ""))
    if url_only:
        return IsoResult("url", link.filename, url=link.url)

    dest = folder / link.filename
    if dest.is_file() and dest.stat().st_size > 0:
        return IsoResult("up-to-date", link.filename, dest)

    size = download_file(link.url, dest, log)
    log(f"Downloaded {dest.name} ({size / 2**30:.2f} GiB)")
    pruned = prune_isos(folder, link.filename, keep)
    return IsoResult("downloaded", link.filename, dest, pruned=pruned)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("--dest", metavar="DIR", help="folder for the ISO (default: next to this script)")
    parser.add_argument("--lang", default="Ukrainian", metavar="NAME",
                        help="language as named by Microsoft, e.g. Ukrainian, English (default: Ukrainian)")
    parser.add_argument("--arch", default="x64", metavar="ARCH", help="x64 or arm64 (default: x64)")
    parser.add_argument("--locale", default="en-US", metavar="LOC", help="API locale (default: en-US)")
    parser.add_argument("--edition-id", type=int, metavar="N",
                        help="product edition id; normally discovered from the download page")
    parser.add_argument("--keep", type=int, default=DEFAULT_KEEP, metavar="N",
                        help=f"ISOs of this kind to keep, newest first (default: {DEFAULT_KEEP})")
    parser.add_argument("--url-only", action="store_true", help="print the signed download URL and exit")
    parser.add_argument("--debug", action="store_true", help="print every request and status")
    args = parser.parse_args(argv)

    try:
        result = update(args.dest, args.lang, args.arch, args.locale, args.edition_id,
                        args.keep, args.url_only, args.debug)
    except (MsDownloadError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    if result.status == "url":
        print(result.url)
    elif result.status == "up-to-date":
        print(f"Up to date: {result.filename}")
    else:
        print(f"Downloaded: {result.path}")
        for path in result.pruned:
            print(f"Deleted:    {path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
