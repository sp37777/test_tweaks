#!/usr/bin/env python3
"""Generate Windows unattended setup XML variants.

The source XML is never modified. Three output files are written next to this
script: Enterprise-key, IoT Enterprise LTSC-key, and firmware/no-key variants.
Only Python's standard library is required.

The XML is NOT parsed and re-serialized. Instead the few needed lines are
inserted into the original text, so everything else stays byte-for-byte
identical to the source: line endings (CRLF), indentation, comments, character
references such as &#xAB; / &#x2026; / &#x2019;, and the BOM (if any).
The XML parser is used only to check that the result is still well-formed.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

WCM_NS = "http://schemas.microsoft.com/WMIConfig/2002/State"

ENTERPRISE_KEY = "M7XTQ-FN8P6-TTKYV-9D4CC-J462D"
IOT_ENTERPRISE_LTSC_KEY = "CGK42-GYN6Y-VD22B-BX98W-J8JXD"

COMMAND_DESCRIPTION = "Launch Master GUI"
COMMAND_PATH = (
    'cmd /c "for %i in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) '
    'do if exist %i:\\ventoy\\script\\winpe.cmd '
    '(%i:\\ventoy\\script\\winpe.cmd -c "10_choices.ini")"'
)

OUTPUTS = (
    ("unattend_10_enterprise_key.xml", ENTERPRISE_KEY),
    ("unattend_10_LTSC_IoT_key.xml", IOT_ENTERPRISE_LTSC_KEY),
    ("unattend_10_no_key.xml", None),
)

# <settings pass="windowsPE"> ... </settings>
_PE_RE = re.compile(
    r"""(<settings\b[^>]*\bpass\s*=\s*["']windowsPE["'][^>]*>)(.*?)(</settings>)""",
    re.S,
)
# <component name="Microsoft-Windows-Setup" ...> ... </component>
_SETUP_RE = re.compile(
    r"""(<component\b[^>]*\bname\s*=\s*["']Microsoft-Windows-Setup["'][^>]*>)(.*?)(</component>)""",
    re.S,
)


class BuildError(Exception):
    """Raised when the source XML cannot safely be processed."""


# --------------------------------------------------------------------------
# Small text helpers
# --------------------------------------------------------------------------
def _indent_of_tag(text: str, pos: int) -> str | None:
    """Indentation of the line on which ``pos`` starts, if only whitespace
    precedes ``pos`` on that line; otherwise None (tag is not at line start)."""
    line_start = text.rfind("\n", 0, pos) + 1
    prefix = text[line_start:pos]
    return prefix if prefix.strip() == "" else None


def _insert_lines(text: str, pos: int, lines: list[str], indent: str, nl: str) -> str:
    """Insert ``lines`` (already relative to ``indent``) on their own lines
    before the tag that starts at ``pos`` (which must be at a line start)."""
    line_start = text.rfind("\n", 0, pos) + 1
    block = "".join(f"{indent}{line}{nl}" for line in lines)
    return text[:line_start] + block + text[line_start:]


def _set_or_add_child(
    inner: str, tag: str, value: str, before_tag: str | None, child_indent: str, nl: str
) -> str:
    """Within ``inner`` (the content of a parent element) set <tag> text, or add
    it on its own line. If added, it goes before <before_tag> if present, else
    at the end of ``inner``."""
    value = escape(value)
    m = re.search(rf"(<{tag}\b[^>]*>)(.*?)(</{tag}>)", inner, re.S)
    if m:
        return inner[: m.start(2)] + value + inner[m.end(2) :]

    element = f"<{tag}>{value}</{tag}>"
    if before_tag:
        b = re.search(rf"<{before_tag}\b", inner)
        if b and _indent_of_tag(inner, b.start()) is not None:
            return _insert_lines(inner, b.start(), [element], child_indent, nl)
    # Append at the end: inner normally ends with "\n<indent of closing tag>".
    stripped_end = len(inner.rstrip(" \t"))
    return inner[:stripped_end] + child_indent + element + nl + inner[stripped_end:]


# --------------------------------------------------------------------------
# Edits inside one Microsoft-Windows-Setup component
# --------------------------------------------------------------------------
def _set_product_key(body: str, key: str, unit: str, nl: str) -> str:
    """Put <Key> into <UserData><ProductKey>, leaving everything else alone."""
    if re.search(r"<ProductKey\s*/>", body):
        raise BuildError("Self-closing <ProductKey/> is not supported.")

    pk = re.search(r"(<ProductKey\b[^>]*>)(.*?)(</ProductKey>)", body, re.S)
    if pk is None:
        # No ProductKey at all: add one to the start of <UserData> (or create it).
        ud = re.search(r"(<UserData\b[^>]*>)(.*?)(</UserData>)", body, re.S)
        if ud is None:
            raise BuildError("No <UserData>/<ProductKey> in Microsoft-Windows-Setup.")
        ud_indent = _indent_of_tag(body, ud.start()) or ""
        pk_indent = ud_indent + unit
        new_pk = (
            f"{nl}{pk_indent}<ProductKey>{nl}"
            f"{pk_indent}{unit}<Key>{escape(key)}</Key>{nl}"
            f"{pk_indent}{unit}<WillShowUI>OnError</WillShowUI>{nl}"
            f"{pk_indent}</ProductKey>"
        )
        return body[: ud.end(1)] + new_pk + body[ud.end(1) :]

    pk_indent = _indent_of_tag(body, pk.start()) or ""
    child_indent = pk_indent + unit
    inner = pk.group(2)

    # Key first (schema order: Key, WillShowUI), then WillShowUI.
    inner = _set_or_add_child(inner, "Key", key, "WillShowUI", child_indent, nl)
    inner = _set_or_add_child(inner, "WillShowUI", "OnError", None, child_indent, nl)
    return body[: pk.start(2)] + inner + body[pk.end(2) :]


def _add_winpe_command(body: str, wcm: str, unit: str, nl: str) -> str:
    """Add the launcher <RunSynchronousCommand> once (skipped if already there)."""
    path_xml = escape(COMMAND_PATH)
    rs = re.search(r"(<RunSynchronous\b[^>]*>)(.*?)(</RunSynchronous>)", body, re.S)

    if rs is not None and path_xml in rs.group(2):
        return body  # already present (re-run on an already built file)

    if rs is None:
        # Create the whole <RunSynchronous> block at the end of the component.
        close_pos = len(body.rstrip(" \t"))
        comp_indent = body[close_pos:]  # indentation of </component>
        base = comp_indent + unit
        block = (
            f"{base}<RunSynchronous>{nl}"
            f"{base}{unit}<RunSynchronousCommand {wcm}:action=\"add\">{nl}"
            f"{base}{unit}{unit}<Order>1</Order>{nl}"
            f"{base}{unit}{unit}<Description>{escape(COMMAND_DESCRIPTION)}</Description>{nl}"
            f"{base}{unit}{unit}<Path>{path_xml}</Path>{nl}"
            f"{base}{unit}</RunSynchronousCommand>{nl}"
            f"{base}</RunSynchronous>{nl}"
        )
        return body[:close_pos] + block + body[close_pos:]

    used = {
        int(n)
        for n in re.findall(r"<Order>\s*(\d+)\s*</Order>", rs.group(2))
    }
    order = 1
    while order in used:
        order += 1

    close_pos = rs.start(3)
    rs_indent = _indent_of_tag(body, close_pos)
    if rs_indent is None:
        raise BuildError("</RunSynchronous> is not at the start of a line.")
    cmd_indent = rs_indent + unit
    lines = [
        f'<RunSynchronousCommand {wcm}:action="add">',
        f"{unit}<Order>{order}</Order>",
        f"{unit}<Description>{escape(COMMAND_DESCRIPTION)}</Description>",
        f"{unit}<Path>{path_xml}</Path>",
        "</RunSynchronousCommand>",
    ]
    return _insert_lines(body, close_pos, lines, cmd_indent, nl)


# --------------------------------------------------------------------------
# One output variant
# --------------------------------------------------------------------------
def prepare_variant(source_text: str, product_key: str | None) -> str:
    nl = "\r\n" if "\r\n" in source_text else "\n"
    unit = "\t" if re.search(r"\n[ ]*\t", source_text) else "  "

    m = re.search(r'xmlns:(\w+)\s*=\s*["\']' + re.escape(WCM_NS) + r'["\']', source_text)
    wcm = m.group(1) if m else "wcm"
    if m is None:
        raise BuildError(f"Namespace {WCM_NS} is not declared in the source XML.")

    pe = _PE_RE.search(source_text)
    if pe is None:
        raise BuildError("No <settings pass='windowsPE'> section found.")

    pe_body = pe.group(2)
    count = 0

    def edit_component(mc: re.Match[str]) -> str:
        nonlocal count
        count += 1
        body = mc.group(2)
        if product_key is not None:
            body = _set_product_key(body, product_key, unit, nl)
        # The no-key variant deliberately leaves ProductKey untouched.
        body = _add_winpe_command(body, wcm, unit, nl)
        return mc.group(1) + body + mc.group(3)

    new_pe_body = _SETUP_RE.sub(edit_component, pe_body)
    if count == 0:
        raise BuildError(
            "No Microsoft-Windows-Setup component found under settings pass='windowsPE'."
        )

    result = source_text[: pe.start(2)] + new_pe_body + source_text[pe.end(2) :]

    # Only a well-formedness check; the parsed tree is thrown away.
    try:
        ET.fromstring(result.encode("utf-8"))
    except ET.ParseError as exc:
        raise BuildError(f"Generated XML failed validation: {exc}") from exc
    return result


def next_backup_path(destination: Path) -> Path:
    """Return ``<stem>_<N><suffix>`` where N is one more than the highest
    existing number for this destination (1 if there are none yet)."""
    pattern = re.compile(
        rf"^{re.escape(destination.stem)}_(\d+){re.escape(destination.suffix)}$"
    )
    highest = 0
    for item in destination.parent.iterdir():
        match = pattern.match(item.name)
        if match:
            highest = max(highest, int(match.group(1)))
    return destination.with_name(f"{destination.stem}_{highest + 1}{destination.suffix}")


def _write_outputs_atomically(outputs: dict[Path, bytes]) -> list[tuple[Path, Path]]:
    """Stage every output first, then back up existing files and replace them.

    An existing destination is renamed to the next free ``_N`` name instead of
    being overwritten. Returns the (original, backup) pairs that were made.
    """
    staged: dict[Path, Path] = {}
    backups: list[tuple[Path, Path]] = []
    try:
        for destination, content in outputs.items():
            fd, temp_name = tempfile.mkstemp(
                prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
            )
            temp_path = Path(temp_name)
            staged[destination] = temp_path
            with os.fdopen(fd, "wb") as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())

        for destination, temp_path in staged.items():
            if destination.exists():
                backup = next_backup_path(destination)
                os.replace(destination, backup)
                backups.append((destination, backup))
            os.replace(temp_path, destination)
    finally:
        for temp_path in staged.values():
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass
    return backups


