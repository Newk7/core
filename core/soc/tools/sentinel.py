import os, json
from datetime import timedelta
from langchain_core.tools import tool
from azure.identity import ClientSecretCredential
from azure.monitor.query import LogsQueryClient, LogsQueryStatus


def _cred():
    return ClientSecretCredential(
        tenant_id=os.getenv("SENTINEL_TENANT_ID"),
        client_id=os.getenv("SENTINEL_CLIENT_ID"),
        client_secret=os.getenv("SENTINEL_CLIENT_SECRET"),
    )


def _logs_client():
    return LogsQueryClient(_cred())


@tool
def query_sentinel_logs(kql_query: str, hours_back: int = 24) -> str:
    """
    Run a KQL query against Microsoft Sentinel / Azure Log Analytics.
    Use to search events, logins, process executions, network connections.
    Example: SecurityEvent | where Computer == 'prod-api-01' | order by TimeGenerated desc | take 50
    Returns rows as JSON.
    """
    workspace_id = os.getenv("SENTINEL_WORKSPACE_ID")
    try:
        response = _logs_client().query_workspace(
            workspace_id=workspace_id,
            query=kql_query,
            timespan=timedelta(hours=hours_back),
        )
        if response.status == LogsQueryStatus.SUCCESS:
            rows = []
            for table in response.tables:
                for row in table.rows:
                    rows.append(dict(zip(table.columns, row)))
            return json.dumps({"status": "success", "row_count": len(rows), "rows": rows[:100]}, default=str)
        return json.dumps({"status": "partial", "error": str(response.partial_error)})
    except Exception as e:
        return json.dumps({"status": "error", "error": str(e)})


@tool
def get_sentinel_incidents(status: str = "New", severity: str = "", hours_back: int = 48) -> str:
    """
    Get Microsoft Sentinel security incidents filtered by status and severity.
    Status: New | Active | Closed
    Severity: High | Medium | Low | Informational
    """
    resource_group = os.getenv("SENTINEL_RESOURCE_GROUP", "")
    workspace_name = os.getenv("SENTINEL_WORKSPACE_NAME", "")
    from azure.mgmt.securityinsight import SecurityInsights
    from datetime import datetime
    try:
        client = SecurityInsights(_cred(), os.getenv("SENTINEL_SUBSCRIPTION_ID", ""))
        incidents = client.incidents.list(resource_group, workspace_name)
        cutoff = datetime.utcnow() - timedelta(hours=hours_back)
        results = []
        for inc in incidents:
            if inc.status != status:
                continue
            if severity and inc.severity != severity:
                continue
            if inc.created_time_utc and inc.created_time_utc.replace(tzinfo=None) < cutoff:
                continue
            results.append({
                "id": inc.name,
                "title": inc.title,
                "severity": inc.severity,
                "status": inc.status,
                "description": inc.description,
                "created_at": str(inc.created_time_utc),
            })
        return json.dumps({"incidents": results, "count": len(results)}, default=str)
    except Exception as e:
        return json.dumps({"status": "error", "error": str(e)})


@tool
def get_sentinel_entity_timeline(entity_id: str, hours_back: int = 72) -> str:
    """
    Get activity timeline for a hostname, IP, or username across all Sentinel tables.
    Use to understand what happened before and after an alert on a specific entity.
    """
    kql = f"""
    union
    (SecurityEvent | where Computer contains '{entity_id}' | project TimeGenerated, EventID, Activity, Computer, Account, IpAddress),
    (SigninLogs | where IPAddress == '{entity_id}' or UserDisplayName contains '{entity_id}' | project TimeGenerated, UserDisplayName, IPAddress, ResultType, AppDisplayName)
    | order by TimeGenerated desc
    | take 200
    """
    return query_sentinel_logs.invoke({"kql_query": kql, "hours_back": hours_back})


SENTINEL_TOOLS = [query_sentinel_logs, get_sentinel_incidents, get_sentinel_entity_timeline]
