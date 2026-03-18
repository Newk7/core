"""
SOC Agent scheduler + SQS consumer.
Runs as: python -m core.soc.main agent

Dual mode:
  1. APScheduler for periodic jobs (ingest, triage, sync, hunt)
  2. SQS consumer for manual triggers from the API (soc.investigate, soc.hunt, etc.)
"""
import os, json, uuid, signal, threading
from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler
from sqlalchemy.orm import Session

from core.soc.db.models import Alert, Investigation, Asset
from core.soc.db.session import get_engine, init_db
from core.soc.scripts.ingest import run_ingestion
from core.soc.orchestrator.runner import run_investigation, run_threat_hunt
from core.log import create_log

log = create_log(__name__)


def _session():
    return Session(get_engine())


def _notify(alert: Alert, inv: Investigation):
    import requests as req
    msg = f"CRITICAL -- SOC Agent\nAlert: {alert.id} ({alert.source})\n{inv.final_verdict[:400]}"
    slack = os.getenv("SLACK_WEBHOOK_URL")
    if slack:
        try:
            req.post(slack, json={"text": msg}, timeout=5)
        except Exception:
            pass
    pd = os.getenv("PAGERDUTY_ROUTING_KEY")
    if pd:
        try:
            req.post("https://events.pagerduty.com/v2/enqueue", json={
                "routing_key": pd, "event_action": "trigger",
                "payload": {"summary": f"Critical SOC alert {alert.id}", "severity": "critical", "source": "soc-agent"},
            }, timeout=5)
        except Exception:
            pass


def _build_prompt(alert: Alert, asset=None) -> str:
    asset_ctx = ""
    if asset:
        asset_ctx = (
            f"\nAsset context:\n"
            f"  hostname={asset.hostname}  env={asset.environment}  "
            f"  criticality={asset.criticality}  owner={asset.owner}\n"
            f"  ec2={asset.ec2_instance_id}  ip={asset.ip_address}\n"
            f"  known_fp_patterns={json.dumps(asset.fp_patterns or [])}\n"
        )
    return (
        f"Investigate this security alert.\n\n"
        f"Source: {alert.source}\n"
        f"Severity: {alert.severity}\n"
        f"Data: {json.dumps(alert.raw_data, default=str)}\n"
        f"{asset_ctx}\n"
        f"Using triage_agent and vuln_agent, investigate fully. "
        f"Correlate across all available tools and produce a final verdict."
    )


def process_queue():
    log.info("Processing work queue...")
    with _session() as s:
        alerts = s.query(Alert).filter(Alert.status == "new").order_by(Alert.created_at).limit(10).all()
        if not alerts:
            log.info("No new alerts.")
            return
        log.info(f"{len(alerts)} alerts to investigate.")
        for alert in alerts:
            log.info(f"  -> {alert.source} / {alert.severity} / {alert.id}")
            alert.status = "investigating"
            s.commit()

            rid = alert.raw_data.get("resource_id") or alert.raw_data.get("resource_ip", "")
            asset = s.query(Asset).filter(
                (Asset.ec2_instance_id == rid) | (Asset.ip_address == rid) | (Asset.hostname == rid)
            ).first() if rid else None

            prompt = _build_prompt(alert, asset)
            result = run_investigation(prompt, alert_id=alert.id)

            inv = Investigation(
                id=str(uuid.uuid4()),
                alert_id=alert.id,
                asset_id=asset.id if asset else None,
                triage_findings=result["triage_findings"],
                vuln_findings=result["vuln_findings"],
                final_verdict=result["final_verdict"],
                severity=result["severity"],
                hitl_required=result["hitl_required"],
                hitl_status=result["hitl_status"],
                hitl_thread_id=result["thread_id"],
                agent_trace=result["agent_trace"],
                created_at=datetime.utcnow(),
            )
            s.add(inv)

            alert.status = "escalated" if result["severity"] in ("critical", "high") else "closed"
            if asset:
                asset.last_investigation = datetime.utcnow()
            s.commit()

            if alert.status == "escalated":
                _notify(alert, inv)
            log.info(f"  done: {result['severity']} -> {alert.status}")


def scheduled_hunt():
    log.info("Running scheduled threat hunt...")
    result = run_threat_hunt()
    log.info(f"Hunt complete -- severity: {result['severity']}")

    with _session() as s:
        inv = Investigation(
            id=str(uuid.uuid4()),
            hunt_findings=result["hunt_findings"],
            final_verdict=result["final_verdict"],
            severity=result["severity"],
            agent_trace=result["agent_trace"],
            created_at=datetime.utcnow(),
        )
        s.add(inv)
        s.commit()


