from sqlalchemy import Column, String, DateTime, JSON, Text, Boolean
from sqlalchemy.orm import declarative_base
from datetime import datetime

Base = declarative_base()


class Alert(Base):
    __tablename__ = "alerts"
    id = Column(String, primary_key=True)
    source = Column(String)
    raw_data = Column(JSON)
    asset_id = Column(String)
    severity = Column(String)
    status = Column(String, default="new")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class Investigation(Base):
    __tablename__ = "investigations"
    id = Column(String, primary_key=True)
    alert_id = Column(String)
    asset_id = Column(String)
    triage_findings = Column(Text)
    vuln_findings = Column(Text)
    hunt_findings = Column(Text)
    final_verdict = Column(Text)
    severity = Column(String)
    recommended_action = Column(Text)
    agent_trace = Column(JSON)
    hitl_required = Column(Boolean, default=False)
    hitl_status = Column(String)
    hitl_thread_id = Column(String)
    analyst_notes = Column(Text)
    analyst_severity_override = Column(String)
    resolved_at = Column(DateTime)
    resolved_by = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)


class Asset(Base):
    __tablename__ = "assets"
    id = Column(String, primary_key=True)
    hostname = Column(String)
    ec2_instance_id = Column(String)
    ip_address = Column(String)
    wiz_resource_id = Column(String)
    qualys_asset_id = Column(String)
    snyk_project_id = Column(String)
    criticality = Column(String, default="medium")
    owner = Column(String)
    environment = Column(String)
    tags = Column(JSON, default=dict)
    fp_patterns = Column(JSON, default=list)
    last_investigation = Column(DateTime)
    created_at = Column(DateTime, default=datetime.utcnow)


class AnalystFeedback(Base):
    __tablename__ = "analyst_feedback"
    id = Column(String, primary_key=True)
    investigation_id = Column(String)
    alert_id = Column(String)
    asset_id = Column(String)
    agent_severity = Column(String)
    analyst_severity = Column(String)
    action = Column(String)
    notes = Column(Text)
    created_at = Column(DateTime, default=datetime.utcnow)
