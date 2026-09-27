"""Check deployed schema using the application's restricted database login."""
import os
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlsplit

settings = dict(line.split('=', 1) for line in
                Path('/home/ubuntu/frontierTank/.deploy/api.env').read_text().splitlines() if '=' in line)
uri = urlsplit(settings['DATABASE_URL'])
env = dict(os.environ, PGHOST=uri.hostname, PGPORT=str(uri.port),
           PGUSER=unquote(uri.username), PGPASSWORD=unquote(uri.password),
           PGDATABASE=uri.path.lstrip('/'), PGSSLMODE='require', PGCONNECT_TIMEOUT='15')
cmd = ['docker', 'run', '--rm', '-i']
for key in ('PGHOST', 'PGPORT', 'PGUSER', 'PGPASSWORD', 'PGDATABASE', 'PGSSLMODE', 'PGCONNECT_TIMEOUT'):
    cmd += ['-e', key]
cmd += ['postgres:17-alpine', 'psql', '-X', '-v', 'ON_ERROR_STOP=1']
sql = """
SELECT current_database(),current_user;
SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid();
SELECT rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user;
SELECT name FROM schema_migrations ORDER BY name;
SELECT count(*) AS application_tables FROM information_schema.tables WHERE table_schema='public';
"""
raise SystemExit(subprocess.run(cmd, input=sql, text=True, env=env).returncode)
