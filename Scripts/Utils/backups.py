"""Numbered backups shared by the builder and updater scripts.

Convention: ``name.ext`` is backed up as ``name_<N>.ext``. N grows over time,
so the highest number is always the newest backup.
Only Python's standard library is required.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Iterable


def _backup_pattern(path: Path) -> re.Pattern[str]:
    return re.compile(rf"^{re.escape(path.stem)}_(\d+){re.escape(path.suffix)}$")


def next_backup_path(destination: Path) -> Path:
    """Return ``<stem>_<N><suffix>`` where N is one more than the highest
    existing number for this destination (1 if there are none yet)."""
    pattern = _backup_pattern(destination)
    highest = 0
    for item in destination.parent.iterdir():
        match = pattern.match(item.name)
        if match:
            highest = max(highest, int(match.group(1)))
    return destination.with_name(f"{destination.stem}_{highest + 1}{destination.suffix}")


def prune_backups(directory: Path, filenames: Iterable[str], keep: int) -> list[Path]:
    """Delete old ``<stem>_<N><suffix>`` backups, keeping the ``keep`` newest
    (highest numbers) for every name in ``filenames``. Returns deleted paths."""
    removed: list[Path] = []
    for filename in filenames:
        pattern = _backup_pattern(Path(filename))
        found = sorted(
            (
                (int(m.group(1)), item)
                for item in directory.iterdir()
                if (m := pattern.match(item.name))
            ),
            key=lambda pair: pair[0],
            reverse=True,
        )
        for _, item in found[max(keep, 0):]:
            item.unlink()
            removed.append(item)
    return removed
