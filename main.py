# main.py
from fastapi import FastAPI, Request, Depends, HTTPException, status
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pathlib import Path
from sqlalchemy.orm import Session
from sqlalchemy import func 
from datetime import date, datetime, timezone, timedelta
import io
import csv # Für serverseitigen CSV-Export, falls wir das später wollen

# API Router und App-Module
from app.api.endpoints import laptops, reports, commands
from app.database import get_db
from app import crud, models, schemas # schemas importieren

# Basispfad des Projekts (wo main.py liegt)
PROJECT_ROOT_DIR = Path(__file__).resolve().parent

app = FastAPI(
    title="Willkommen zu ScanOp!",
    description="API zur Steuerung und Überwachung von Virenscans auf Client-Laptops.",
    version="0.1.0",
    # Uvicorn --proxy-headers wird für HTTPS hinter Reverse Proxy benötigt
)

STATIC_FILES_DIR = PROJECT_ROOT_DIR / "static"
TEMPLATES_DIR = PROJECT_ROOT_DIR / "templates"

# Sicherstellen, dass die Verzeichnisse existieren (optional, aber gutes Debugging)
if not STATIC_FILES_DIR.is_dir():
    print(f"WARNUNG: Static-Verzeichnis nicht gefunden: {STATIC_FILES_DIR} (erwartet neben main.py)")
if not TEMPLATES_DIR.is_dir():
    print(f"WARNUNG: Templates-Verzeichnis nicht gefunden: {TEMPLATES_DIR} (erwartet neben main.py)")

