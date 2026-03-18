"""
Alert ingestion: pulls new alerts from all security tools into the database.
Called on a schedule by the scheduler.
"""
import os, uuid, json
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from core.soc.db.models import Alert
from core.soc.db.session import get_engine


def _session():
    return Session(get_engine())


def _exists(session, source: str, native_id: str) -> bool:
    return session.query(Alert).filter(
        Alert.source == source,
        Alert.raw_data["id"].as_string() == native_id
    ).first() is not None


def ingest_guardduty():
    try:
        import boto3
        c = boto3.client("guardduty", region_name=os.getenv("AWS_REGION", "us-east-1"))
        dids = c.list_detectors().get("DetectorIds", [])
        if not dids:
            return
        did = dids[0]
        ids = c.list_findings(
            DetectorId=did,
            FindingCriteria={"Criterion": {
                "severity": {"Gte": 40},
                "updatedAt": {"Gte": int((datetime.utcnow() - timedelta(hours=1)).timestamp() * 1000)},
            }},
        ).get("FindingIds", [])
        if not ids:
            return
        findings = c.get_findings(DetectorId=did, FindingIds=ids[:50])["Findings"]
        with _session() as s:
            added = 0
            for f in findings:
                if _exists(s, "guardduty", f["Id"]):
                    continue
                sev = f["Severity"]
                s.add(Alert(
                    id=str(uuid.uuid4()),
                    source="guardduty",
                    raw_data={
                        "id": f["Id"], "type": f["Type"], "description": f["Description"],
                        "severity": sev,
                        "resource_id": f.get("Resource", {}).get("InstanceDetails", {}).get("InstanceId"),
                    },
                    severity="critical" if sev >= 7 else ("high" if sev >= 4 else "low"),
                    status="new",
                ))
                added += 1
            s.commit()
        if added:
            print(f"  [ingest] GuardDuty +{added}")
    except Exception as e:
        print(f"  [ingest] GuardDuty error: {e}")


def ingest_sentinel():
    try:
        from core.soc.tools.sentinel import get_sentinel_incidents
        data = json.loads(get_sentinel_incidents.invoke({"status": "New", "hours_back": 2}))
        incidents = data.get("incidents", [])
        with _session() as s:
            added = 0
            for inc in incidents:
                if _exists(s, "sentinel", inc["id"]):
                    continue
                s.add(Alert(
                    id=str(uuid.uuid4()),
                    source="sentinel",
                    raw_data={"id": inc["id"], "title": inc["title"], "description": inc.get("description", ""), "severity": inc["severity"]},
                    severity=inc["severity"].lower(),
                    status="new",
                ))
                added += 1
            s.commit()
        if added:
            print(f"  [ingest] Sentinel +{added}")
    except Exception as e:
        print(f"  [ingest] Sentinel error: {e}")


def ingest_wiz():
    try:
        from core.soc.tools.wiz import get_wiz_issues
        data = json.loads(get_wiz_issues.invoke({"severity": "CRITICAL", "limit": 20}))
        issues = data.get("issues", [])
        with _session() as s:
            added = 0
            for issue in issues:
                if _exists(s, "wiz", issue["id"]):
                    continue
                s.add(Alert(
                    id=str(uuid.uuid4()),
                    source="wiz",
                    raw_data={"id": issue["id"], "title": issue["title"], "severity": issue["severity"], "resource_id": issue.get("entitySnapshot", {}).get("id")},
                    severity=issue["severity"].lower(),
                    status="new",
                ))
                added += 1
            s.commit()
        if added:
            print(f"  [ingest] Wiz +{added}")
    except Exception as e:
        print(f"  [ingest] Wiz error: {e}")


def run_ingestion():
    print(f"[{datetime.utcnow().isoformat()}] Ingesting alerts...")
    ingest_guardduty()
    ingest_sentinel()
    ingest_wiz()
