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

## Server-Setup (Entwicklung)

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