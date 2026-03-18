"""
Runs LangGraph graphs and returns structured investigation results.
Handles HITL thread persistence and resumption.
"""
import uuid
from core.soc.orchestrator.graph import investigation_graph, hunt_graph


def _extract_severity(text: str) -> str:
    text_lower = text.lower()
    for level in ["critical", "high", "medium", "low", "informational"]:
        if f"severity: {level}" in text_lower:
            return level
    return "medium"


def _extract_agent_findings(messages: list) -> dict:
    findings = {"triage": "", "vuln": "", "hunt": ""}
    for msg in messages:
        name = getattr(msg, "name", None)
        content = getattr(msg, "content", "")
        if isinstance(content, list):
            content = " ".join(c.get("text", "") if isinstance(c, dict) else str(c) for c in content)
        if name == "triage_agent":
            findings["triage"] = content
        elif name == "vuln_agent":
            findings["vuln"] = content
        elif name == "hunt_agent":
            findings["hunt"] = content
    return findings


def _last_substantive(messages: list) -> str:
    for msg in reversed(messages):
        content = getattr(msg, "content", "")
        if isinstance(content, str) and len(content) > 100:
            if "SEVERITY:" in content or "SUMMARY:" in content:
                return content
    if messages:
        return str(getattr(messages[-1], "content", ""))
    return ""


def _trace(messages: list) -> list:
    return [
        {
            "type": type(m).__name__,
            "name": getattr(m, "name", None),
            "content": str(getattr(m, "content", ""))[:500],
        }
        for m in messages
    ]


def run_investigation(prompt: str, alert_id: str = "") -> dict:
    """
    Run a full investigation through the supervisor graph.
    For CRITICAL/HIGH findings, sets hitl_required=True and preserves
    thread_id so the graph can be resumed after analyst review.
    """
    thread_id = str(uuid.uuid4())
    config = {"configurable": {"thread_id": thread_id}}

    result = investigation_graph.invoke(
        {"messages": [{"role": "user", "content": prompt}]},
        config=config,
    )

    messages = result.get("messages", [])
    findings = _extract_agent_findings(messages)
    final_text = _last_substantive(messages)
    severity = _extract_severity(final_text)
    hitl_required = severity in ("critical", "high")

    return {
        "alert_id": alert_id,
        "thread_id": thread_id,
        "final_verdict": final_text,
        "triage_findings": findings["triage"],
        "vuln_findings": findings["vuln"],
        "severity": severity,
        "hitl_required": hitl_required,
        "hitl_status": "pending" if hitl_required else None,
        "agent_trace": _trace(messages),
    }


def resume_investigation(thread_id: str, analyst_instruction: str) -> dict:
    """
    Resume a paused investigation after analyst review.
    Passes analyst instruction back into the graph as a new user message.
    """
    config = {"configurable": {"thread_id": thread_id}}

    result = investigation_graph.invoke(
        {"messages": [{"role": "user", "content": analyst_instruction}]},
        config=config,
    )

    messages = result.get("messages", [])
    final_text = _last_substantive(messages)
    severity = _extract_severity(final_text)

    return {
        "thread_id": thread_id,
        "final_verdict": final_text,
        "severity": severity,
        "agent_trace": _trace(messages),
    }


def run_threat_hunt(prompt: str = "") -> dict:
    """Run a proactive threat hunt. No HITL."""
    if not prompt:
        prompt = (
            "Perform a full proactive threat hunt across the environment. "
            "Review the last 7 days of GuardDuty findings, check Sentinel for "
            "anomalous patterns, and identify the top 5 risks without open alerts."
        )

    result = hunt_graph.invoke(
        {"messages": [{"role": "user", "content": prompt}]}
    )

    messages = result.get("messages", [])
    findings = _extract_agent_findings(messages)
    final_text = _last_substantive(messages)

    return {
        "final_verdict": final_text,
        "hunt_findings": findings["hunt"],
        "severity": _extract_severity(final_text),
        "agent_trace": _trace(messages),
    }
