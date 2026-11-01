"""Closing the bare mint (audit H5) and the Google-link takeover (PR #175).

Until v37, `POST /api/chat/sessions` gave a session to anyone who claimed a
known device id with no proof — and a reinstall restored from a phone backup
got its family back exactly that way. Now:

  * every token records how it was minted (api_tokens.mint_kind), and a proof
    that was itself bare stays bare;
  * a restore key (services/restore_keys.py), kept beside the backed-up device
    id, proves the device at the mint — and a bare session cannot get one;
  * with SESSION_MINT_ENFORCE on, a bare mint becomes a new, empty device for
    builds that adopt the answered id, and a 401 for older ones;
  * a bare session cannot confirm a Google link, a first push token on an
    established device waits out its pause before confirming, and an
    unvouched token change takes confirmed back;
  * what a parent deleted on one phone is not merged back from another
    (services/merge_tombstones.py).
"""
from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from app.db.init_db import get_conn
from app.routers import identity
from app.routers.privacy import erase_account, erase_child, erase_device_memory
from app.services import child_memory as cm
from app.services import restore_keys
from tests.device_proof_support import prove, register_push


@pytest.fixture
def client():
    from app.main import app
    with TestClient(app) as c:
        yield c


def _mint(client, device: str, *, proof: str | None = None, restore: str | None = None,
          build: int | None = None):
    headers = {}
    if proof:
        headers["Authorization"] = f"Bearer {proof}"
    if restore:
        headers[restore_keys.HEADER] = restore
    if build is not None:
        headers["X-App-Build"] = str(build)
    return client.post("/api/chat/sessions", json={"device_id": device}, headers=headers)


def _session(client, device: str, **kw) -> tuple[dict, str, str]:
    """(auth headers, raw token, the device the server minted for)."""
    r = _mint(client, device, **kw)
    assert r.status_code == 201, r.text
    body = r.json()
    return {"Authorization": f"Bearer {body['token']}"}, body["token"], body["device_id"]


def _kind(token: str) -> str | None:
    from app.services import conversation_store as store
    return store.token_mint_kind(token)


def _child(client, h, name="سالم") -> int:
    r = client.post("/api/children", json={"name": name, "age_group": "4-6"}, headers=h)
    assert r.status_code in (200, 201), r.text
    return r.json()["id"]


def _age(device: str, days: int = 4) -> None:
    """Make the device established: older than the 72-hour cooldown."""
    conn = get_conn()
    for table in ("api_tokens", "chat_sessions", "child_profiles"):
        conn.execute(f"UPDATE {table} SET created_at = datetime(created_at, ?) "
                     "WHERE device_id = ?", (f"-{days} days", device))
    conn.commit()
    conn.close()


def _link(client, h, sub: str):
    with patch("app.routers.identity._verify_google_id_token",
               new=AsyncMock(return_value={"sub": sub, "email": f"{sub}@example.com",
                                           "email_verified": True})):
        r = client.post("/api/identity/link-google", json={"id_token": "x.y.z"}, headers=h)
    assert r.status_code == 200, r.text
    return r.json()


def _confirmed(device: str) -> int | None:
    conn = get_conn()
    row = conn.execute("SELECT confirmed FROM identity_links WHERE device_id = ?",
                       (device,)).fetchone()
    conn.close()
    return None if row is None else int(row[0])


def _children_of(device: str) -> list[str]:
    conn = get_conn()
    names = [r[0] for r in conn.execute(
        "SELECT name FROM child_profiles WHERE device_id = ? ORDER BY id", (device,))]
    conn.close()
    return names


# ── mint_kind ─────────────────────────────────────────────────────────────


def test_every_mint_records_how_it_was_minted(client, monkeypatch):
    monkeypatch.delenv("SESSION_MINT_ENFORCE", raising=False)
    _, first, _ = _session(client, "dev-kinds")
    assert _kind(first) == "new"
    _, proven, _ = _session(client, "dev-kinds", proof=first)
    assert _kind(proven) == "proof"
    _, bare, _ = _session(client, "dev-kinds")                  # known id, no proof
    assert _kind(bare) == "bare"
    # A bare token presented as proof does not launder the session.
    _, laundered, _ = _session(client, "dev-kinds", proof=bare)
    assert _kind(laundered) == "bare"


# ── restore keys ──────────────────────────────────────────────────────────


def test_a_restore_key_brings_a_reinstall_back_to_its_family(client):
    h, _, dev = _session(client, "dev-restore")
    cid = _child(client, h)
    r = client.post("/api/chat/restore-key", headers=h)
    assert r.status_code == 200, r.text
    key = r.json()["restore_key"]
    assert key.startswith("tgr_")

    # The reinstall: the backed-up id and key, no token.
    h2, token2, minted = _session(client, "dev-restore", restore=key)
    assert minted == dev and _kind(token2) == "restore"
    assert client.get(f"/api/children/{cid}", headers=h2).status_code != 404
    # Only the hash is stored.
    conn = get_conn()
    stored = conn.execute("SELECT key_hash FROM device_restore_keys WHERE device_id = ?",
                          (dev,)).fetchone()[0]
    conn.close()
    assert key not in stored


