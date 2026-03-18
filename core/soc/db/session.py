import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session
from core.soc.db.models import Base

_engine = None


def get_engine():
    global _engine
    if _engine is None:
        url = os.getenv("SOC_DATABASE_URL", "postgresql://socagent:socagent@biz-tool-postgres:5432/socagent")
        _engine = create_engine(url)
    return _engine


def get_session() -> Session:
    return Session(get_engine())


def init_db():
    engine = get_engine()
    Base.metadata.create_all(engine)
    print("[SOC DB] Schema ready.")
