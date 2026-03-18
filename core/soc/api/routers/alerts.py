import uuid
from fastapi import APIRouter, HTTPException, Query
from datetime import datetime, timedelta
from core.soc.db.models import Alert
from core.soc.db.session import get_session

router = APIRouter()


def _alert_dict(a: Alert) -> dict:
    return {
        "id": a.id, "source": a.source, "severity": a.severity,
        "status": a.status, "raw_data": a.raw_data,
        "asset_id": a.asset_id,
        "created_at": a.created_at.isoformat() if a.created_at else None,
        "updated_at": a.updated_at.isoformat() if a.updated_at else None,
    }


@router.get("")
def list_alerts(
    status: str = Query(None),
    severity: str = Query(None),
    source: str = Query(None),
    hours: int = Query(24),
    limit: int = Query(100),
):
    with get_session() as s:
        q = s.query(Alert).filter(Alert.created_at >= datetime.utcnow() - timedelta(hours=hours))
        if status:
            q = q.filter(Alert.status == status)
        if severity:
            q = q.filter(Alert.severity == severity)
        if source:
            q = q.filter(Alert.source == source)
        alerts = q.order_by(Alert.created_at.desc()).limit(limit).all()
        return [_alert_dict(a) for a in alerts]


@router.post("")
def create_alert(body: dict):
    allowed_sources = {"guardduty", "sentinel", "wiz", "qualys", "snyk", "manual"}
    allowed_severities = {"critical", "high", "medium", "low", "informational", "unknown"}
    source = body.get("source", "manual")
    severity = body.get("severity", "medium")
    if source not in allowed_sources:
        raise HTTPException(400, f"source must be one of {allowed_sources}")
    if severity not in allowed_severities:
        raise HTTPException(400, f"severity must be one of {allowed_severities}")
    with get_session() as s:
        a = Alert(
            id=str(uuid.uuid4()),
            source=source,
            raw_data=body.get("raw_data", {}),
            severity=severity,
            status="new",
            asset_id=body.get("asset_id"),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        s.add(a)
        s.commit()
        s.refresh(a)
        return _alert_dict(a)


@router.get("/{alert_id}")
def get_alert(alert_id: str):
    with get_session() as s:
        a = s.query(Alert).filter_by(id=alert_id).first()
        if not a:
            raise HTTPException(404, "Alert not found")
        return _alert_dict(a)


@router.patch("/{alert_id}/status")
def update_alert_status(alert_id: str, body: dict):
    allowed = {"new", "investigating", "awaiting_review", "escalated", "closed", "false_positive"}
    new_status = body.get("status")
    if new_status not in allowed:
        raise HTTPException(400, f"status must be one of {allowed}")
    with get_session() as s:
        a = s.query(Alert).filter_by(id=alert_id).first()
        if not a:
            raise HTTPException(404, "Alert not found")
        a.status = new_status
        a.updated_at = datetime.utcnow()
        s.commit()
        return _alert_dict(a)
