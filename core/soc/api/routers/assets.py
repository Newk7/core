import uuid
from datetime import datetime
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from core.soc.db.models import Asset
from core.soc.db.session import get_session

router = APIRouter()


def _asset_dict(a: Asset) -> dict:
    return {
        "id": a.id, "hostname": a.hostname, "ec2_instance_id": a.ec2_instance_id,
        "ip_address": a.ip_address, "wiz_resource_id": a.wiz_resource_id,
        "qualys_asset_id": a.qualys_asset_id, "snyk_project_id": a.snyk_project_id,
        "criticality": a.criticality, "owner": a.owner, "environment": a.environment,
        "tags": a.tags, "fp_patterns": a.fp_patterns,
        "last_investigation": a.last_investigation.isoformat() if a.last_investigation else None,
        "created_at": a.created_at.isoformat() if a.created_at else None,
    }


class AssetCreate(BaseModel):
    hostname: str
    ec2_instance_id: str = ""
    ip_address: str = ""
    wiz_resource_id: str = ""
    qualys_asset_id: str = ""
    snyk_project_id: str = ""
    criticality: str = "medium"
    owner: str = ""
    environment: str = "production"
    tags: dict = {}
    fp_patterns: List[str] = []


class AssetUpdate(BaseModel):
    hostname: Optional[str] = None
    ec2_instance_id: Optional[str] = None
    ip_address: Optional[str] = None
    wiz_resource_id: Optional[str] = None
    qualys_asset_id: Optional[str] = None
    snyk_project_id: Optional[str] = None
    criticality: Optional[str] = None
    owner: Optional[str] = None
    environment: Optional[str] = None
    tags: Optional[dict] = None
    fp_patterns: Optional[List[str]] = None


@router.get("")
def list_assets(environment: str = None, criticality: str = None):
    with get_session() as s:
        q = s.query(Asset)
        if environment:
            q = q.filter(Asset.environment == environment)
        if criticality:
            q = q.filter(Asset.criticality == criticality)
        return [_asset_dict(a) for a in q.order_by(Asset.criticality, Asset.hostname).all()]


@router.get("/{asset_id}")
def get_asset(asset_id: str):
    with get_session() as s:
        a = s.query(Asset).filter_by(id=asset_id).first()
        if not a:
            raise HTTPException(404, "Asset not found")
        return _asset_dict(a)


@router.post("")
def create_asset(body: AssetCreate):
    with get_session() as s:
        existing = s.query(Asset).filter_by(hostname=body.hostname).first()
        if existing:
            raise HTTPException(409, f"Asset with hostname {body.hostname} already exists")
        a = Asset(id=str(uuid.uuid4()), **body.model_dump(), created_at=datetime.utcnow())
        s.add(a)
        s.commit()
        return _asset_dict(a)


@router.patch("/{asset_id}")
def update_asset(asset_id: str, body: AssetUpdate):
    with get_session() as s:
        a = s.query(Asset).filter_by(id=asset_id).first()
        if not a:
            raise HTTPException(404, "Asset not found")
        for field, val in body.model_dump(exclude_none=True).items():
            setattr(a, field, val)
        s.commit()
        return _asset_dict(a)


@router.delete("/{asset_id}")
def delete_asset(asset_id: str):
    with get_session() as s:
        a = s.query(Asset).filter_by(id=asset_id).first()
        if not a:
            raise HTTPException(404, "Asset not found")
        s.delete(a)
        s.commit()
        return {"deleted": asset_id}


@router.post("/{asset_id}/fp-patterns")
def add_fp_pattern(asset_id: str, body: dict):
    pattern = body.get("pattern", "").strip()
    if not pattern:
        raise HTTPException(400, "pattern required")
    with get_session() as s:
        a = s.query(Asset).filter_by(id=asset_id).first()
        if not a:
            raise HTTPException(404, "Asset not found")
        patterns = list(a.fp_patterns or [])
        if pattern not in patterns:
            patterns.append(pattern)
            a.fp_patterns = patterns
            s.commit()
        return _asset_dict(a)


@router.delete("/{asset_id}/fp-patterns/{index}")
def remove_fp_pattern(asset_id: str, index: int):
    with get_session() as s:
        a = s.query(Asset).filter_by(id=asset_id).first()
        if not a:
            raise HTTPException(404, "Asset not found")
        patterns = list(a.fp_patterns or [])
        if index < 0 or index >= len(patterns):
            raise HTTPException(400, f"Index {index} out of range")
        patterns.pop(index)
        a.fp_patterns = patterns
        s.commit()
        return _asset_dict(a)
