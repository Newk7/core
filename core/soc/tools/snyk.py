import os, json, requests
from langchain_core.tools import tool

SNYK_V1 = "https://snyk.io/api/v1"


def _headers():
    return {"Authorization": f"token {os.getenv('SNYK_API_TOKEN')}", "Content-Type": "application/json"}


@tool
def get_snyk_vulnerabilities(project_id: str = "", severity: str = "high") -> str:
    """
    Get application/dependency vulnerabilities from Snyk.
    Severity: critical | high | medium | low
    Optionally filter by project_id. Leave blank to get issues across all projects.
    Returns CVEs, exploitability scores, package names, and fix guidance.
    """
    org = os.getenv("SNYK_ORG_ID", "")
    url = f"{SNYK_V1}/org/{org}/project/{project_id}/issues" if project_id else f"{SNYK_V1}/org/{org}/issues"
    try:
        r = requests.post(
            url,
            json={"filters": {"severities": [severity, "critical"], "types": ["vuln"]}},
            headers=_headers(),
            timeout=30,
        )
        r.raise_for_status()
        vulns = r.json().get("issues", {}).get("vulnerabilities", [])
        simplified = [
            {
                "id": v.get("id"), "title": v.get("title"), "severity": v.get("severity"),
                "cvss": v.get("cvssScore"), "cve": v.get("identifiers", {}).get("CVE", []),
                "package": v.get("package"), "version": v.get("version"),
                "patchable": v.get("isPatchable"), "upgradable": v.get("isUpgradable"),
            }
            for v in vulns[:30]
        ]
        return json.dumps({"vulnerabilities": simplified, "count": len(simplified)})
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def get_snyk_projects() -> str:
    """
    List all Snyk-monitored projects with current vulnerability counts.
    Use to understand the application attack surface before diving into a specific project.
    """
    org = os.getenv("SNYK_ORG_ID", "")
    try:
        r = requests.get(f"{SNYK_V1}/org/{org}/projects", headers=_headers(), timeout=30)
        r.raise_for_status()
        projects = [
            {"id": p["id"], "name": p["name"], "type": p["type"], "issues": p.get("issueCountsBySeverity")}
            for p in r.json().get("projects", [])
        ]
        return json.dumps({"projects": projects, "count": len(projects)})
    except Exception as e:
        return json.dumps({"error": str(e)})


SNYK_TOOLS = [get_snyk_vulnerabilities, get_snyk_projects]
