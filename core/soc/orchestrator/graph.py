"""
LangGraph supervisor graph with Human-in-the-Loop (HITL) support.

HITL flow for critical/high severity:
  START -> supervisor -> triage_agent -> supervisor -> vuln_agent
        -> supervisor produces verdict
        -> runner checks severity -- if critical/high, marks hitl_required=True
        -> graph thread persisted in MemorySaver with thread_id
        -> analyst reviews in dashboard, approves or rejects via API
        -> for approved: graph resumes and supervisor finalises
        -> for rejected/false_positive: alert closed with analyst notes

For medium/low: no interrupt, runs to completion automatically.
Threat hunt graph has no HITL.
"""
from langchain_anthropic import ChatAnthropic
from langgraph.checkpoint.memory import MemorySaver
from langgraph_supervisor import create_supervisor

from core.soc.orchestrator.agents import triage_agent, vuln_agent, hunt_agent

_model = ChatAnthropic(model="claude-sonnet-4-6", temperature=0)

# In-memory checkpointer -- swap to langgraph-checkpoint-postgres for multi-worker prod
checkpointer = MemorySaver()

SUPERVISOR_PROMPT = """You are the lead SOC analyst coordinating a specialist team.

YOUR TEAM:
- triage_agent: active threat investigation -- GuardDuty behavioural findings and Sentinel logs
- vuln_agent: vulnerability and exposure context -- Wiz, Qualys, Snyk

INVESTIGATION WORKFLOW:
1. Call triage_agent first -- is there active exploitation?
2. Call vuln_agent -- how exploitable is the affected asset?
3. Synthesise both into a final verdict

FINAL REPORT FORMAT (always use this exact structure):
---
SEVERITY: [critical / high / medium / low / informational]
CONFIDENCE: [high / medium / low]

SUMMARY:
2-3 sentence executive summary.

TRIAGE FINDINGS:
Key findings from active threat investigation.

VULNERABILITY CONTEXT:
Key findings from vulnerability and exposure analysis.

FINAL ASSESSMENT:
Your synthesis -- do the active signals and vulnerability context together suggest
a higher or lower risk than either alone?

RECOMMENDED ACTIONS:
1. Specific next step
2. Specific next step

REASONING:
Why you reached this severity and confidence.
---

Be decisive. Analysts need clear answers."""


def build_investigation_graph():
    """
    Compiled supervisor graph for alert investigations.
    Checkpointer enables HITL thread state persistence.
    """
    workflow = create_supervisor(
        agents=[triage_agent, vuln_agent],
        model=_model,
        prompt=SUPERVISOR_PROMPT,
    )
    return workflow.compile(checkpointer=checkpointer)


def build_hunt_graph():
    """Compiled supervisor graph for proactive threat hunts. No HITL."""
    workflow = create_supervisor(
        agents=[hunt_agent],
        model=_model,
        prompt=SUPERVISOR_PROMPT,
    )
    return workflow.compile()


investigation_graph = build_investigation_graph()
hunt_graph = build_hunt_graph()