def test_the_key_decides_the_device_not_the_claim(client):
    h, _, _ = _session(client, "dev-key-owner")
    key = client.post("/api/chat/restore-key", headers=h).json()["restore_key"]
    _, _, minted = _session(client, "dev-someone-else", restore=key)
    assert minted == "dev-key-owner"


def test_a_new_key_retires_the_old_one(client, monkeypatch):
    monkeypatch.delenv("SESSION_MINT_ENFORCE", raising=False)
    h, _, _ = _session(client, "dev-rotate")
    old = client.post("/api/chat/restore-key", headers=h).json()["restore_key"]
    new = client.post("/api/chat/restore-key", headers=h).json()["restore_key"]
    assert old != new
    _, token, _ = _session(client, "dev-rotate", restore=old)
    assert _kind(token) == "bare"                                # the old key proves nothing
    _, token, _ = _session(client, "dev-rotate", restore=new)
    assert _kind(token) == "restore"


@pytest.mark.parametrize("key", ["tgr_" + "0" * 64, "garbage", "tgr_" + "a" * 200, ""])
def test_a_wrong_key_proves_nothing(client, monkeypatch, key):
    monkeypatch.delenv("SESSION_MINT_ENFORCE", raising=False)
    _session(client, "dev-wrong")
    _, token, minted = _session(client, "dev-wrong", restore=key)
    assert minted == "dev-wrong" and _kind(token) == "bare"


def test_a_bare_session_gets_no_restore_key(client, monkeypatch):
    monkeypatch.delenv("SESSION_MINT_ENFORCE", raising=False)
    _session(client, "dev-victim-key")
    bare, _, _ = _session(client, "dev-victim-key")
    r = client.post("/api/chat/restore-key", headers=bare)
    assert r.status_code == 403
    assert r.json()["detail"]["code"] == "restore_key_unavailable"


def test_restore_key_needs_a_session(client):
    assert client.post("/api/chat/restore-key").status_code == 401


def test_an_account_deletion_takes_the_restore_key(client):
    h, _, dev = _session(client, "dev-erase-key")
    key = client.post("/api/chat/restore-key", headers=h).json()["restore_key"]
    erase_account(dev)
    assert restore_keys.device_for(key) is None


# ── enforcement ───────────────────────────────────────────────────────────


def test_enforced_bare_mint_becomes_a_new_empty_device(client, monkeypatch):
    owner, _, dev = _session(client, "dev-enforced")
    _child(client, owner)
    monkeypatch.setenv("SESSION_MINT_ENFORCE", "true")

    h, token, minted = _session(client, "dev-enforced", build=121)
    assert minted != dev and _kind(token) == "new"
    assert _children_of(minted) == []
    assert client.get("/api/children", headers=h).json()["count"] == 0
    # The family is untouched.
    assert _children_of(dev) == ["سالم"]


@pytest.mark.parametrize("build", [None, 116])
def test_enforced_bare_mint_from_a_build_that_cannot_adopt_is_refused(client, monkeypatch, build):
    _session(client, "dev-old-build")
    monkeypatch.setenv("SESSION_MINT_ENFORCE", "true")
    assert _mint(client, "dev-old-build", build=build).status_code == 401


def test_enforced_mint_still_serves_a_token_or_a_restore_key(client, monkeypatch):
    h, token, dev = _session(client, "dev-enforced-ok")
    key = client.post("/api/chat/restore-key", headers=h).json()["restore_key"]
    monkeypatch.setenv("SESSION_MINT_ENFORCE", "true")
    assert _session(client, dev, proof=token, build=121)[2] == dev
    assert _session(client, dev, restore=key, build=121)[2] == dev


# ── the Google-link takeover (security review of PR #175) ─────────────────


