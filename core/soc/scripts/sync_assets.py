"""
Asset sync -- automatically imports and keeps your asset registry current.

Sources (use whichever you have credentials for -- others are skipped):
  - Wiz:    full cloud inventory with environment tags, criticality signals
  - AWS:    EC2 fleet via describe-instances with Name/Environment/Team tags
  - Qualys: scan targets with hostnames and IPs

Each source upserts into the assets table:
  - New assets are created
  - Existing assets (matched by hostname or EC2 ID) are updated with
    fresh IPs, resource IDs, and tags -- but fp_patterns are NEVER overwritten
    (analyst-added false positive patterns survive syncs)
"""

import os, uuid, json, logging
from datetime import datetime
from sqlalchemy.orm import Session
from core.soc.db.models import Asset
from core.soc.db.session import get_engine, init_db

log = logging.getLogger(__name__)


def _session():
    return Session(get_engine())


def _upsert(session: Session, lookup_kwargs: dict, defaults: dict) -> tuple:
    asset = None
    for key, val in lookup_kwargs.items():
        if val:
            asset = session.query(Asset).filter(
                getattr(Asset, key) == val
            ).first()
            if asset:
                break

    if asset:
        for field, val in defaults.items():
            if field != "fp_patterns" and val:
                setattr(asset, field, val)
        return asset, False
    else:
        asset = Asset(
            id=str(uuid.uuid4()),
            fp_patterns=[],
            created_at=datetime.utcnow(),
            **defaults,
        )
        session.add(asset)
        return asset, True


def _wiz_criticality(issue_counts: dict, is_internet_exposed: bool) -> str:
    critical = issue_counts.get("critical", 0)
    high = issue_counts.get("high", 0)
    if is_internet_exposed and (critical > 0 or high > 2):
        return "critical"
    if critical > 0 or high > 5:
        return "high"
    if high > 0 or issue_counts.get("medium", 0) > 10:
        return "medium"
    return "low"


