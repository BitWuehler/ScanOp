<div align="center">
  <img src="static/scanop_logo.png" alt="ScanOp Logo" width="250"/>
  <h1>ScanOp</h1>
  <p><b>Zentrales Virenscan-Management & Monitoring für Windows Clients</b></p>

  ![Python](https://img.shields.io/badge/Python-3.12-blue.svg?logo=python)
  ![FastAPI](https://img.shields.io/badge/FastAPI-0.100+-009688.svg?logo=fastapi)
  ![Docker](https://img.shields.io/badge/Docker-Ready-2496ED.svg?logo=docker)
  ![PowerShell](https://img.shields.io/badge/Client-PowerShell-5391FE.svg?logo=powershell)
</div>

---

## 🎯 Über ScanOp

ScanOp ist eine moderne, leichtgewichtige Webanwendung zur zentralen Steuerung und Überwachung von **Windows Defender Virenscans** über ein Netzwerk. Es ermöglicht Administratoren, den Sicherheitsstatus einer Flotte von Windows-Laptops zentral einzusehen, Scans aus der Ferne zu triggern und detaillierte PDF/CSV-Berichte zu generieren.

## ✨ Kernfunktionen

| Kategorie | Funktion | Beschreibung |
| :--- | :--- | :--- |
| 🛡️ **Sicherheit** | **Zentrales Management** | Starten Sie *Quick-* oder *Full-Scans* bequem über das Web-Dashboard für einzelne Laptops oder das gesamte Netzwerk. |
| 📊 **Monitoring** | **Live-Status** | Sehen Sie auf einen Blick, ob Clients online sind, wann der letzte Scan lief und ob Bedrohungen gefunden wurden. |
| 📈 **Reporting** | **Tagesberichte** | Exportieren Sie übersichtliche Tagesberichte als hochauflösendes PDF oder maschinenlesbares CSV für Ihre Audits. |
| 🔄 **Updates** | **Remote-Updates** | Pushen Sie Client-Updates vollautomatisch über GitHub direkt aus dem Webinterface an alle Laptops. |
| 🔌 **Architektur** | **Sichere API** | Robuste Polling-Architektur. Clients kontaktieren den Server via HTTPS und authentifizieren sich mit einem starken API-Key. |

---

## 🚀 Server-Setup (Docker Deployment)

Das produktive Setup erfolgt am einfachsten und sichersten über Docker. Dank der integrierten GitHub Container Registry (GHCR) müssen Sie den Code nicht einmal klonen!

### 1. `docker-compose.yml` herunterladen
Laden Sie sich lediglich die Konfigurationsdatei auf Ihren Docker-Host herunter:
```bash
curl -o docker-compose.yml https://raw.githubusercontent.com/BitWuehler/ScanOp/main/docker-compose.yml
```

### 2. Geheimnisse eintragen
Öffnen Sie die `docker-compose.yml` und passen Sie die Environment-Variablen an:
* `SECRET_KEY`: Ein beliebiger, langer String für die Session-Sicherheit.
* `SERVER_API_KEY`: Der geheime Schlüssel, mit dem sich die Laptops später am Server ausweisen.
* `APP_PASSWORD`: Ein **Bcrypt-Hash** für den Login in das Web-Dashboard (Nutzen Sie lokal `python hash_password.py` um einen Hash zu generieren).

### 3. Server starten
Docker zieht das fertige Image automatisch herunter, aktualisiert die Datenbank und startet den Webserver:
```bash
docker compose up -d
```

> [!TIP]
> **Updates einspielen:** Um ScanOp später zu aktualisieren, wenn ein neues Release auf GitHub verfügbar ist, genügt ein einfaches:
> `docker compose pull && docker compose up -d` 
> Ihre Datenbank im Ordner `./data` bleibt dabei erhalten!

---

## 💻 Client-Installation

Damit die Windows-Laptops mit dem Server kommunizieren, steht ein robuster PowerShell-Installer bereit.

1. Gehen Sie auf die **Releases-Seite** dieses Repositories auf GitHub.
2. Laden Sie die angeheftete **`ScanOp-Client.zip`** des aktuellsten Releases herunter und entpacken Sie diese auf dem Windows-Laptop.
3. Führen Sie `start_installer.cmd` als Administrator aus.
4. Folgen Sie den Anweisungen, um die URL Ihres Servers, den `SERVER_API_KEY` und einen Namen (Alias) für den Laptop einzugeben.

*(Alternativ: Legen Sie vor der Installation eine Datei namens `client_config.json` in den Entpack-Ordner, um die Installation komplett ohne Benutzereingaben (`unattended`) durchzuführen).*

---

## 🛠️ Lokale Entwicklung

Für Entwickler, die an ScanOp mitarbeiten möchten:

1. **Klonen & Setup:**
   ```bash
   git clone https://github.com/BitWuehler/ScanOp.git
   cd ScanOp
   python -m venv .venv
   source .venv/bin/activate  # Windows: .\.venv\Scripts\activate
   pip install -r requirements.txt
   ```
2. **Datenbank & Umgebung:**
   Kopieren Sie `.env.example` zu `.env` und passen Sie die Werte an.
   Führen Sie die Datenbank-Migrationen aus:
   ```bash
   alembic upgrade head
   ```
3. **Starten:**
   ```bash
   uvicorn main:app --reload
   ```

---
<div align="center">
  <i>Gebaut für IT-Admins, die den Überblick behalten wollen.</i>
</div>