app.mount("/static", StaticFiles(directory=STATIC_FILES_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATES_DIR)


# --- Web-Routen für das Interface ---
@app.get("/", response_class=HTMLResponse)
async def read_root_html(request: Request):
    return templates.TemplateResponse("index.html", {
        "request": request,
        "title": "Willkommen bei ScanOp"
    })

@app.get("/dashboard/laptops", response_class=HTMLResponse)
async def web_laptops_overview(request: Request, db: Session = Depends(get_db)):
    all_laptops_db = crud.get_laptops(db=db, limit=10000) # Erhöhe Limit für Übersicht
    
    laptops_with_status = []
    now_utc = datetime.now(timezone.utc)

    for laptop_instance in all_laptops_db:
        status_info = {"text": "Unbekannt", "color_class": "status-unknown"} 
        
        last_scan_time_val = laptop_instance.last_scan_time
        last_scan_threats_found_val = laptop_instance.last_scan_threats_found

        if last_scan_time_val is not None:
            # Sicherstellen, dass last_scan_time_val offset-aware (UTC) ist
            # (Sollte durch DB-Modell schon so sein, aber als Absicherung)
            if last_scan_time_val.tzinfo is None or last_scan_time_val.tzinfo.utcoffset(last_scan_time_val) is None:
                last_scan_time_val = last_scan_time_val.replace(tzinfo=timezone.utc)
            else:
                last_scan_time_val = last_scan_time_val.astimezone(timezone.utc)
            
            time_since_last_scan = now_utc - last_scan_time_val

            if last_scan_threats_found_val is True:
                status_info = {"text": "Bedrohung(en) gefunden!", "color_class": "status-red"}
            elif time_since_last_scan <= timedelta(hours=5): # 5-Stunden-Regel
                status_info = {"text": "OK (aktuell)", "color_class": "status-green"}
            else: 
                status_info = {"text": "OK (älter als 5h)", "color_class": "status-yellow"}
        else:
            status_info = {"text": "Kein Scan bisher", "color_class": "status-white"}

        laptops_with_status.append({
            "db_data": laptop_instance, # Für Zugriff auf alle Laptop-Attribute im Template
            "scan_status": status_info
        })

    return templates.TemplateResponse("laptops_overview.html", {
        "request": request,
        "laptops_list": laptops_with_status,
        "title": "Laptop Übersicht"
    })

@app.get("/dashboard/daily_report", response_class=HTMLResponse)
async def web_daily_report(
    request: Request,
    report_date_str: str | None = None, 
    db: Session = Depends(get_db)
):
    target_date: date
    if report_date_str:
        try:
            target_date = date.fromisoformat(report_date_str)
        except ValueError:
            # Fallback auf heute bei ungültigem Format, mit Meldung (oder Fehler werfen)
            # Hier einfacher: Fallback mit Hinweis im Titel
            target_date = date.today()
            report_title = f"Tagesbericht für HEUTE ({target_date.strftime('%d.%m.%Y')}) - Ungültiges Datum angegeben"
    else:
        target_date = date.today()
        report_title = f"Tagesbericht für {target_date.strftime('%d.%m.%Y')}"

    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    report_data = []
    now_utc = datetime.now(timezone.utc)

    for laptop in all_laptops_db:
        status_text = "N/A"
        scan_time_for_report_utc_iso = None
        scan_time_for_report_display = "N/A"
        scan_result_display = "N/A"
        threats_found_for_report = None
        color_class = "status-white"

        # Hier könnten wir komplexere Logik einbauen, um den relevantesten Scan für `target_date` zu finden.
        # Fürs Erste: Wir zeigen den letzten bekannten Scan-Status des Laptops an.
        # Der "Tagesbericht" ist dann eher ein "Status aller Laptops am Zieldatum (basierend auf letztem Scan)".
        
        if laptop.last_scan_time:
            # Sicherstellen, dass es aware ist für Vergleiche
            last_scan_time_aware = laptop.last_scan_time
            if last_scan_time_aware.tzinfo is None: # Sollte nicht passieren
                last_scan_time_aware = last_scan_time_aware.replace(tzinfo=timezone.utc)
            else:
                last_scan_time_aware = last_scan_time_aware.astimezone(timezone.utc)

            scan_time_for_report_utc_iso = last_scan_time_aware.isoformat()
            scan_time_for_report_display = last_scan_time_aware.strftime('%Y-%m-%d %H:%M:%S UTC')
            scan_result_display = laptop.last_scan_result_message or "Keine Details"
            threats_found_for_report = laptop.last_scan_threats_found

            if threats_found_for_report is True:
                status_text = "Bedrohung(en)!"
                color_class = "status-red"
            # Für den Tagesbericht könnte die 5-Stunden-Regel weniger relevant sein,
            # wichtiger ist, ob an diesem Tag ein "sauberer" Scan lief.
            # Die aktuelle Logik zeigt den letzten Status.
            elif (now_utc.date() == last_scan_time_aware.date()) and (now_utc - last_scan_time_aware) <= timedelta(days=1) : # Scan von heute und innerhalb 24h
                status_text = "OK (Scan heute)"
                color_class = "status-green"
            elif (now_utc - last_scan_time_aware) <= timedelta(days=1): # Scan innerhalb 24h
                 status_text = "OK (Scan <24h)"
                 color_class = "status-green"
            else:
                status_text = "OK (Scan älter)"
                color_class = "status-yellow"
        else:
            status_text = "Kein Scan bisher"
            color_class = "status-white"


        report_data.append({
            "alias_name": laptop.alias_name,
            "hostname": laptop.hostname,
            "last_scan_time_utc": scan_time_for_report_utc_iso,
            "last_scan_time_display": scan_time_for_report_display,
            "last_scan_result": scan_result_display,
            "threats_found": threats_found_for_report, # Kann None, True, False sein
            "status_text": status_text,
            "status_color_class": color_class
        })

    return templates.TemplateResponse("daily_report.html", {
        "request": request,
        "report_date_iso": target_date.isoformat(), # Für das Formularfeld
        "report_date_display": target_date.strftime('%d.%m.%Y'), # Für die Überschrift
        "laptops_report_data": report_data,
        "title": report_title
    })


# --- API Endpunkte (bleiben wie sie sind) ---
@app.get("/api/health")
async def health_check():
    return {"status": "ok", "message": "API ist betriebsbereit."}

# Einbinden der API-Router
app.include_router(laptops.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(commands.router, prefix="/api/v1")

# API-Endpunkt für den Update-Check (für Polling der Laptop-Übersicht)
@app.get("/api/v1/reports/last_update_timestamp", include_in_schema=False)
async def get_last_report_timestamp(db: Session = Depends(get_db)):
    last_report_time_db = db.query(func.max(models.ScanReport.report_time_on_server)).scalar()
    
    if last_report_time_db is not None:
        # Sicherstellen, dass es aware ist, bevor isoformat aufgerufen wird
        if last_report_time_db.tzinfo is None or last_report_time_db.tzinfo.utcoffset(last_report_time_db) is None:
            last_report_time_db = last_report_time_db.replace(tzinfo=timezone.utc)
        else:
            last_report_time_db = last_report_time_db.astimezone(timezone.utc)
        return {"last_update": last_report_time_db.isoformat()}
    return {"last_update": None}