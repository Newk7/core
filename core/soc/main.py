"""
SOC Agent entry point.
Usage:
  python -m core.soc.main agent       # Start scheduler + SQS consumer
  python -m core.soc.main seed        # Seed assets from config
  python -m core.soc.main investigate "prompt"  # One-off investigation
  python -m core.soc.main hunt        # One-off threat hunt
  python -m core.soc.main sync-assets [wiz|aws|qualys]  # Sync asset registry
"""
import sys
from core.soc.db.session import init_db


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "agent":
        from core.soc.scripts.scheduler import run
        run()

    elif cmd == "seed":
        init_db()
        print("[SOC] Database seeded.")

    elif cmd == "investigate":
        init_db()
        prompt = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else "Investigate the latest alerts."
        from core.soc.orchestrator.runner import run_investigation
        result = run_investigation(prompt)
        print(f"\nSeverity: {result['severity']}")
        print(f"HITL required: {result['hitl_required']}")
        print(f"\n{result['final_verdict']}")

    elif cmd == "hunt":
        init_db()
        from core.soc.orchestrator.runner import run_threat_hunt
        result = run_threat_hunt()
        print(f"\nSeverity: {result['severity']}")
        print(f"\n{result['final_verdict']}")

    elif cmd == "sync-assets":
        init_db()
        sources = sys.argv[2:] if len(sys.argv) > 2 else None
        from core.soc.scripts.sync_assets import run_sync
        run_sync(sources)

    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
