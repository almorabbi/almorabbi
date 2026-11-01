"""Merge tombstones — what a parent deleted stays deleted across their phones.

The cross-device merge (routers/identity.py `_merge_legacy_device_data`) copies
children and their memory from every phone confirmed to the same Google
account, and it never deletes on the phone it copies from. So a child erased
on one phone, a fact removed from a child's memory, or a memory wiped whole
came back on the next link, from the other phone's copy.

A deletion now leaves a tombstone on the device it happened on, and the merge
copies nothing that a tombstone covers:

  * `child`  — key: the child's normalized name. A source child created on or
    before the tombstone is skipped whole (no profile, no rows) — even onto a
    child of the same name added again later. A child created on the other
    phone after the deletion is a new child and still comes across.
  * `fact`   — key: target child id, category and the fact's text. That exact
    fact is never copied back.
  * `memory` — key: a target child id, or `*` for the whole device. Memory
    rows (facts, follow-ups, weekly plans and their marks) created on or
    before the wipe are not copied; newer ones are.

Rows carry their original created_at when copied, so a copy of something
deleted is as old as the original and stays covered. Keyed by device_id, so
an account deletion takes them with everything else.
"""
from __future__ import annotations

import hashlib
import sqlite3
from typing import Optional

TABLE = "merge_tombstones"
CREATE_TABLE = (
    "CREATE TABLE IF NOT EXISTS merge_tombstones ("
    " device_id  TEXT NOT NULL,"
    " kind       TEXT NOT NULL,"
    " key_hash   TEXT NOT NULL,"
    " created_at TEXT NOT NULL DEFAULT (datetime('now')),"
    " PRIMARY KEY (device_id, kind, key_hash))"
)

KINDS = ("child", "fact", "memory")
ALL_CHILDREN = "*"


def child_key(name: Optional[str]) -> str:
    return (name or "").strip().lower()


def fact_key(child_id: int, category: str, fact: str) -> str:
    return f"{int(child_id)}\x1f{category or ''}\x1f{fact or ''}"


def _hash(kind: str, key: str) -> str:
    return hashlib.sha256(f"{kind}\x1f{key}".encode("utf-8")).hexdigest()


def _present(conn: sqlite3.Connection) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (TABLE,)
    ).fetchone() is not None


def record(conn: sqlite3.Connection, device_id: str, kind: str, key: str) -> None:
    """Inside the caller's transaction. Re-deleting moves the mark forward."""
    if kind not in KINDS:
        raise ValueError(kind)
    if not _present(conn):
        conn.execute(CREATE_TABLE)
    conn.execute(
        "INSERT INTO merge_tombstones (device_id, kind, key_hash) VALUES (?, ?, ?) "
        "ON CONFLICT(device_id, kind, key_hash) DO UPDATE SET created_at = datetime('now')",
        (device_id, kind, _hash(kind, key)),
    )


def since(conn: sqlite3.Connection, device_id: str, kind: str, key: str) -> Optional[str]:
    """When the device last deleted this (UTC 'YYYY-MM-DD HH:MM:SS'), or None."""
    if not _present(conn):
        return None
    row = conn.execute(
        "SELECT created_at FROM merge_tombstones WHERE device_id = ? AND kind = ? AND key_hash = ?",
        (device_id, kind, _hash(kind, key)),
    ).fetchone()
    return row[0] if row else None


def memory_since(conn: sqlite3.Connection, device_id: str, child_id: int) -> Optional[str]:
    """The later of the child's own memory wipe and a whole-device one."""
    marks = [m for m in (since(conn, device_id, "memory", str(int(child_id))),
                         since(conn, device_id, "memory", ALL_CHILDREN)) if m]
    return max(marks) if marks else None


def covers(created_at: Optional[str], mark: Optional[str]) -> bool:
    """A row created at or before the mark is covered. A row with no created_at
    is treated as old: deleted data must not come back on a missing column."""
    if not mark:
        return False
    if not created_at:
        return True

    def norm(ts) -> str:  # SQLite's 'YYYY-MM-DD HH:MM:SS' and ISO's 'T' compare as one
        return str(ts).replace("T", " ")[:19]
    return norm(created_at) <= norm(mark)
