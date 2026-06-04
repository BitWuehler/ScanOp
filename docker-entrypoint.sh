#!/bin/bash
set -e

echo "Starte Datenbank-Migrationen via Alembic..."
# Wendet alle noch nicht ausgeführten Migrationen an
python -m alembic upgrade head

echo "Starte Uvicorn Server..."
# Startet FastAPI über Uvicorn
exec uvicorn main:app --host 0.0.0.0 --port 8000
