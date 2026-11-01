"""Restore keys — a reinstall gets its family back without the open door.

Android's Auto Backup restores the app's plain SharedPreferences — and with
them `tg_device_id_backup` — onto a reinstalled or new phone, but never the
session token, which lives in the keystore-encrypted storage the backup rules
exclude. Until now that restored id minted a session bare, with no proof
(routers/chat.py), and got its family back: the same door that let anyone who
learned a device id open that family (audit H5, the identity review of PR #175).

A restore key closes it without taking the restore away. A session that is
not itself a bare mint asks for one (POST /api/device/restore-key); the app
keeps it beside the backed-up id, so the backup carries both; and a mint that
presents it (header X-Device-Restore) is served as that device — the key
decides, like a token proof does. Once SESSION_MINT_ENFORCE is on, a mint for
a known device with neither is moved to a new, empty device instead.

One key per device. Asking again replaces it (the old one stops working), the
server keeps only sha256(key), and an account deletion removes the row with
every other row keyed by device_id (routers/privacy.py erase_account).
"""
from __future__ import annotations

import logging
import secrets
import sqlite3
from typing import Optional

from app.db.init_db import get_conn, hash_token

logger = logging.getLogger(__name__)

TABLE = "device_restore_keys"
CREATE_TABLE = (
    "CREATE TABLE IF NOT EXISTS device_restore_keys ("
    " device_id    TEXT PRIMARY KEY,"
    " key_hash     TEXT NOT NULL UNIQUE,"
    " created_at   TEXT NOT NULL DEFAULT (datetime('now')),"
    " last_used_at TEXT)"
)

HEADER = "X-Device-Restore"
PREFIX = "tgr_"


def _generate() -> str:
    return PREFIX + secrets.token_hex(32)


def issue(device_id: str) -> str:
    """A new restore key for the device; any earlier one stops working."""
    key = _generate()
    conn = get_conn()
    try:
        conn.execute(
            "INSERT INTO device_restore_keys (device_id, key_hash) VALUES (?, ?) "
            "ON CONFLICT(device_id) DO UPDATE SET key_hash = excluded.key_hash, "
            "created_at = datetime('now'), last_used_at = NULL",
            (device_id, hash_token(key)),
        )
        conn.commit()
    finally:
        conn.close()
    return key


def device_for(key: Optional[str]) -> Optional[str]:
    """The device a restore key belongs to, or None. Marks it used."""
    if not key or not key.startswith(PREFIX) or len(key) > 128:
        return None
    digest = hash_token(key)
    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT device_id FROM device_restore_keys WHERE key_hash = ?", (digest,)
        ).fetchone()
        if row is None:
            return None
        conn.execute(
            "UPDATE device_restore_keys SET last_used_at = datetime('now') WHERE key_hash = ?",
            (digest,),
        )
        conn.commit()
        return row["device_id"]
    except sqlite3.OperationalError:
        logger.exception("restore key lookup failed")
        return None
    finally:
        conn.close()
