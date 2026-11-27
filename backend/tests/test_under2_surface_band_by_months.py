"""Tests for the under-2 child-surface rule by calendar months (#fb_b796ab75).

Curriculum content places 12-23 month olds on the "2-3" (1-3 years) band
because its content is closer to a walking toddler than pregnancy/newborn
content. Child-surface policy must still enforce the strict no-screen
"under-2" rule whenever `birth_month` is known and age is under 24 months,
regardless of the stored or computed `age_group`.
"""
from datetime import date

import pytest

from app.config.guardrails_loader import load_child_surface_policy
from app.core.taxonomy import map_profile_age_to_band
from app.services import child_budget, programs_common


@pytest.mark.parametrize(
    "profile_age,age_months,expected",
    [
        ("2-3", 16, "under-2"),
        ("2-3", 12, "under-2"),
        ("2-3", 23, "under-2"),
        ("4-6", 18, "under-2"),
        ("7-9", 23, "under-2"),
        ("2-3", 0, "under-2"),
        ("2-3", -3, "under-2"),
        ("2-3", 24, "2-3"),
        ("2-3", 30, "2-3"),
        ("4-6", 48, "4-6"),
        ("2-3", None, "2-3"),
        ("prenatal-1", None, "under-2"),
        ("0-3", None, "under-2"),
        (None, None, "under-2"),
    ],
)
def test_map_profile_age_to_band_respects_age_months_under_24(
    profile_age, age_months, expected
):
    assert map_profile_age_to_band(profile_age, age_months=age_months) == expected


def test_child_surface_band_vs_effective_age_group_for_16_month_old():
    today = date(2026, 11, 27)
    row_16m = {"age_group": "2-3", "birth_month": "2025-07"}
    # Curriculum still routes 16-month-old to 2-3 (ages 1-3)
    assert programs_common.effective_age_group(row_16m, on=today) == "2-3"
    # Child surface gate strictly enforces under-2 (< 24 months)
    assert programs_common.child_surface_band(row_16m, on=today) == "under-2"

    row_16m_prenatal = {"age_group": "prenatal-1", "birth_month": "2025-07"}
    assert programs_common.effective_age_group(row_16m_prenatal, on=today) == "2-3"
    assert programs_common.child_surface_band(row_16m_prenatal, on=today) == "under-2"

    row_24m = {"age_group": "prenatal-1", "birth_month": "2024-11"}
    assert programs_common.effective_age_group(row_24m, on=today) == "2-3"
    assert programs_common.child_surface_band(row_24m, on=today) == "2-3"

    row_no_birth = {"age_group": "2-3", "birth_month": None}
    assert programs_common.child_surface_band(row_no_birth, on=today) == "2-3"


def test_open_session_blocks_16_month_old_even_when_age_group_is_2_3(
    monkeypatch, tmp_path
):
    db_file = tmp_path / "test.db"
    monkeypatch.setenv("CONVERSATIONS_DB", str(db_file))
    from app.db.init_db import get_conn, init_db

    init_db()
    today = date.today()
    # 16 months ago -> YYYY-MM
    total_m = today.year * 12 + (today.month - 1) - 16
    bm_16m = f"{total_m // 12:04d}-{(total_m % 12) + 1:02d}"
    # 25 months ago -> YYYY-MM
    total_m_25 = today.year * 12 + (today.month - 1) - 25
    bm_25m = f"{total_m_25 // 12:04d}-{(total_m_25 % 12) + 1:02d}"

    conn = get_conn()
    try:
        c16 = conn.execute(
            "INSERT INTO child_profiles (device_id, name, age_group, birth_month) "
            "VALUES (?, ?, ?, ?)",
            ("dev-under2", "سالم", "2-3", bm_16m),
        ).lastrowid
        c25 = conn.execute(
            "INSERT INTO child_profiles (device_id, name, age_group, birth_month) "
            "VALUES (?, ?, ?, ?)",
            ("dev-under2", "زين", "prenatal-1", bm_25m),
        ).lastrowid
        conn.commit()
    finally:
        conn.close()

    policy = load_child_surface_policy()
    # 16-month-old with age_group='2-3' is blocked on screen_off (under-2)
    r16 = child_budget.open_session("dev-under2", c16, "screen_off", 0, policy)
    assert r16["ok"] is False
    assert r16["reason"] == "age_not_allowed"
    assert r16["band"] == "under-2"

    # 25-month-old with stale age_group='prenatal-1' is allowed screen_off (2-3)
    r25 = child_budget.open_session("dev-under2", c25, "screen_off", 0, policy)
    assert r25["ok"] is True
    assert r25["band"] == "2-3"
