import uuid
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from core.soc.db.models import Investigation, Alert, Asset, AnalystFeedback
from core.soc.db.session import get_session

router = APIRouter()


def _inv_dict(i: Investigation) -> dict:
    return {
        "id": i.id, "alert_id": i.alert_id, "asset_id": i.asset_id,
        "triage_findings": i.triage_findings, "vuln_findings": i.vuln_findings,
        "hunt_findings": i.hunt_findings, "final_verdict": i.final_verdict,
        "severity": i.severity, "recommended_action": i.recommended_action,
        "hitl_required": i.hitl_required, "hitl_status": i.hitl_status,
        "hitl_thread_id": i.hitl_thread_id,
        "analyst_notes": i.analyst_notes,
        "analyst_severity_override": i.analyst_severity_override,
        "resolved_at": i.resolved_at.isoformat() if i.resolved_at else None,
        "resolved_by": i.resolved_by,
        "agent_trace": i.agent_trace,
        "created_at": i.created_at.isoformat() if i.created_at else None,
    }


@router.get("")
def list_investigations(
    hitl_status: str = Query(None),
    severity: str = Query(None),
    hours: int = Query(24),
    limit: int = Query(50),
):
    with get_session() as s:
        q = s.query(Investigation).filter(
            Investigation.created_at >= datetime.utcnow() - timedelta(hours=hours)
        )
        if hitl_status:
            q = q.filter(Investigation.hitl_status == hitl_status)
        if severity:
            q = q.filter(Investigation.severity == severity)
        invs = q.order_by(Investigation.created_at.desc()).limit(limit).all()
        return [_inv_dict(i) for i in invs]


@router.get("/pending-review")
def pending_review():
    with get_session() as s:
        invs = s.query(Investigation).filter(
            Investigation.hitl_status == "pending"
        ).order_by(Investigation.created_at.desc()).all()
        return [_inv_dict(i) for i in invs]


@router.get("/{inv_id}")
def get_investigation(inv_id: str):
    with get_session() as s:
        i = s.query(Investigation).filter_by(id=inv_id).first()
        if not i:
            raise HTTPException(404, "Investigation not found")
        return _inv_dict(i)


class ResolveRequest(BaseModel):
    action: str
    notes: str = ""
    severity_override: str = ""
    analyst: str = "analyst"


@router.post("/{inv_id}/resolve")
def resolve_investigation(inv_id: str, body: ResolveRequest):
    allowed_actions = {"approved", "rejected", "false_positive", "escalated"}
    if body.action not in allowed_actions:
        raise HTTPException(400, f"action must be one of {allowed_actions}")

    with get_session() as s:
        inv = s.query(Investigation).filter_by(id=inv_id).first()
        if not inv:
            raise HTTPException(404, "Investigation not found")
        if inv.hitl_status != "pending":
            raise HTTPException(400, f"Investigation is not pending review (status={inv.hitl_status})")

        alert = s.query(Alert).filter_by(id=inv.alert_id).first()

        inv.hitl_status = body.action
        inv.analyst_notes = body.notes
        inv.analyst_severity_override = body.severity_override or None
        inv.resolved_at = datetime.utcnow()
        inv.resolved_by = body.analyst

        effective_severity = body.severity_override or inv.severity

        if body.action == "approved":
            if alert:
                alert.status = "escalated" if effective_severity in ("critical", "high") else "closed"
            if inv.hitl_thread_id:
                try:
                    from core.soc.orchestrator.runner import resume_investigation
                    instruction = (
                        f"The analyst has APPROVED this investigation. "
                        f"Analyst notes: {body.notes or 'none'}. "
                        f"Proceed with finalising the report and recommended actions."
                    )
                    resume_result = resume_investigation(inv.hitl_thread_id, instruction)
                    if resume_result.get("final_verdict"):
                        inv.final_verdict = resume_result["final_verdict"]
                except Exception as e:
                    print(f"[HITL] Graph resume failed: {e}")

        elif body.action in ("rejected", "false_positive"):
            if alert:
                alert.status = "false_positive" if body.action == "false_positive" else "closed"
            if body.action == "false_positive" and inv.asset_id and body.notes:
                asset = s.query(Asset).filter_by(id=inv.asset_id).first()
                if asset:
                    patterns = list(asset.fp_patterns or [])
                    patterns.append(body.notes)
                    asset.fp_patterns = patterns

        elif body.action == "escalated":
            if alert:
                alert.status = "escalated"
            inv.severity = "critical"

        feedback = AnalystFeedback(
            id=str(uuid.uuid4()),
            investigation_id=inv_id,
            alert_id=inv.alert_id,
            asset_id=inv.asset_id,
            agent_severity=inv.severity,
            analyst_severity=body.severity_override or inv.severity,
            action=body.action,
            notes=body.notes,
            created_at=datetime.utcnow(),
        )
        s.add(feedback)
        s.commit()

        return {
            "status": "resolved",
            "investigation": _inv_dict(inv),
            "alert_status": alert.status if alert else None,
        }
