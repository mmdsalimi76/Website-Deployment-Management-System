#!/bin/bash

set -e

# --- Environment Pre-flight ---
# Ensure database is reachable
if [ "$1" = 'web' ] || [ "$1" = 'celery' ]; then
    echo "[ENTRYPOINT] Checking database connection..."
    # We use a simple python check since we already have it in the base image
    python << END
import socket
import time
import os

host = os.environ.get('POSTGRES_HOST', 'db')
port = int(os.environ.get('POSTGRES_PORT', 5432))

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
while True:
    try:
        s.connect((host, port))
        s.close()
        break
    except socket.error:
        print(f"[ENTRYPOINT] Waiting for database at {host}:{port}...")
        time.sleep(1)
END
    echo "[ENTRYPOINT] Database is up!"
fi

# --- Command Routing ---
if [ "$1" = 'web' ]; then
    echo "[ENTRYPOINT] Starting Gunicorn..."
    # Collect static files (without clear to avoid permission issues with volumes)
    python manage.py collectstatic --noinput
    
    # Start Gunicorn
    # We use 0.0.0.0 to be reachable by Nginx in the frontend network
    exec gunicorn config.wsgi:application \
        --bind 0.0.0.0:8000 \
        --workers 3 \
        --access-logfile - \
        --error-logfile - \
        --worker-tmp-dir /dev/shm
        
elif [ "$1" = 'celery' ]; then
    echo "[ENTRYPOINT] Starting Celery Worker..."
    exec celery -A config worker --loglevel=info

elif [ "$1" = 'celery-beat' ]; then
    echo "[ENTRYPOINT] Starting Celery Beat..."
    # Remove old pid file if it exists
    rm -f /tmp/celerybeat.pid
    exec celery -A config beat --loglevel=info --pidfile=/tmp/celerybeat.pid

elif [ "$1" = 'migrate' ]; then
    echo "[ENTRYPOINT] Running Migrations..."
    python manage.py migrate --noinput
    echo "[ENTRYPOINT] Migrations Complete."

else
    # Fallback to executing whatever was passed
    exec "$@"
fi