def test_the_pr175_takeover_fails_at_every_step(client, monkeypatch):
    """The victim: an established family whose phone has no push token (about
    43% of devices). The attacker knows the device id."""
    monkeypatch.delenv("SESSION_MINT_ENFORCE", raising=False)
    monkeypatch.setenv("IDENTITY_CROSS_DEVICE", "1")
    victim, _, vdev = _session(client, "dev-pr175-victim")
    _child(client, victim, "ليلى")
    _age(vdev)

    # 1-3: a bare session on the victim's id, the attacker's FCM token, a proof.
    intruder, itoken, _ = _session(client, vdev)
    assert _kind(itoken) == "bare"
    prove(client, intruder, push_token="fcm-attacker")
    # 4: linking the victim's phone to the attacker's account does not confirm.
    assert _link(client, intruder, "attacker-sub")["ok"] is True
    assert _confirmed(vdev) == 0
    # 5: the attacker's own phone, proven and linked to the same account,
    # pulls nothing.
    phone, _, adev = _session(client, "dev-pr175-attacker")
    prove(client, phone, push_token="fcm-attacker-phone")
    _link(client, phone, "attacker-sub")
    assert _confirmed(adev) == 1
    assert _children_of(adev) == []
    # 7: deleting the attacker's account does not reach the victim.
    assert client.delete("/api/privacy/account?confirm=true", headers=phone).status_code == 200
    assert _children_of(vdev) == ["ليلى"]
    # And the bare session gets no restore key to keep the door open.
    assert client.post("/api/chat/restore-key", headers=intruder).status_code == 403


def test_a_first_token_on_an_established_device_cannot_confirm_until_its_pause_ends(client):
    """Even from a session that is not bare (a pre-v37 token, say): moving a
    family's data is irreversible, so the first-token pause applies."""
    h, token, dev = _session(client, "dev-first-token")
    _child(client, h)
    _age(dev)                                           # established
    conn = get_conn()
    conn.execute("UPDATE api_tokens SET mint_kind = NULL WHERE device_id = ?", (dev,))
    conn.commit()
    conn.close()
    prove(client, h, push_token="fcm-first")
    _link(client, h, "sub-first")
    assert _confirmed(dev) == 0


def test_the_owner_on_a_new_phone_confirms(client):
    h, _, dev = _session(client, "dev-new-owner")
    prove(client, h, push_token="fcm-new-owner")
    _link(client, h, "sub-owner")
    assert _confirmed(dev) == 1


def test_an_unvouched_token_change_takes_confirmed_back(client):
    h, _, dev = _session(client, "dev-unconfirm")
    prove(client, h, push_token="fcm-a")
    _link(client, h, "sub-unconfirm")
    assert _confirmed(dev) == 1
    other, _, _ = _session(client, dev, proof=None)     # bare: no vouching proof
    register_push(client, other, "fcm-b")
    assert _confirmed(dev) == 0


def test_two_proven_phones_of_one_parent_still_merge(client, monkeypatch):
    monkeypatch.setenv("IDENTITY_CROSS_DEVICE", "1")
    old, _, odev = _session(client, "dev-merge-old")
    prove(client, old, push_token="fcm-merge-old")
    _child(client, old, "يوسف")
    _link(client, old, "sub-merge")
    new, _, ndev = _session(client, "dev-merge-new")
    prove(client, new, push_token="fcm-merge-new")
    _link(client, new, "sub-merge")
    assert _children_of(ndev) == ["يوسف"]


# ── merge tombstones ──────────────────────────────────────────────────────


def _pair(monkeypatch, client, sub: str) -> tuple[dict, str, dict, str]:
    monkeypatch.setenv("IDENTITY_CROSS_DEVICE", "1")
    a, _, adev = _session(client, f"dev-{sub}-a")
    prove(client, a, push_token=f"fcm-{sub}-a")
    b, _, bdev = _session(client, f"dev-{sub}-b")
    prove(client, b, push_token=f"fcm-{sub}-b")
    return a, adev, b, bdev


def _fact(client, h, cid, text):
    r = client.post(f"/api/children/{cid}/memory", headers=h,
                    json={"category": "temperament", "fact": text})
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _facts(device: str) -> list[str]:
    conn = get_conn()
    facts = [r[0] for r in conn.execute(
        "SELECT fact FROM child_facts WHERE device_id = ? ORDER BY id", (device,))]
    conn.close()
    return facts


def test_an_erased_child_does_not_come_back_from_the_other_phone(client, monkeypatch):
    a, adev, b, bdev = _pair(monkeypatch, client, "tomb-child")
    _child(client, a, "مريم")
    _link(client, a, "sub-tomb-child")
    _link(client, b, "sub-tomb-child")                       # b pulls مريم
    conn = get_conn()
    bcid = conn.execute("SELECT id FROM child_profiles WHERE device_id = ?", (bdev,)).fetchone()[0]
    conn.close()
    erase_child(bdev, bcid)
    assert _children_of(bdev) == []
    _link(client, b, "sub-tomb-child")                       # re-link: no resurrection
    assert _children_of(bdev) == []
    # Added again on b: a new child, and a's old copy stays out of it.
    _child(client, b, "مريم")
    _link(client, b, "sub-tomb-child")
    assert _children_of(bdev) == ["مريم"]


