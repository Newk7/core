import os
from psycopg2 import pool
from core.log import create_log

log = create_log(__name__)


def get_db_pool(env_name: str = None, db_name: str = None):
    """
    Get a PostgreSQL connection pool.

    Uses DEV_POSTGRES_TASK_* env vars for dev, POSTGRES_TASK_* for prod.

    :param env_name: 'dev' or 'prod' (defaults to ENV_NAME env var)
    :param db_name: override database name
    """
    if env_name is None:
        env_name = os.getenv('ENV_NAME', 'dev')

    if env_name in ['prod']:
        db_user = os.getenv('POSTGRES_TASK_USER')
        db_password = os.getenv('POSTGRES_TASK_PW')
        db_host = os.getenv('POSTGRES_TASK_FQDN')
        db_port = int(os.getenv('POSTGRES_TASK_PORT', '5432'))
        db_name = db_name or os.getenv('POSTGRES_TASK_DB_NAME', 'biztool')
    else:
        db_user = os.getenv('DEV_POSTGRES_TASK_USER')
        db_password = os.getenv('DEV_POSTGRES_TASK_PW')
        db_host = os.getenv('DEV_POSTGRES_TASK_FQDN', 'localhost')
        db_port = int(os.getenv('DEV_POSTGRES_TASK_PORT', '5432'))
        db_name = db_name or os.getenv('DEV_POSTGRES_TASK_DB_NAME', 'biztool')

    try:
        log.info(f'connecting to db env: {env_name}: postgresql://{db_user}:***@{db_host}:{db_port}/{db_name}')
        pl = pool.SimpleConnectionPool(
            minconn=1,
            maxconn=10,
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password,
        )
        log.info(f'connected to db env: {env_name}')
        return pl
    except Exception as e:
        log.error(f'failed connecting to db: postgresql://{db_user}:***@{db_host}:{db_port}/{db_name} error: {e}')
    return None
