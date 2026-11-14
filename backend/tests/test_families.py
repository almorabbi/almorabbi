"""Tests for «حساب الأسرة» — dual-parent family account (2.0 M3 / v38).

Covers every security and product invariant:
  * Hard lock behind FAMILY_SHARING_ENABLED=1 AND SESSION_MINT_ENFORCE=1.
  * #175 / #179 session & proof guards (bare mint refusal, device_proof_required,
    first-token 72h cooldown, unvouched push-token suspension & reconfirm).
  * Single-use 15-minute hashed invites, immediate bidirectional sync, 2-member cap,
    and zero device_id exposure across all responses.
  * Ongoing sync hooks on weekly-plan marks (with unmark non-resurrection) & follow-ups.
  * Child-deletion isolation + tombstones + mutual partner-deletion confirmation.
  * Leave family, account-deletion isolation + orphan `families` cleanup,
    1-day invite retention, and `v2_gate_check` headline verification.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

from fastapi.testclient import TestClient

from app import curriculum_loader as cl
from app.db.init_db import get_conn
from app.services import conversation_store as store
from app.services import retention
from tests.device_proof_support import prove, register_push

ROOT = Path(__file__).resolve().parents[2]


def _enable_family_sharing(monkeypatch, *, sharing: str = "1", mint_enforce: str = "1") -> None:
    monkeypatch.setenv("FAMILY_SHARING_ENABLED", sharing)
    monkeypatch.setenv("SESSION_MINT_ENFORCE", mint_enforce)


def _mint(client: TestClient, device_id: str, *, proof: str | None = None) -> tuple[dict, str, str]:
    headers = {"Authorization": f"Bearer {proof}"} if proof else {}
    resp = client.post("/api/chat/sessions", json={"device_id": device_id}, headers=headers)
    assert resp.status_code == 201, resp.text
    body = resp.json()
    return {"Authorization": f"Bearer {body['token']}"}, body["token"], body["device_id"]


def _proven_parent(client: TestClient, device_id: str, push_token: str) -> tuple[dict, str, str]:
    h, tok, dev = _mint(client, device_id)
    assert store.token_mint_kind(tok) in ("new", "proof", "restore")
    prove(client, h, push_token=push_token)
    return h, tok, dev


def _create_child(client: TestClient, headers: dict, name: str, age_group: str = "4-6") -> int:
    resp = client.post("/api/children", json={"name": name, "age_group": age_group}, headers=headers)
    assert resp.status_code in (200, 201), resp.text
    return resp.json()["id"]


def _age_device(device_id: str, *, days: int = 4) -> None:
    conn = get_conn()
    try:
        for table in ("api_tokens", "chat_sessions", "child_profiles"):
            conn.execute(
                f"UPDATE {table} SET created_at = datetime(created_at, ?) WHERE device_id = ?",
                (f"-{days} days", device_id),
            )
        conn.commit()
    finally:
        conn.close()


def _lift_proof_cooldown(device_id: str, *, days: int = 4) -> None:
    conn = get_conn()
    try:
        conn.execute(
            "UPDATE push_tokens SET token_since = datetime(token_since, ?) WHERE device_id = ?",
            (f"-{days} days", device_id),
        )
        conn.execute(
            "UPDATE device_proofs SET first_proven_at = datetime(first_proven_at, ?) "
            "WHERE device_id = ?",
            (f"-{days} days", device_id),
        )
        conn.commit()
    finally:
        conn.close()


def _assert_no_device_leak(payload: dict, *device_ids: str) -> None:
    serialized = json.dumps(payload, ensure_ascii=False)
    for dev in device_ids:
        assert dev not in serialized


def test_family_sharing_hard_lock_requires_session_mint_enforce(monkeypatch):
    from app.main import app

    with TestClient(app) as client:
        h, _, _ = _proven_parent(client, "fam-lock-1", "fcm-lock-1")

        # FAMILY_SHARING_ENABLED=1 without SESSION_MINT_ENFORCE -> still locked.
        _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="0")
        assert client.get("/api/app-config").json()["family_sharing_enabled"] is False
        me = client.get("/api/families/me", headers=h)
        assert me.status_code == 200
        assert me.json()["enabled"] is False
        inv = client.post("/api/families/invites", json={"role": "mother"}, headers=h)
        assert inv.status_code == 403 and inv.json()["detail"]["code"] == "family_sharing_locked"

        # SESSION_MINT_ENFORCE=1 without FAMILY_SHARING_ENABLED -> locked.
        _enable_family_sharing(monkeypatch, sharing="0", mint_enforce="1")
        assert client.get("/api/app-config").json()["family_sharing_enabled"] is False
        inv2 = client.post("/api/families/invites", json={"role": "mother"}, headers=h)
        assert inv2.status_code == 403 and inv2.json()["detail"]["code"] == "family_sharing_locked"

        # Both enabled -> unlocked.
        _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
        assert client.get("/api/app-config").json()["family_sharing_enabled"] is True
        me2 = client.get("/api/families/me", headers=h)
        assert me2.status_code == 200 and me2.json()["enabled"] is True


def test_bare_session_and_unproven_guards(monkeypatch):
    from app.main import app

    with TestClient(app) as client:
        # Mint a bare session while enforce is off.
        monkeypatch.setenv("SESSION_MINT_ENFORCE", "0")
        _h1, _, _ = _mint(client, "fam-bare-owner")
        h_bare, tok_bare, _ = _mint(client, "fam-bare-owner")
        assert store.token_mint_kind(tok_bare) == "bare"

        _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")

        # Even if proven via FCM, a bare session cannot access family mutations.
        prove(client, h_bare, push_token="fcm-bare-owner")
        res_bare = client.post("/api/families/invites", json={"role": "parent"}, headers=h_bare)
        assert res_bare.status_code == 403
        assert res_bare.json()["detail"]["code"] == "family_session_not_eligible"

        # An unproven non-bare session is refused with device_proof_required on all 7 POSTs.
        h_unproven, _, _ = _mint(client, "fam-unproven-1")
        for method_path, body in (
            ("/api/families/invites", {"role": "parent"}),
            ("/api/families/join", {"code": "ABCD-EFGH", "role": "parent"}),
            ("/api/families/reconfirm", None),
            ("/api/families/leave", None),
            ("/api/families/deletions/request", {"child_name": "عمر"}),
            ("/api/families/deletions/1/confirm", None),
            ("/api/families/deletions/1/dismiss", None),
        ):
            r = client.post(method_path, json=body, headers=h_unproven)
            assert r.status_code == 403, (method_path, r.text)
            assert r.json()["detail"]["code"] == "device_proof_required", method_path


def test_first_token_cooldown_blocks_irreversible_family_routes(monkeypatch):
    from app.main import app

    _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
    with TestClient(app) as client:
        h, _, dev = _mint(client, "fam-cooldown-dev")
        _create_child(client, h, "طارق")
        _age_device(dev, days=4)
        prove(client, h, push_token="fcm-cooldown-1")

        # During the 72h first-token cooldown, irreversible routes must refuse.
        r1 = client.post("/api/families/invites", json={"role": "father"}, headers=h)
        assert r1.status_code == 403 and r1.json()["detail"]["code"] == "device_proof_cooldown"

        _lift_proof_cooldown(dev, days=4)
        r2 = client.post("/api/families/invites", json={"role": "father"}, headers=h)
        assert r2.status_code == 200 and r2.json()["ok"] is True


def test_unvouched_push_change_suspends_membership_and_stops_sync(monkeypatch):
    from app.main import app

    _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
    with TestClient(app) as client:
        h_a, _, dev_a = _proven_parent(client, "fam-susp-a", "fcm-susp-a1")
        h_b, _, _dev_b = _proven_parent(client, "fam-susp-b", "fcm-susp-b1")
        _create_child(client, h_a, "عمر")

        code = client.post("/api/families/invites", json={"role": "mother"}, headers=h_a).json()["code"]
        assert client.post("/api/families/join", json={"code": code, "role": "father"}, headers=h_b).status_code == 200

        # Partner B adds a new child, while A restores on another install and registers
        # a new push token (unvouched token change -> membership suspended).
        _create_child(client, h_b, "مولود جديد")
        r_key = client.post("/api/chat/restore-key", headers=h_a).json()["restore_key"]
        h_a2_resp = client.post(
            "/api/chat/sessions",
            json={"device_id": dev_a},
            headers={"X-Device-Restore": r_key},
        )
        assert h_a2_resp.status_code == 201 and h_a2_resp.json()["device_id"] == dev_a
        h_a2 = {"Authorization": f"Bearer {h_a2_resp.json()['token']}"}
        register_push(client, h_a2, "fcm-susp-a-unvouched")

        me_a = client.get("/api/families/me", headers=h_a2).json()
        assert me_a["self_member"]["confirmed"] is False

        # Child from B must NOT sync to A while A's membership is unconfirmed.
        names_a = [c["name"] for c in client.get("/api/children", headers=h_a2).json()["children"]]
        assert "مولود جديد" not in names_a

        # Prove on the new token, clear any cooldown, reconfirm -> sync resumes.
        prove(client, h_a2, push_token="fcm-susp-a-unvouched")
        _lift_proof_cooldown(dev_a, days=4)
        reconf = client.post("/api/families/reconfirm", headers=h_a2)
        assert reconf.status_code == 200
        assert reconf.json()["self_member"]["confirmed"] is True

        names_a_after = [c["name"] for c in client.get("/api/children", headers=h_a2).json()["children"]]
        assert "مولود جديد" in names_a_after


def test_pair_sync_bounds_and_zero_device_id_leak(monkeypatch):
    from app.main import app

    _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
    with TestClient(app) as client:
        h_a, _, dev_a = _proven_parent(client, "fam-pair-a-secret", "fcm-pair-a")
        h_b, _, dev_b = _proven_parent(client, "fam-pair-b-secret", "fcm-pair-b")
        h_c, _, dev_c = _proven_parent(client, "fam-pair-c-secret", "fcm-pair-c")

        a_omar = _create_child(client, h_a, "عمر")
        client.put("/api/children/memory/settings", json={"enabled": True}, headers=h_a)
        client.post(
            f"/api/children/{a_omar}/memory",
            json={"category": "temperament", "fact": "يحب القراءة قبل النوم"},
            headers=h_a,
        )
        lesson_id = cl.get_lessons_for_path(cl.get_paths()[0]["id"])[0]["id"]
        lp = client.patch(
            f"/api/program/lessons/{lesson_id}/progress",
            json={"status": "completed", "child_id": a_omar},
            headers=h_a,
        )
        assert lp.status_code == 200, lp.text

        plan_a = client.get(f"/api/children/{a_omar}/weekly-plan", headers=h_a).json()
        week_start = plan_a["week_start"]
        item_key = plan_a["actions"][0]["key"]
        mark_r = client.put(
            f"/api/children/{a_omar}/weekly-plan/marks",
            json={"week_start": week_start, "item_key": item_key},
            headers=h_a,
        )
        assert mark_r.status_code == 200

        # Parent B also starts with their child + memory ON.
        _create_child(client, h_b, "مريم")
        client.put("/api/children/memory/settings", json={"enabled": True}, headers=h_b)

        # Parent A creates a 15m single-use invite; DB holds hash only.
        inv_res = client.post(
            "/api/families/invites",
            json={"role": "mother", "display_name": "أم عمر"},
            headers=h_a,
        )
        assert inv_res.status_code == 200, inv_res.text
        inv_data = inv_res.json()
        code = inv_data["code"]
        assert "-" in code and len(code.replace("-", "")) == 8
        _assert_no_device_leak(inv_data, dev_a, dev_b, dev_c)

        conn = get_conn()
        try:
            stored = conn.execute("SELECT code_hash FROM family_invites ORDER BY id DESC LIMIT 1").fetchone()[0]
            assert len(stored) == 64
            assert code not in stored and code.replace("-", "") not in stored
        finally:
            conn.close()

        # Self-join blocked.
        self_join = client.post("/api/families/join", json={"code": code, "role": "mother"}, headers=h_a)
        assert self_join.status_code in (400, 409)

        # Parent B joins -> immediate bidirectional sync.
        join_res = client.post(
            "/api/families/join",
            json={"code": code, "role": "father", "display_name": "أبو عمر"},
            headers=h_b,
        )
        assert join_res.status_code == 200, join_res.text
        join_data = join_res.json()
        assert join_data["in_family"] is True
        assert join_data["partner"]["role"] == "mother"
        assert join_data["partner"]["display_name"] == "أم عمر"
        assert join_data["partner"]["confirmed"] is True
        _assert_no_device_leak(join_data, dev_a, dev_b, dev_c)

        children_b = client.get("/api/children", headers=h_b).json()["children"]
        children_a = client.get("/api/children", headers=h_a).json()["children"]
        assert {"عمر", "مريم"} <= {c["name"] for c in children_b}
        assert {"عمر", "مريم"} <= {c["name"] for c in children_a}

        b_omar = next(c["id"] for c in children_b if c["name"] == "عمر")
        b_prog = client.get(f"/api/children/{b_omar}/progress", headers=h_b).json()
        assert any(row["lesson_id"] == lesson_id and row["status"] == "completed" for row in b_prog.get("lessons", []))
        b_plan = client.get(f"/api/children/{b_omar}/weekly-plan", headers=h_b).json()
        assert item_key in b_plan["marks"]
        b_mem = client.get(f"/api/children/{b_omar}/memory", headers=h_b).json()
        assert any("القراءة" in f["fact"] for f in b_mem["facts"])

        # Reusing claimed code fails with invite_not_found.
        reuse = client.post("/api/families/join", json={"code": code, "role": "parent"}, headers=h_c)
        assert reuse.status_code == 404 and reuse.json()["detail"]["code"] == "invite_not_found"

        # Creating a third invite in a full 2-parent family is refused.
        full_inv = client.post("/api/families/invites", json={"role": "mother"}, headers=h_a)
        assert full_inv.status_code == 409 and full_inv.json()["detail"]["code"] == "family_full"

        # A 3rd parent joining via a synthetic unclaimed invite still hits 409 family_full.
        conn = get_conn()
        try:
            fid = conn.execute("SELECT id FROM families ORDER BY id DESC LIMIT 1").fetchone()[0]
            import hashlib
            raw = "ZXCVBNM2"
            chash = hashlib.sha256(f"tg_fam:{raw}".encode("utf-8")).hexdigest()
            conn.execute(
                "INSERT INTO family_invites (family_id, device_id, code_hash, expires_at) "
                "VALUES (?, ?, ?, datetime('now', '+15 minutes'))",
                (fid, dev_a, chash),
            )
            conn.commit()
        finally:
            conn.close()
        third_join = client.post("/api/families/join", json={"code": "ZXCV-BNM2", "role": "parent"}, headers=h_c)
        assert third_join.status_code == 409 and third_join.json()["detail"]["code"] == "family_full"

        # Expired invite check for C.
        inv_c = client.post("/api/families/invites", json={"role": "parent"}, headers=h_c)
        assert inv_c.status_code == 200
        expired_code = inv_c.json()["code"]
        conn = get_conn()
        try:
            conn.execute(
                "UPDATE family_invites SET expires_at = datetime('now', '-2 minutes') WHERE device_id = ?",
                (dev_c,),
            )
            conn.commit()
        finally:
            conn.close()
        h_d, _, _ = _proven_parent(client, "fam-pair-d", "fcm-pair-d")
        exp_join = client.post("/api/families/join", json={"code": expired_code, "role": "parent"}, headers=h_d)
        assert exp_join.status_code == 410 and exp_join.json()["detail"]["code"] == "invite_expired"

        _assert_no_device_leak(client.get("/api/families/me", headers=h_a).json(), dev_a, dev_b, dev_c)


def test_ongoing_sync_hooks_weekly_plan_marks_and_followups(monkeypatch):
    from app.main import app

    _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
    with TestClient(app) as client:
        h_a, _, _ = _proven_parent(client, "fam-hook-a", "fcm-hook-a")
        h_b, _, _ = _proven_parent(client, "fam-hook-b", "fcm-hook-b")
        a_cid = _create_child(client, h_a, "زينة")
        client.put("/api/children/memory/settings", json={"enabled": True}, headers=h_a)
        client.put("/api/children/memory/settings", json={"enabled": True}, headers=h_b)

        code = client.post("/api/families/invites", json={"role": "mother"}, headers=h_a).json()["code"]
        client.post("/api/families/join", json={"code": code, "role": "father"}, headers=h_b)

        b_cid = next(c["id"] for c in client.get("/api/children", headers=h_b).json()["children"] if c["name"] == "زينة")

        # Mark an action on A -> B fetches plan -> synced!
        plan_a = client.get(f"/api/children/{a_cid}/weekly-plan", headers=h_a).json()
        wk = plan_a["week_start"]
        key2 = plan_a["actions"][1]["key"]
        client.put(
            f"/api/children/{a_cid}/weekly-plan/marks",
            json={"week_start": wk, "item_key": key2},
            headers=h_a,
        )
        plan_b = client.get(f"/api/children/{b_cid}/weekly-plan", headers=h_b).json()
        assert key2 in plan_b["marks"]

        # Un-tick on B: sync runs BEFORE unmark_item so B keeps it unmarked cleanly.
        unmark = client.request(
            "DELETE",
            f"/api/children/{b_cid}/weekly-plan/marks",
            json={"week_start": wk, "item_key": key2},
            headers=h_b,
        )
        assert unmark.status_code == 200
        assert key2 not in unmark.json()["marks"]

        # Promise follow-up opened & answered on A syncs to B when B reads followups.
        open_fu = client.post(
            f"/api/children/{a_cid}/followups",
            json={"strategy": "وقت هادئ قبل النوم", "when": "tonight", "topic": "sleep"},
            headers=h_a,
        )
        assert open_fu.status_code == 201, open_fu.text
        fid = open_fu.json()["followup"]["id"]
        ans = client.post(
            f"/api/children/followups/{fid}/answer",
            json={"outcome": "worked", "note": "نجحت من أول ليلة"},
            headers=h_a,
        )
        assert ans.status_code == 200, ans.text

        # B calls followups/due (sync trigger) and checks child facts / followups.
        assert client.get("/api/children/followups/due", headers=h_b).status_code == 200
        b_mem = client.get(f"/api/children/{b_cid}/memory", headers=h_b).json()
        assert any("وقت هادئ" in f["fact"] or "نجحت" in f["fact"] for f in b_mem["facts"])


def test_deletion_isolation_tombstones_and_mutual_confirmation(monkeypatch):
    from app.main import app

    _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
    with TestClient(app) as client:
        h_a, _, _ = _proven_parent(client, "fam-del-a", "fcm-del-a")
        h_b, _, _ = _proven_parent(client, "fam-del-b", "fcm-del-b")
        a_cid = _create_child(client, h_a, "عمر")

        code = client.post("/api/families/invites", json={"role": "mother"}, headers=h_a).json()["code"]
        client.post("/api/families/join", json={"code": code, "role": "father"}, headers=h_b)

        # Parent A deletes عمر locally.
        d = client.delete(f"/api/children/{a_cid}", headers=h_a)
        assert d.status_code == 200

        # Tombstone keeps عمر deleted on A across subsequent syncs, while B still has him.
        assert "عمر" not in [c["name"] for c in client.get("/api/children", headers=h_a).json()["children"]]
        assert "عمر" not in [c["name"] for c in client.get("/api/children", headers=h_a).json()["children"]]
        assert "عمر" in [c["name"] for c in client.get("/api/children", headers=h_b).json()["children"]]

        # Request partner deletion -> B sees pending request -> A cannot self-confirm.
        req1 = client.post("/api/families/deletions/request", json={"child_name": "عمر"}, headers=h_a)
        assert req1.status_code == 200
        rid1 = req1.json()["request_id"]

        me_b = client.get("/api/families/me", headers=h_b).json()
        assert len(me_b["pending_deletion_requests"]) == 1
        assert me_b["pending_deletion_requests"][0]["child_name"] == "عمر"

        self_conf = client.post(f"/api/families/deletions/{rid1}/confirm", headers=h_a)
        assert self_conf.status_code == 403 and self_conf.json()["detail"]["code"] == "cannot_self_confirm"

        # Dismiss keeps child on B.
        dis = client.post(f"/api/families/deletions/{rid1}/dismiss", headers=h_b)
        assert dis.status_code == 200 and dis.json()["status"] == "dismissed"
        assert "عمر" in [c["name"] for c in client.get("/api/children", headers=h_b).json()["children"]]

        # Second request confirmed by B erases عمر on B too.
        req2 = client.post("/api/families/deletions/request", json={"child_name": "عمر"}, headers=h_a)
        rid2 = req2.json()["request_id"]
        conf = client.post(f"/api/families/deletions/{rid2}/confirm", headers=h_b)
        assert conf.status_code == 200 and conf.json()["erased_children"] == 1
        assert "عمر" not in [c["name"] for c in client.get("/api/children", headers=h_b).json()["children"]]


def test_leave_account_deletion_retention_and_gate_check(monkeypatch):
    from app.main import app

    _enable_family_sharing(monkeypatch, sharing="1", mint_enforce="1")
    with TestClient(app) as client:
        h_a, _, _ = _proven_parent(client, "fam-leave-a", "fcm-leave-a")
        h_b, _, _ = _proven_parent(client, "fam-leave-b", "fcm-leave-b")
        _create_child(client, h_a, "يوسف")
        code = client.post("/api/families/invites", json={"role": "mother"}, headers=h_a).json()["code"]
        client.post("/api/families/join", json={"code": code, "role": "father"}, headers=h_b)

        # Leave keeps both phones' children intact.
        left = client.post("/api/families/leave", headers=h_a)
        assert left.status_code == 200 and left.json()["left"] is True
        assert client.get("/api/families/me", headers=h_a).json()["in_family"] is False
        assert "يوسف" in [c["name"] for c in client.get("/api/children", headers=h_a).json()["children"]]
        assert "يوسف" in [c["name"] for c in client.get("/api/children", headers=h_b).json()["children"]]

        # Leave remaining member -> cleans up empty family.
        assert client.post("/api/families/leave", headers=h_b).status_code == 200

        # Re-pair and test full account deletion isolation + orphan cleanup.
        code2 = client.post("/api/families/invites", json={"role": "mother"}, headers=h_a).json()["code"]
        client.post("/api/families/join", json={"code": code2, "role": "father"}, headers=h_b)
        del_a = client.delete("/api/privacy/account?confirm=true", headers=h_a)
        assert del_a.status_code == 200
        # Partner B's children remain intact after A deletes their account.
        assert "يوسف" in [c["name"] for c in client.get("/api/children", headers=h_b).json()["children"]]

        del_b = client.delete("/api/privacy/account?confirm=true", headers=h_b)
        assert del_b.status_code == 200

        conn = get_conn()
        try:
            for tbl in ("families", "family_members", "family_invites", "family_deletion_requests"):
                assert conn.execute(f"SELECT COUNT(*) FROM {tbl}").fetchone()[0] == 0, tbl

            # Retention: purge aged family_invites (>1 day), preserve fresh ones.
            fid = conn.execute("INSERT INTO families DEFAULT VALUES").lastrowid
            conn.execute(
                "INSERT INTO family_invites (family_id, device_id, code_hash, expires_at, created_at) "
                "VALUES (?, 'd-old', 'h-old', datetime('now', '-2 days'), datetime('now', '-2 days'))",
                (fid,),
            )
            conn.execute(
                "INSERT INTO family_invites (family_id, device_id, code_hash, expires_at) "
                "VALUES (?, 'd-new', 'h-new', datetime('now', '+15 minutes'))",
                (fid,),
            )
            conn.commit()
        finally:
            conn.close()

        summary = retention.run_housekeeping()
        assert summary["family_invites"] == 1

        conn = get_conn()
        try:
            remaining_hashes = [r[0] for r in conn.execute("SELECT code_hash FROM family_invites").fetchall()]
            assert remaining_hashes == ["h-new"]

            # v2_gate_check sees family_account=True on this worktree + v38 DB.
            spec = importlib.util.spec_from_file_location("v2_gate_check", ROOT / "ops" / "scripts" / "v2_gate_check.py")
            assert spec is not None and spec.loader is not None
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            gate1 = mod.evaluate_gate1_headlines(conn, root=ROOT)
            assert gate1["items"]["family_account"] is True
        finally:
            conn.close()
