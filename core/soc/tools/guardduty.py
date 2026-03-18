import os, json, boto3
from datetime import datetime, timedelta
from langchain_core.tools import tool


def _client():
    return boto3.client("guardduty", region_name=os.getenv("AWS_REGION", "us-east-1"))


def _detector():
    ids = _client().list_detectors().get("DetectorIds", [])
    if not ids:
        raise ValueError("No GuardDuty detector found.")
    return ids[0]


@tool
def get_guardduty_findings(severity_min: float = 4.0, hours_back: int = 24, resource_id: str = "") -> str:
    """
    Get AWS GuardDuty security findings filtered by severity and time range.
    Use to find suspicious activity, unusual network connections, compromised credentials,
    or behavioural anomalies on AWS resources.
    Pass resource_id (EC2 instance ID) to filter to a specific asset.
    Returns JSON list of findings.
    """
    c = _client()
    did = _detector()
    criterion = {
        "severity": {"Gte": severity_min},
        "updatedAt": {
            "Gte": int((datetime.utcnow() - timedelta(hours=hours_back)).timestamp() * 1000)
        },
    }
    if resource_id:
        criterion["resource.instanceDetails.instanceId"] = {"Eq": [resource_id]}

    ids = c.list_findings(
        DetectorId=did,
        FindingCriteria={"Criterion": criterion},
        MaxResults=50,
    ).get("FindingIds", [])

    if not ids:
        return json.dumps({"findings": [], "count": 0})

    findings = c.get_findings(DetectorId=did, FindingIds=ids[:20])["Findings"]
    summary = [
        {
            "id": f["Id"],
            "type": f["Type"],
            "severity": f["Severity"],
            "resource_id": f.get("Resource", {}).get("InstanceDetails", {}).get("InstanceId"),
            "description": f["Description"],
            "first_seen": f["Service"]["EventFirstSeen"],
            "last_seen": f["Service"]["EventLastSeen"],
            "count": f["Service"]["Count"],
        }
        for f in findings
    ]
    return json.dumps({"findings": summary, "count": len(summary)}, default=str)


@tool
def get_guardduty_finding_detail(finding_id: str) -> str:
    """
    Get full detail on a specific GuardDuty finding — network connections, process info,
    threat intelligence on remote IPs. Call after get_guardduty_findings to drill in.
    """
    c = _client()
    findings = c.get_findings(DetectorId=_detector(), FindingIds=[finding_id])["Findings"]
    if not findings:
        return json.dumps({"error": f"Finding {finding_id} not found"})
    return json.dumps(findings[0], default=str)


@tool
def get_guardduty_ip_findings(ip_address: str) -> str:
    """
    Find all GuardDuty findings involving a specific remote IP address.
    Useful for pivoting from a suspicious IP found in Sentinel logs.
    """
    c = _client()
    ids = c.list_findings(
        DetectorId=_detector(),
        FindingCriteria={
            "Criterion": {
                "service.action.networkConnectionAction.remoteIpDetails.ipAddressV4": {
                    "Eq": [ip_address]
                }
            }
        },
    ).get("FindingIds", [])
    if not ids:
        return json.dumps({"ip": ip_address, "findings": [], "verdict": "no_findings"})
    findings = c.get_findings(DetectorId=_detector(), FindingIds=ids[:5])["Findings"]
    return json.dumps({
        "ip": ip_address,
        "finding_count": len(ids),
        "sample_findings": [{"type": f["Type"], "severity": f["Severity"]} for f in findings],
        "verdict": "suspicious",
    }, default=str)


GUARDDUTY_TOOLS = [get_guardduty_findings, get_guardduty_finding_detail, get_guardduty_ip_findings]