def _handle_sqs_task(task_data: dict):
    """Handle a manual trigger from the API via SQS."""
    task_type = task_data.get("type", "")
    in_args = task_data.get("in_args", {})

    if task_type == "soc.investigate":
        prompt = in_args.get("prompt", "")
        if prompt:
            result = run_investigation(prompt)
            with _session() as s:
                inv = Investigation(
                    id=str(uuid.uuid4()),
                    triage_findings=result["triage_findings"],
                    vuln_findings=result["vuln_findings"],
                    final_verdict=result["final_verdict"],
                    severity=result["severity"],
                    hitl_required=result["hitl_required"],
                    hitl_status=result["hitl_status"],
                    hitl_thread_id=result["thread_id"],
                    agent_trace=result["agent_trace"],
                    created_at=datetime.utcnow(),
                )
                s.add(inv)
                s.commit()
            log.info(f"SQS investigate complete: severity={result['severity']}")

    elif task_type == "soc.hunt":
        result = run_threat_hunt()
        with _session() as s:
            inv = Investigation(
                id=str(uuid.uuid4()),
                hunt_findings=result["hunt_findings"],
                final_verdict=result["final_verdict"],
                severity=result["severity"],
                agent_trace=result["agent_trace"],
                created_at=datetime.utcnow(),
            )
            s.add(inv)
            s.commit()
        log.info(f"SQS hunt complete: severity={result['severity']}")

    elif task_type == "soc.ingest":
        run_ingestion()
        log.info("SQS ingest complete")

    elif task_type == "soc.sync":
        from core.soc.scripts.sync_assets import run_sync
        sources = in_args.get("sources")
        run_sync(sources)
        log.info("SQS sync complete")

    else:
        log.warning(f"Unknown SOC task type: {task_type}")


def _sqs_consumer(stop_event: threading.Event):
    """Poll SQS for soc.* tasks in a background thread."""
    try:
        from core.sqs.consume import receive_messages, delete_message
        from core.sqs.get_client import get_sqs_client, get_queue_url
    except ImportError:
        log.warning("SQS modules not available, manual triggers disabled")
        return

    env = os.getenv("ENV_NAME", "prod")
    queue_name = f"biz-tool-{env}-task-queue"

    try:
        sqs_client = get_sqs_client()
        queue_url = get_queue_url(sqs_client, queue_name)
    except Exception as e:
        log.warning(f"Could not connect to SQS: {e}")
        return

    log.info(f"SQS consumer started, polling {queue_name}")

    while not stop_event.is_set():
        try:
            messages = receive_messages(sqs_client, queue_url, max_messages=1, wait_time=5)
            for msg in messages:
                body = msg.get("body", {})
                task_type = body.get("type", "")
                if task_type.startswith("soc."):
                    log.info(f"SQS received: {task_type}")
                    try:
                        _handle_sqs_task(body)
                    except Exception as e:
                        log.error(f"SQS task failed: {e}")
                    delete_message(sqs_client, queue_url, msg["receipt_handle"])
                # Non-soc tasks are left in the queue for the main worker
        except Exception as e:
            if not stop_event.is_set():
                log.error(f"SQS consumer error: {e}")


def run():
    init_db()
    log.info("=" * 60)
    log.info("  SOC Agent (LangGraph orchestrator) starting...")
    log.info("=" * 60)

    # Run immediately on startup
    run_ingestion()
    process_queue()

    from core.soc.scripts.sync_assets import run_sync as run_asset_sync
    run_asset_sync()

    # Start SQS consumer in background thread
    stop_event = threading.Event()
    sqs_thread = threading.Thread(target=_sqs_consumer, args=(stop_event,), daemon=True)
    sqs_thread.start()

    # Start APScheduler
    scheduler = BackgroundScheduler()
    scheduler.add_job(run_ingestion, "interval", minutes=10, id="ingest")
    scheduler.add_job(process_queue, "interval", minutes=15, id="triage")
    scheduler.add_job(run_asset_sync, "interval", hours=6, id="asset_sync")
    scheduler.add_job(scheduled_hunt, "cron", day_of_week="mon", hour=8, id="hunt")

    log.info("Scheduler running.")
    log.info("  Ingest:       every 10 min")
    log.info("  Triage:       every 15 min")
    log.info("  Asset sync:   every 6 hours")
    log.info("  Threat hunt:  Mondays 08:00")
    log.info("  SQS consumer: polling for manual triggers")

    scheduler.start()

    # Block until signal
    shutdown = threading.Event()

    def _shutdown(sig, frame):
        log.info("Shutting down...")
        stop_event.set()
        scheduler.shutdown(wait=False)
        shutdown.set()

    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)
    shutdown.wait()
