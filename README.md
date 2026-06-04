# ScanOp - Virenscan-Management-Tool

ScanOp ist eine Webanwendung zur zentralen Steuerung und Überwachung von Windows Defender Virenscans auf mehreren Client-Laptops. Es bietet ein passwortgeschütztes Webinterface, um den Status der Laptops einzusehen, Scans zu starten und Berichte zu exportieren.

Die Kommunikation zwischen Client und Server ist durch einen API-Schlüssel gesichert.

## Features

-   Passwortgeschütztes Web-Dashboard
-   Übersicht aller verbundenen Laptops mit Live-Status
-   Manueller Start von Quick- und Full-Scans (pro Laptop oder für alle)
-   Tagesberichte mit Export als CSV und PDF
-   Sichere Client-Server-Kommunikation via API-Key
-   Einfacher Client-Installer für Windows

## Server-Setup (Docker - Empfohlen)

Am einfachsten lässt sich der Server über Docker bereitstellen. Alle benötigten Umgebungsvariablen können direkt in der `docker-compose.yml` definiert werden.

1. **`docker-compose.yml` herunterladen:**
    Laden Sie sich lediglich die `docker-compose.yml` Datei auf Ihren Docker-Host herunter. Ein Klonen des kompletten Repositories ist nicht mehr nötig!
    ```bash
    curl -o docker-compose.yml https://raw.githubusercontent.com/BitWuehler/ScanOp/main/docker-compose.yml
    ```

2. **Umgebungsvariablen anpassen:**
    Öffnen Sie die heruntergeladene `docker-compose.yml` und ersetzen Sie die Platzhalter (`SECRET_KEY`, `APP_PASSWORD`, `SERVER_API_KEY`) durch Ihre eigenen sicheren Werte. Das `APP_PASSWORD` muss ein Bcrypt-Hash sein.

3. **Server starten:**
    ```bash
    docker compose up -d
    ```
    Docker zieht nun automatisch das fertige Image von GitHub (ghcr.io). Der Server ist unter Port `8000` erreichbar. Die Datenbank (`scanop.db`) wird sicher im Ordner `./data` abgelegt.

4. **Updates installieren:**
    Sobald eine neue Version auf GitHub veröffentlicht wird, führen Sie einfach aus:
    ```bash
    docker compose pull
    docker compose up -d
    ```

---

## Server-Setup (Lokale Entwicklung)

1.  **Repository klonen:**
    ```bash
    git clone https://github.com/BitWuehler/ScanOp.git
    cd ScanOp
    ```

2.  **Virtuelles Environment erstellen und aktivieren:**
    ```bash
    python -m venv .venv
    # Windows:
    .\.venv\Scripts\activate
    # macOS/Linux:
    source .venv/bin/activate
    ```

3.  **Abhängigkeiten installieren:**
    ```bash
    pip install -r requirements.txt
    ```

4.  **Konfigurationsdatei `.env` erstellen:**
    Kopieren Sie die `.env.example`-Datei zu `.env` und passen Sie die Werte (insbesondere `SECRET_KEY` und `SERVER_API_KEY`) an. Generieren Sie einen Passwort-Hash für `APP_PASSWORD` mit dem `hash_password.py`-Skript.

5.  **Datenbank initialisieren:**
    (Falls Sie Alembic für Migrationen verwenden, fügen Sie hier die Anleitung hinzu. Ansonsten wird die SQLite-DB beim ersten Start automatisch erstellt.)

6.  **Server starten:**
    ```bash
    uvicorn main:app --reload
    ```
    Der Server ist nun unter `http://127.0.0.1:8000` erreichbar.

## Client-Installation

Siehe Anweisungen im `ScanOp-Client-Installer`-Verzeichnis.