def build(base_name: str = "autounattend") -> tuple[list[Path], list[tuple[Path, Path]]]:
    """Build the three XML variants from ``<base_name>.xml``.

    ``base_name`` is a filename stem, not a path. The source and output files
    are located in the same directory as this module. The source is never
    overwritten. Output files that already exist are renamed to
    ``<name>_<N>.xml`` (next free N) before the new ones are written.
    Returns (generated paths, list of (original, backup) pairs).
    """
    if not isinstance(base_name, str) or not base_name.strip():
        raise BuildError("Base name must be a non-empty filename stem.")

    base_name = base_name.strip()
    if Path(base_name).name != base_name or base_name in {".", ".."}:
        raise BuildError("Base name must not contain a directory path.")
    if base_name.lower().endswith(".xml"):
        base_name = base_name[:-4]
    if not base_name:
        raise BuildError("Base name must not be empty.")

    script_dir = Path(__file__).resolve().parent
    source_path = script_dir / f"{base_name}.xml"
    if not source_path.is_file():
        raise BuildError(f"Source XML not found: {source_path}")

    try:
        source_bytes = source_path.read_bytes()
        # Decode only; no newline translation, so CRLF is preserved.
        source_text = source_bytes.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise BuildError(f"Cannot read source XML '{source_path}': {exc}") from exc

    prepared: dict[Path, bytes] = {}
    for filename, key in OUTPUTS:
        destination = script_dir / filename
        prepared[destination] = prepare_variant(source_text, key).encode("utf-8")

    try:
        backups = _write_outputs_atomically(prepared)
    except OSError as exc:
        raise BuildError(f"Cannot write generated XML files: {exc}") from exc

    return list(prepared), backups


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Generate Enterprise, IoT Enterprise LTSC, and firmware-key unattend XML variants."
    )
    parser.add_argument(
        "--base-name",
        default="autounattend",
        metavar="NAME",
        help="source XML filename without .xml (default: autounattend)",
    )
    args = parser.parse_args(argv)

    try:
        generated, backups = build(args.base_name)
    except BuildError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    for original, backup in backups:
        print(f"Backup:    {original.name} -> {backup.name}")
    for path in generated:
        print(f"Generated: {path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
