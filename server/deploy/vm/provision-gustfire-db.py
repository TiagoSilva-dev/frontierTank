"""Run on the VM; receive the Railway administrator credentials as JSON on stdin."""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
from urllib.parse import quote, urlsplit, unquote

admin = json.load(sys.stdin)
deploy = Path('/home/ubuntu/frontierTank/.deploy')
env_path = deploy / 'api.env'

def psql(sql, user, password, database='railway'):
    env = dict(os.environ, PGHOST=admin['host'], PGPORT=str(admin['port']),
               PGUSER=user, PGPASSWORD=password, PGDATABASE=database,
               PGSSLMODE='require', PGCONNECT_TIMEOUT='15')
    cmd = ['docker', 'run', '--rm', '-i']
    for name in ('PGHOST', 'PGPORT', 'PGUSER', 'PGPASSWORD', 'PGDATABASE', 'PGSSLMODE', 'PGCONNECT_TIMEOUT'):
        cmd += ['-e', name]
    cmd += ['postgres:17-alpine', 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']
    result = subprocess.run(cmd, input=sql, text=True, capture_output=True, env=env)
    if result.returncode:
        print(result.stderr.replace(password, '[redacted]'), file=sys.stderr)
        raise SystemExit(result.returncode)
    return result.stdout.strip()

print('Administrator connection:', psql(
    "SELECT current_user, current_database(); SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid();",
    admin['user'], admin['password']), flush=True)
exists = psql("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='gustfire_app'), "
              "EXISTS(SELECT 1 FROM pg_database WHERE datname='gustfire');",
              admin['user'], admin['password'])
if env_path.exists():
    values = dict(line.split('=', 1) for line in env_path.read_text().splitlines() if '=' in line)
    app_password = unquote(urlsplit(values['DATABASE_URL']).password)
elif exists != 'f|f':
    raise SystemExit('The role or database already exists without a deployment credential; inspect before proceeding.')
else:
    app_password = secrets.token_urlsafe(36)
    uri = (f"postgresql://gustfire_app:{quote(app_password, safe='')}@{admin['host']}:{admin['port']}"
           '/gustfire?sslmode=require&connect_timeout=15&pool_max_conns=5')
    fd = os.open(env_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as out:
        out.write(f'DATABASE_URL={uri}\nINTERNAL_KEY={secrets.token_hex(32)}\n')

role_exists, database_exists = exists.split('|')
if role_exists == 'f':
    escaped_password = app_password.replace("'", "''")
    psql(f"CREATE ROLE gustfire_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD '{escaped_password}';",
         admin['user'], admin['password'])
if database_exists == 'f':
    psql('CREATE DATABASE gustfire OWNER gustfire_app;', admin['user'], admin['password'])

print('Application connection:', psql(
    "SELECT current_user,current_database(); SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid();",
    'gustfire_app', app_password, 'gustfire'), flush=True)
print('Dedicated database and role ready; deployment credentials stored with mode 600.')
