"""
Three specialized ReAct agents built with LangGraph's create_react_agent.

  triage_agent  - GuardDuty + Sentinel: active threat detection & alert correlation
  vuln_agent    - Wiz + Qualys + Snyk: vulnerability & exposure context
  hunt_agent    - Sentinel + GuardDuty cross-tool: proactive anomaly hunting

The supervisor (orchestrator/graph.py) decides which agents to invoke and
synthesises their findings into a final verdict.
"""
from core.log import create_log
log = create_log("soc.agents")
from langchain_anthropic import ChatAnthropic
from langgraph.prebuilt import create_react_agent

from core.soc.tools.guardduty import GUARDDUTY_TOOLS
from core.soc.tools.wiz import WIZ_TOOLS
from core.soc.tools.qualys import QUALYS_TOOLS
from core.soc.tools.snyk import SNYK_TOOLS

# Optional integrations — skip if deps not installed
try:
    from core.soc.tools.sentinel import SENTINEL_TOOLS
except ImportError:
    log.warning("sentinel tools unavailable (azure packages not installed)")
    SENTINEL_TOOLS = []

_model = ChatAnthropic(model="claude-sonnet-4-6", temperature=0)

# -- Triage Agent --
triage_agent = create_react_agent(
    model=_model,
    tools=GUARDDUTY_TOOLS + SENTINEL_TOOLS,
    name="triage_agent",
    prompt=(
        "You are a SOC triage specialist focused on ACTIVE THREATS.\n\n"
        "Your job:\n"
        "1. Investigate GuardDuty findings for the asset — behavioural anomalies, "
        "   unusual connections, credential abuse\n"
        "2. Query Sentinel logs to build a timeline of activity around the alert\n"
        "3. Cross-reference suspicious IPs across both tools\n"
        "4. Look for lateral movement indicators: port scanning, new service accounts, "
        "   unusual process trees, outbound connections to rare IPs\n\n"
        "Always end your response with a clear TRIAGE SUMMARY including:\n"
        "- Whether active exploitation is occurring (yes/no/unknown)\n"
        "- The highest severity finding you observed\n"
        "- Key IOCs (IPs, processes, account names) found\n"
        "- Confidence level (high/medium/low)\n\n"
        "Be specific. Your findings feed into a supervisor for final verdict."
    ),
)

# -- Vulnerability Agent --
vuln_agent = create_react_agent(
    model=_model,
    tools=WIZ_TOOLS + QUALYS_TOOLS + SNYK_TOOLS,
    name="vuln_agent",
    prompt=(
        "You are a vulnerability and exposure specialist.\n\n"
        "Your job:\n"
        "1. Pull Wiz issues for the asset — misconfigurations, CVEs, network exposure, "
        "   IAM problems\n"
        "2. Get Qualys vulnerability data — unpatched CVEs with CVSS scores\n"
        "3. Check Snyk for vulnerable code dependencies that could be exploited\n"
        "4. Run Wiz attack path analysis to understand blast radius\n"
        "5. Correlate: does Qualys show an unpatched CVE that Wiz shows is internet-exposed?\n\n"
        "Always end your response with a VULN SUMMARY including:\n"
        "- Top 3 most dangerous vulnerabilities for this asset (with CVE IDs if available)\n"
        "- Whether the asset has internet-exposed services with known CVEs\n"
        "- Estimated exploitability: immediate/likely/unlikely\n"
        "- Recommended patches or config fixes\n\n"
        "Be specific. Your findings feed into a supervisor for final verdict."
    ),
)

# -- Hunt Agent --
hunt_agent = create_react_agent(
    model=_model,
    tools=GUARDDUTY_TOOLS + SENTINEL_TOOLS + WIZ_TOOLS,
    name="hunt_agent",
    prompt=(
        "You are a proactive threat hunter.\n\n"
        "Your job (called on a schedule, not triggered by a specific alert):\n"
        "1. Review GuardDuty findings from the last 7 days — look for patterns "
        "   across multiple assets that individually look low-severity\n"
        "2. Query Sentinel for anomalous patterns: logins from new locations, "
        "   off-hours access, new admin account creations, unusual outbound volumes\n"
        "3. Check Wiz for newly exposed assets or new critical misconfigurations\n"
        "4. Look for lateral movement: assets that appear in multiple findings, "
        "   internal port scan patterns, service-to-service anomalies\n"
        "5. Identify the top 5 risks that do NOT currently have an open alert\n\n"
        "Always end with a HUNT SUMMARY:\n"
        "- Top findings ordered by risk\n"
        "- Recommended follow-up investigations\n"
        "- Any patterns suggesting an ongoing campaign\n\n"
        "Think like an adversary. What would you exploit if you were in the network?"
    ),
)
