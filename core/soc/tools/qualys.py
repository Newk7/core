import os, json, requests
from requests.auth import HTTPBasicAuth
from langchain_core.tools import tool


def _auth():
    return HTTPBasicAuth(os.getenv("QUALYS_USERNAME"), os.getenv("QUALYS_PASSWORD"))


def _base():
    return os.getenv("QUALYS_API_URL", "https://qualysapi.qualys.com")


@tool
def get_qualys_vulnerabilities(asset_ip: str = "", severity_min: int = 3) -> str:
    """
    Get vulnerabilities from Qualys for an asset IP address.
    Severity: 1=minimal 2=medium 3=serious 4=critical 5=urgent
    Returns CVEs, CVSS scores, patch status.
    Leave asset_ip empty to get all vulnerabilities above severity threshold.
    """
    params = {
        "action": "list",
        "severities": ",".join(str(i) for i in range(severity_min, 6)),
        "show_results": 1,
    }
    if asset_ip:
        params["ips"] = asset_ip
    try:
        r = requests.get(
            f"{_base()}/api/2.0/fo/asset/host/vm/detection/",
            params=params,
            auth=_auth(),
            headers={"X-Requested-With": "SOCAgent"},
            timeout=30,
        )
        r.raise_for_status()
        return json.dumps({"status": "success", "data": r.text[:6000]})
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def get_qualys_cve(cve_id: str) -> str:
    """
    Look up a specific CVE in the Qualys knowledge base.
    Returns CVSS score, affected software versions, and remediation guidance.
    """
    try:
        r = requests.post(
            f"{_base()}/api/2.0/fo/knowledge_base/vuln/",
            data={"action": "list", "details": "All", "cve_id": cve_id},
            auth=_auth(),
            headers={"X-Requested-With": "SOCAgent", "Content-Type": "application/x-www-form-urlencoded"},
            timeout=30,
        )
        r.raise_for_status()
        return json.dumps({"cve": cve_id, "data": r.text[:3000]})
    except Exception as e:
        return json.dumps({"error": str(e)})


QUALYS_TOOLS = [get_qualys_vulnerabilities, get_qualys_cve]
