"""«موقف بقرار» — the four-minute decision step for parents (docs/MAWAQIF.md).

One bank, `knowledge_base/curriculum/mawaqif/mawaqif.json`, with its English
twin under `curriculum/i18n/en/mawaqif/` (content_lang.localised). Each item
is a situation from the parent's day for one age band, three reasonable
responses each with what happens now and later, one hadith card from the
Sahihayn (checked whole by ops/tools/check_scripture_coverage.py through
ops/tools/content_surfaces.py), one idea and one step.

Nothing here is stored per family: the app keeps which steps a parent went
through, and a step the parent commits to becomes an ordinary follow-up
(`POST /api/children/{id}/followups` with source='mawqif').
"""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any, Optional

from app.core.taxonomy import canonical_age_group
from app.services import content_lang

logger = logging.getLogger(__name__)

BANK_DIR = Path(__file__).resolve().parents[3] / "knowledge_base" / "curriculum" / "mawaqif"
BANK_FILE = "mawaqif.json"


def _valid(item: Any) -> bool:
    """The shape the app renders. A malformed item is dropped, not served."""
    if not isinstance(item, dict):
        return False
    if not all(isinstance(item.get(k), str) and item[k].strip()
               for k in ("id", "age_group", "topic", "title", "situation", "idea", "step")):
        return False
    choices = item.get("choices")
    if not isinstance(choices, list) or len(choices) != 3:
        return False
    for c in choices:
        if not isinstance(c, dict) or not all(
                isinstance(c.get(k), str) and c[k].strip() for k in ("key", "text", "now", "later")):
            return False
    ev = item.get("evidence")
    return isinstance(ev, dict) and all(
        isinstance(ev.get(k), str) and ev[k].strip() for k in ("text_ar", "source"))


def load(lang: Optional[str] = None) -> list[dict[str, Any]]:
    path = content_lang.localised(BANK_DIR, BANK_FILE, lang)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        logger.warning("mawaqif bank unreadable: %s", path)
        return []
    if not isinstance(data, dict) or data.get("is_published") is False:
        return []
    items = data.get("items")
    return [i for i in items if _valid(i)] if isinstance(items, list) else []


def for_age(age_group: str, lang: Optional[str] = None) -> list[dict[str, Any]]:
    """The published steps for one child band, in bank order."""
    band = canonical_age_group(age_group)
    return [i for i in load(lang) if i["age_group"] == band]