def test_a_child_created_on_the_other_phone_after_the_erase_still_comes(client, monkeypatch):
    a, adev, b, bdev = _pair(monkeypatch, client, "tomb-later")
    _child(client, a, "عمر")
    _link(client, a, "sub-tomb-later")
    _link(client, b, "sub-tomb-later")
    conn = get_conn()
    bcid = conn.execute("SELECT id FROM child_profiles WHERE device_id = ?", (bdev,)).fetchone()[0]
    conn.execute("UPDATE merge_tombstones SET created_at = datetime('now', '-1 day')")
    conn.commit()
    conn.close()
    erase_child(bdev, bcid)
    conn = get_conn()
    conn.execute("UPDATE merge_tombstones SET created_at = datetime('now', '-1 hour') "
                 "WHERE device_id = ? AND kind = 'child'", (bdev,))
    conn.execute("UPDATE child_profiles SET created_at = datetime('now', '-2 hours') "
                 "WHERE device_id = ?", (adev,))
    conn.commit()
    conn.close()
    # a's عمر predates the erase: stays out. A second child born on a since: comes.
    _child(client, a, "هند")
    _link(client, b, "sub-tomb-later")
    assert _children_of(bdev) == ["هند"]


def test_a_deleted_fact_does_not_come_back(client, monkeypatch):
    a, adev, b, bdev = _pair(monkeypatch, client, "tomb-fact")
    acid = _child(client, a, "سلمى")
    _fact(client, a, acid, "تخاف من الظلام")
    _fact(client, a, acid, "تحب القصص")
    _link(client, a, "sub-tomb-fact")
    _link(client, b, "sub-tomb-fact")
    assert len(_facts(bdev)) == 2
    conn = get_conn()
    bcid, fid = conn.execute(
        "SELECT child_id, id FROM child_facts WHERE device_id = ? AND fact LIKE '%الظلام%'",
        (bdev,)).fetchone()
    conn.close()
    assert cm.delete_fact(bdev, bcid, fid)
    _link(client, b, "sub-tomb-fact")
    assert len(_facts(bdev)) == 1 and "القصص" in _facts(bdev)[0]


@pytest.mark.parametrize("whole_device", [False, True])
def test_wiped_memory_does_not_come_back(client, monkeypatch, whole_device):
    sub = f"tomb-mem-{int(whole_device)}"
    a, adev, b, bdev = _pair(monkeypatch, client, sub)
    acid = _child(client, a, "زين")
    _fact(client, a, acid, "يحب الكرة")
    _link(client, a, f"sub-{sub}")
    _link(client, b, f"sub-{sub}")
    assert len(_facts(bdev)) == 1
    conn = get_conn()
    bcid = conn.execute("SELECT id FROM child_profiles WHERE device_id = ?", (bdev,)).fetchone()[0]
    conn.close()
    if whole_device:
        erase_device_memory(bdev)
    else:
        cm.delete_child_memory(bdev, bcid)
    _link(client, b, f"sub-{sub}")
    assert _facts(bdev) == []
    assert _children_of(bdev) == ["زين"]                      # the child itself stays


def test_no_memory_crosses_onto_a_phone_with_memory_off(client, monkeypatch):
    a, adev, b, bdev = _pair(monkeypatch, client, "mem-off")
    acid = _child(client, a, "نور")
    _fact(client, a, acid, "تحب الرسم")
    _link(client, a, "sub-mem-off")
    conn = get_conn()
    conn.execute("INSERT INTO child_memory_settings (device_id, enabled) VALUES (?, 0) "
                 "ON CONFLICT(device_id) DO UPDATE SET enabled = 0", (bdev,))
    conn.commit()
    conn.close()
    _link(client, b, "sub-mem-off")
    assert _children_of(bdev) == ["نور"] and _facts(bdev) == []


def test_tombstones_are_erased_with_the_account(client, monkeypatch):
    a, adev, b, bdev = _pair(monkeypatch, client, "tomb-erase")
    erase_device_memory(bdev)
    erase_account(bdev)
    conn = get_conn()
    left = conn.execute("SELECT COUNT(*) FROM merge_tombstones WHERE device_id = ?",
                        (bdev,)).fetchone()[0]
    conn.close()
    assert left == 0


def test_link_confirmable_is_what_the_endpoint_uses():
    """The hardening must not be patched around by name: the endpoint calls
    _link_confirmable, which checks the mint and the irreversible access."""
    import inspect
    src = inspect.getsource(identity.link_google_identity)
    assert "_link_confirmable" in src and "request_proven" not in src


def test_a_bare_session_cannot_confirm_even_without_a_pause(client, monkeypatch):
    """A device younger than the cooldown has no first-token pause: the bare
    mint alone is what keeps the stranger's link unconfirmed."""
    monkeypatch.delenv("SESSION_MINT_ENFORCE", raising=False)
    _session(client, "dev-young-victim")
    intruder, _, dev = _session(client, "dev-young-victim")
    prove(client, intruder, push_token="fcm-young-attacker")
    _link(client, intruder, "sub-young-attacker")
    assert _confirmed(dev) == 0
