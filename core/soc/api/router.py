"""
Main SOC router — mounts all sub-routers.
Included in core API at /api/v1/soc/
"""
from fastapi import APIRouter
from core.soc.api.routers import alerts, investigations, assets, feedback, agent, stats

soc_router = APIRouter()

soc_router.include_router(alerts.router, prefix="/alerts", tags=["soc-alerts"])
soc_router.include_router(investigations.router, prefix="/investigations", tags=["soc-investigations"])
soc_router.include_router(assets.router, prefix="/assets", tags=["soc-assets"])
soc_router.include_router(feedback.router, prefix="/feedback", tags=["soc-feedback"])
soc_router.include_router(agent.router, prefix="/agent", tags=["soc-agent"])
soc_router.include_router(stats.router, prefix="/stats", tags=["soc-stats"])
