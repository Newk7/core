from fastapi import APIRouter, Query
from core.soc.db.models import AnalystFeedback
from core.soc.db.session import get_session

router = APIRouter()


def _f_dict(f: AnalystFeedback) -> dict:
    return {
        "id": f.id, "investigation_id": f.investigation_id,
        "alert_id": f.alert_id, "asset_id": f.asset_id,
        "agent_severity": f.agent_severity, "analyst_severity": f.analyst_severity,
        "action": f.action, "notes": f.notes,
        "created_at": f.created_at.isoformat() if f.created_at else None,
    }


@router.get("")
def list_feedback(limit: int = Query(100)):
    with get_session() as s:
        items = s.query(AnalystFeedback).order_by(AnalystFeedback.created_at.desc()).limit(limit).all()
        return [_f_dict(f) for f in items]


@router.get("/summary")
def feedback_summary():
    with get_session() as s:
        items = s.query(AnalystFeedback).all()
        total = len(items)
        if not total:
            return {"total": 0}

        action_counts = {}
        severity_matches = 0
        for f in items:
            action_counts[f.action] = action_counts.get(f.action, 0) + 1
            if f.agent_severity == f.analyst_severity:
                severity_matches += 1

        return {
            "total": total,
            "severity_accuracy_pct": round(severity_matches / total * 100, 1),
            "action_breakdown": action_counts,
            "false_positive_rate_pct": round(action_counts.get("false_positive", 0) / total * 100, 1),
        }
