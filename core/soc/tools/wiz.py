import os, json, requests
from langchain_core.tools import tool

WIZ_AUTH_URL = "https://auth.app.wiz.io/oauth/token"
WIZ_API_URL = "https://api.app.wiz.io/graphql"


def _token():
    r = requests.post(WIZ_AUTH_URL, data={
        "grant_type": "client_credentials",
        "client_id": os.getenv("WIZ_CLIENT_ID"),
        "client_secret": os.getenv("WIZ_CLIENT_SECRET"),
        "audience": "wiz-api",
    })
    r.raise_for_status()
    return r.json()["access_token"]


def _gql(query, variables=None):
    r = requests.post(
        WIZ_API_URL,
        json={"query": query, "variables": variables or {}},
        headers={"Authorization": f"Bearer {_token()}"},
    )
    r.raise_for_status()
    return r.json()


@tool
def get_wiz_issues(severity: str = "HIGH", limit: int = 50) -> str:
    """
    Get open security issues from Wiz — misconfigurations, vulnerabilities, exposure.
    Severity: CRITICAL | HIGH | MEDIUM | LOW
    Returns issues with affected resource context.
    """
    q = """
    query($severity:[Severity!], $first:Int) {
      issues(filterBy:{severity:$severity, status:[OPEN,IN_PROGRESS]} first:$first) {
        nodes {
          id title severity status type createdAt
          entitySnapshot { id name type cloudPlatform region tags }
          control { name description }
        }
      }
    }"""
    try:
        data = _gql(q, {"severity": [severity], "first": limit})
        issues = data.get("data", {}).get("issues", {}).get("nodes", [])
        return json.dumps({"issues": issues, "count": len(issues)}, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def get_wiz_asset(resource_id: str) -> str:
    """
    Get full security posture for a specific cloud asset from Wiz.
    Includes vulnerabilities, misconfigurations, network exposure, IAM issues.
    Use resource_id from Wiz (ARN or Wiz entity ID).
    """
    q = """
    query($id:String!) {
      graphEntity(id:$id) {
        id name type properties
        issues(first:20) { nodes { id title severity status control { name } } }
      }
    }"""
    try:
        return json.dumps(_gql(q, {"id": resource_id}).get("data", {}), default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def get_wiz_attack_paths(asset_id: str) -> str:
    """
    Get Wiz attack path analysis for an asset.
    Shows how an attacker could reach it and what they could pivot to.
    Use to understand blast radius when a resource is compromised.
    """
    q = """
    query($id:String!) {
      attackPaths(filterBy:{targetEntityId:$id} first:5) {
        nodes { id riskScore attackSteps { entityType entityName action } }
      }
    }"""
    try:
        return json.dumps(_gql(q, {"id": asset_id}).get("data", {}), default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


WIZ_TOOLS = [get_wiz_issues, get_wiz_asset, get_wiz_attack_paths]
