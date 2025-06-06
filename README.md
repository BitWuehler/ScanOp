# ScanOp - Virenscan-Management-Tool

ScanOp ist eine Webanwendung zur zentralen Steuerung und Überwachung von Windows Defender Virenscans auf mehreren Client-Laptops. Es bietet ein Webinterface, um den Status der Laptops einzusehen, Scans zu starten und Berichte zu exportieren.

## Features

-   Web-Dashboard zur Übersicht aller verbundenen Laptops
-   Manueller Start von Quick- und Full-Scans (pro Laptop oder für alle)
-   Statusanzeige (OK, Bedrohung gefunden, älterer Scan)
-   Tagesberichte mit Export als CSV und PDF

## Setup & Installation

1.  **Repository klonen:**
    ```bash
    git clone https://github.com/BitWuehler/ScanOp.git
    cd ScanOp
    ```

2.  **Virtuelles Environment erstellen und aktivieren:**
    ```bash
    python -m venv .venv
    # Windows
    .\.venv\Scripts\activate
    # macOS/Linux
    source .venv/bin/activate
    ```

3.  **Abhängigkeiten installieren:**
    ```bash
    pip install -r requirements.txt
    ```

4.  **Konfigurationsdatei erstellen:**
    Kopieren Sie die `.env.example`-Datei zu `.env` und passen Sie die Werte an.
    ```bash
    # Beispiel-Inhalt für .env
    DATABASE_URL="sqlite:///./scanop.db"
    ```

5.  **Datenbank initialisieren:**
    (Anleitung hier hinzufügen, falls Sie Alembic oder eine manuelle Initialisierung verwenden)

6.  **Server starten:**
    ```bash
    uvicorn main:app --reload
    ```
    Der Server ist nun unter `http://127.0.0.1:8000` erreichbar.

## Client-Skript

Das zugehörige PowerShell-Client-Skript `ScanOpClient_Polling.ps1` muss auf jedem zu überwachenden Laptop platziert werden. Konfigurieren Sie die `client_config.json` entsprechend.