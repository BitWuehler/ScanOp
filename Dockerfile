# Verwende das offizielle und schlanke Python-Image als Basis
FROM python:3.12-slim

# Verhindere, dass Python *.pyc Dateien schreibt und stelle sicher, dass Ausgaben direkt in die Konsole fließen
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Setze das Arbeitsverzeichnis im Container
WORKDIR /app

# Kopiere die requirements.txt in den Container
COPY requirements.txt /app/

# Installiere die Abhängigkeiten
RUN pip install --no-cache-dir -r requirements.txt

# Kopiere den gesamten Projektcode in den Container
COPY . /app/

# Stelle sicher, dass das Entrypoint-Skript ausführbar ist
RUN chmod +x /app/docker-entrypoint.sh

# Öffne den Port 8000
EXPOSE 8000

# Definiere den Entrypoint, der Alembic ausführt und Uvicorn startet
ENTRYPOINT ["/app/docker-entrypoint.sh"]