def sync_from_wiz() -> dict:
    wiz_client_id = os.getenv("WIZ_CLIENT_ID")
    wiz_client_secret = os.getenv("WIZ_CLIENT_SECRET")
    if not wiz_client_id or not wiz_client_secret:
        return {"skipped": True, "reason": "WIZ_CLIENT_ID / WIZ_CLIENT_SECRET not set"}

    import requests

    try:
        r = requests.post(
            "https://auth.app.wiz.io/oauth/token",
            data={
                "grant_type": "client_credentials",
                "client_id": wiz_client_id,
                "client_secret": wiz_client_secret,
                "audience": "wiz-api",
            },
            timeout=15,
        )
        r.raise_for_status()
        token = r.json()["access_token"]
    except Exception as e:
        return {"skipped": True, "reason": f"Wiz auth failed: {e}"}

    query = """
    query($after: String) {
      graphEntities(
        filterBy: { type: [VIRTUAL_MACHINE, CONTAINER_IMAGE, SERVERLESS] }
        first: 500
        after: $after
      ) {
        nodes {
          id name type properties
          issueAnalytics { criticalSeverityCount highSeverityCount mediumSeverityCount }
          exposedToInternet
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    added = updated = skipped = 0
    cursor = None

    with _session() as session:
        while True:
            try:
                resp = requests.post(
                    "https://api.app.wiz.io/graphql",
                    json={"query": query, "variables": {"after": cursor}},
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=30,
                )
                resp.raise_for_status()
                data = resp.json().get("data", {}).get("graphEntities", {})
            except Exception as e:
                log.warning(f"[sync:wiz] page fetch failed: {e}")
                break

            nodes = data.get("nodes", [])
            for node in nodes:
                props = node.get("properties", {})
                analytics = node.get("issueAnalytics", {})
                issue_counts = {
                    "critical": analytics.get("criticalSeverityCount", 0),
                    "high": analytics.get("highSeverityCount", 0),
                    "medium": analytics.get("mediumSeverityCount", 0),
                }

                hostname = props.get("name") or props.get("dnsName") or node["name"]
                ip_address = props.get("privateIpAddress") or props.get("ipAddress", "")
                ec2_id = props.get("instanceId", "")
                tags = props.get("tags", {}) or {}
                env_tag = (
                    tags.get("Environment") or tags.get("environment") or
                    tags.get("Env") or tags.get("env") or
                    props.get("cloudEnvironment", "")
                ).lower()
                environment = "production" if "prod" in env_tag else (
                              "staging" if "stag" in env_tag or "stage" in env_tag else (
                              "dev" if "dev" in env_tag else "production"))
                owner = (
                    tags.get("Owner") or tags.get("Team") or
                    tags.get("team") or tags.get("owner") or ""
                )
                criticality = _wiz_criticality(issue_counts, node.get("exposedToInternet", False))

                defaults = {
                    "hostname": hostname,
                    "ip_address": ip_address,
                    "ec2_instance_id": ec2_id,
                    "wiz_resource_id": node["id"],
                    "environment": environment,
                    "owner": owner,
                    "criticality": criticality,
                    "tags": tags,
                }

                asset, created = _upsert(
                    session,
                    {"wiz_resource_id": node["id"], "hostname": hostname, "ec2_instance_id": ec2_id},
                    defaults,
                )
                if created:
                    added += 1
                else:
                    updated += 1

            session.commit()

            page_info = data.get("pageInfo", {})
            if not page_info.get("hasNextPage"):
                break
            cursor = page_info["endCursor"]

    return {"source": "wiz", "added": added, "updated": updated, "skipped": skipped}


def sync_from_aws() -> dict:
    if not os.getenv("AWS_ACCESS_KEY_ID"):
        return {"skipped": True, "reason": "AWS_ACCESS_KEY_ID not set"}

    import boto3

    regions_env = os.getenv("AWS_REGIONS", "")
    regions = [r.strip() for r in regions_env.split(",") if r.strip()] if regions_env else [
        os.getenv("AWS_REGION", "us-east-1")
    ]

    added = updated = 0

    with _session() as session:
        for region in regions:
            try:
                ec2 = boto3.client("ec2", region_name=region)
                paginator = ec2.get_paginator("describe_instances")
                pages = paginator.paginate(
                    Filters=[{"Name": "instance-state-name", "Values": ["running", "stopped"]}]
                )
            except Exception as e:
                log.warning(f"[sync:aws] {region} describe-instances failed: {e}")
                continue

            for page in pages:
                for reservation in page["Reservations"]:
                    for inst in reservation["Instances"]:
                        tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
                        hostname = (
                            tags.get("Name") or
                            inst.get("PrivateDnsName", "").split(".")[0] or
                            inst["InstanceId"]
                        )
                        env_tag = (
                            tags.get("Environment", "") or tags.get("Env", "")
                        ).lower()
                        environment = "production" if "prod" in env_tag else (
                                      "staging" if "stag" in env_tag else (
                                      "dev" if "dev" in env_tag else "production"))
                        owner = tags.get("Owner") or tags.get("Team") or tags.get("team", "")
                        crit_tag = tags.get("Criticality", tags.get("criticality", "")).lower()
                        criticality = crit_tag if crit_tag in ("critical", "high", "medium", "low") else "medium"

                        defaults = {
                            "hostname": hostname,
                            "ec2_instance_id": inst["InstanceId"],
                            "ip_address": inst.get("PrivateIpAddress", ""),
                            "environment": environment,
                            "owner": owner,
                            "criticality": criticality,
                            "tags": tags,
                        }

                        asset, created = _upsert(
                            session,
                            {"ec2_instance_id": inst["InstanceId"], "hostname": hostname},
                            defaults,
                        )
                        if created:
                            added += 1
                        else:
                            updated += 1

        session.commit()

    return {"source": "aws", "regions": regions, "added": added, "updated": updated}


def sync_from_qualys() -> dict:
    qualys_user = os.getenv("QUALYS_USERNAME")
    qualys_pass = os.getenv("QUALYS_PASSWORD")
    qualys_url = os.getenv("QUALYS_API_URL", "https://qualysapi.qualys.com")
    if not qualys_user or not qualys_pass:
        return {"skipped": True, "reason": "QUALYS_USERNAME / QUALYS_PASSWORD not set"}

    import requests
    from requests.auth import HTTPBasicAuth

    auth = HTTPBasicAuth(qualys_user, qualys_pass)
    headers = {"X-Requested-With": "SOCAgent", "Content-Type": "application/x-www-form-urlencoded"}

    added = updated = 0
    offset = 0
    batch = 500

    with _session() as session:
        while True:
            try:
                r = requests.post(
                    f"{qualys_url}/api/2.0/fo/asset/host/",
                    data={"action": "list", "details": "All", "truncation_limit": batch, "id_min": offset},
                    auth=auth, headers=headers, timeout=30,
                )
                r.raise_for_status()
            except Exception as e:
                log.warning(f"[sync:qualys] host list failed: {e}")
                break

            import xml.etree.ElementTree as ET
            try:
                root = ET.fromstring(r.text)
            except ET.ParseError as e:
                log.warning(f"[sync:qualys] XML parse error: {e}")
                break

            hosts = root.findall(".//HOST")
            if not hosts:
                break

            for host in hosts:
                qualys_id = host.findtext("ID", "")
                hostname = host.findtext("DNS", "") or host.findtext("NETBIOS", "") or qualys_id
                ip = host.findtext("IP", "")

                defaults = {
                    "hostname": hostname,
                    "ip_address": ip,
                    "qualys_asset_id": qualys_id,
                }

                asset, created = _upsert(
                    session,
                    {"qualys_asset_id": qualys_id, "ip_address": ip, "hostname": hostname},
                    defaults,
                )
                if created:
                    added += 1
                else:
                    updated += 1

                last_id = int(qualys_id) if qualys_id.isdigit() else offset

            session.commit()

            truncated = root.findtext(".//TRUNCATION/@limit")
            if not truncated or len(hosts) < batch:
                break
            offset = last_id + 1

    return {"source": "qualys", "added": added, "updated": updated}


def run_sync(sources: list = None) -> dict:
    init_db()
    all_sources = sources or ["wiz", "aws", "qualys"]
    results = {}
    ts = datetime.utcnow().isoformat()
    print(f"\n[{ts}] Asset sync starting -- sources: {all_sources}")

    source_fns = {
        "wiz": sync_from_wiz,
        "aws": sync_from_aws,
        "qualys": sync_from_qualys,
    }

    total_added = total_updated = 0
    for source in all_sources:
        fn = source_fns.get(source)
        if not fn:
            print(f"  [sync:{source}] unknown source -- skipping")
            continue
        result = fn()
        results[source] = result
        if result.get("skipped"):
            print(f"  [sync:{source}] skipped -- {result.get('reason', '')}")
        else:
            a = result.get("added", 0)
            u = result.get("updated", 0)
            total_added += a
            total_updated += u
            print(f"  [sync:{source}] +{a} new  ~{u} updated")

    print(f"  Total: +{total_added} new  ~{total_updated} updated\n")
    return {"ts": ts, "results": results, "total_added": total_added, "total_updated": total_updated}
