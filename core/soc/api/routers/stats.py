from fastapi import APIRouter
from datetime import datetime, timedelta
from core.soc.db.models import Alert, Investigation, Asset
from core.soc.db.session import get_session

router = APIRouter()


@router.get("")
def stats():
    with get_session() as s:
        last_24h = datetime.utcnow() - timedelta(hours=24)
        return {
            "alerts_24h": s.query(Alert).filter(Alert.created_at >= last_24h).count(),
            "investigations_24h": s.query(Investigation).filter(Investigation.created_at >= last_24h).count(),
            "awaiting_review": s.query(Investigation).filter(Investigation.hitl_status == "pending").count(),
            "critical_open": s.query(Alert).filter(Alert.severity == "critical", Alert.status.in_(["new", "escalated", "awaiting_review"])).count(),
            "high_open": s.query(Alert).filter(Alert.severity == "high", Alert.status.in_(["new", "escalated", "awaiting_review"])).count(),
            "assets_total": s.query(Asset).count(),
        }
