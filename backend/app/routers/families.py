"""Dual-parent family account endpoints (م٣ / 1.3)."""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.contact import SUPPORT_EMAIL
from app.core.proof import request_proven, require_device_proof_irreversible
from app.services import families_service

router = APIRouter(tags=["families"])


class FamilyProfileIn(BaseModel):
    role: Optional[str] = "parent"
    display_name: Optional[str] = None


class FamilyJoinIn(BaseModel):
    code: str
    role: Optional[str] = "parent"
    display_name: Optional[str] = None


class FamilyDeletionRequestIn(BaseModel):
    child_name: str


def _require_family_session(request: Request) -> str:
    device_id = getattr(request.state, "device_id", "") or ""
    token = getattr(request.state, "token", None)
    if not device_id:
        raise HTTPException(status_code=401, detail="مطلوب توثيق.")
    if not families_service.session_eligible_for_family(token):
        raise HTTPException(
            status_code=403,
            detail={
                "code": "family_session_not_eligible",
                "message": "يلزم جلسة موثّقة غير عارية للوصول إلى حساب الأسرة.",
                "message_en": "A verified, non-bare session is required for family sharing.",
                "support_email": SUPPORT_EMAIL,
            },
        )
    return device_id


def _http_err(exc: families_service.FamilyError) -> HTTPException:
    return HTTPException(
        status_code=exc.status_code,
        detail={
            "code": exc.code,
            "message": exc.message,
            "message_en": exc.message_en,
            "support_email": SUPPORT_EMAIL,
        },
    )


@router.get("/families/me", summary="Current dual-parent family status and pending confirmations")
def get_my_family(request: Request) -> dict:
    device_id = getattr(request.state, "device_id", "") or ""
    if not device_id:
        raise HTTPException(status_code=401, detail="مطلوب توثيق.")
    token = getattr(request.state, "token", None)
    eligible = families_service.session_eligible_for_family(token)
    proven = bool(eligible and request_proven(request))
    return families_service.get_family_status(
        device_id,
        include_memory=proven,
        allow_sync=eligible,
    )


@router.post(
    "/families/invites",
    summary="Create a single-use 15-minute invite code to pair the second parent",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def create_family_invite(request: Request, body: FamilyProfileIn) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.create_invite(
            device_id,
            role_label=body.role,
            display_name=body.display_name,
        )
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc


@router.post(
    "/families/join",
    summary="Join a partner parent's family using an invite code",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def join_family(request: Request, body: FamilyJoinIn) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.join_by_invite(
            device_id,
            code=body.code,
            role_label=body.role,
            display_name=body.display_name,
        )
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc


@router.post(
    "/families/reconfirm",
    summary="Re-confirm family membership on the current push token",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def reconfirm_family_member(request: Request) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.reconfirm_member(device_id)
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc


@router.post(
    "/families/leave",
    summary="Leave the shared family without deleting this phone's local children",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def leave_family(request: Request) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.leave_family(device_id)
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc


@router.post(
    "/families/deletions/request",
    summary="Ask the partner parent to confirm deleting a shared child on their phone too",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def request_partner_child_deletion(request: Request, body: FamilyDeletionRequestIn) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.request_child_deletion(device_id, body.child_name)
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc


@router.post(
    "/families/deletions/{request_id}/confirm",
    summary="Confirm deleting the named child from this parent's phone",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def confirm_partner_child_deletion(request_id: int, request: Request) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.confirm_child_deletion(device_id, request_id)
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc


@router.post(
    "/families/deletions/{request_id}/dismiss",
    summary="Decline a partner child-deletion request and keep the child on this phone",
    dependencies=[Depends(require_device_proof_irreversible)],
)
def dismiss_partner_child_deletion(request_id: int, request: Request) -> dict:
    device_id = _require_family_session(request)
    try:
        return families_service.dismiss_child_deletion(device_id, request_id)
    except families_service.FamilyError as exc:
        raise _http_err(exc) from exc
