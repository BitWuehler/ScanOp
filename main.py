# main.py

from fastapi import FastAPI, Request, Depends
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pathlib import Path
from sqlalchemy.orm import Session
from sqlalchemy import func # für max()
from datetime import datetime, timezone, timedelta

# Importieren Sie die Router aus Ihren Endpoint-Modulen
from app.api.endpoints import laptops, reports, commands

# Importieren Sie Abhängigkeiten
from app.database import get_db
from app import crud
from app import models

# Basispfad des Projekts (wo main.py liegt)
PROJECT_ROOT_DIR = Path(__file__).resolve().parent

app = FastAPI(
    title="Willkommen zu ScanOp!",
    description="API zur Steuerung und Überwachung von Virenscans auf Client-Laptops.",
    version="0.1.0",
)

STATIC_FILES_DIR = PROJECT_ROOT_DIR / "static"
TEMPLATES_DIR = PROJECT_ROOT_DIR / "templates"

if not STATIC_FILES_DIR.is_dir():
    print(f"WARNUNG: Static-Verzeichnis nicht gefunden: {STATIC_FILES_DIR}")
if not TEMPLATES_DIR.is_dir():
    print(f"WARNUNG: Templates-Verzeichnis nicht gefunden: {TEMPLATES_DIR}")

app.mount("/static", StaticFiles(directory=STATIC_FILES_DIR), name="static")
templates = Jinja2Templates(directory=TEMPLATES_DIR)


@app.get("/", response_class=HTMLResponse)
async def read_root_html(request: Request):
    return templates.TemplateResponse("index.html", {"request": request, "title": "Willkommen bei ScanOp"})

@app.get("/api/health")
async def health_check():
    return {"status": "ok", "message": "API ist betriebsbereit."}

app.include_router(laptops.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(commands.router, prefix="/api/v1")


# --- WEB-ROUTEN FÜR DAS INTERFACE ---

@app.get("/dashboard/laptops", response_class=HTMLResponse)
async def web_laptops_overview(request: Request, db: Session = Depends(get_db)):
    all_laptops_db = crud.get_laptops(db=db, limit=1000)
    
    laptops_with_status = []
    now_utc = datetime.now(timezone.utc) # Dies ist offset-aware (UTC)

    for laptop_instance in all_laptops_db:
        status_info = {"text": "Unbekannt", "color_class": "status-unknown"} 
        
        last_scan_time_val = laptop_instance.last_scan_time
        last_scan_threats_found_val = laptop_instance.last_scan_threats_found

        if last_scan_time_val is not None:
            # Sicherstellen, dass last_scan_time_val offset-aware (UTC) ist
            if last_scan_time_val.tzinfo is None or last_scan_time_val.tzinfo.utcoffset(last_scan_time_val) is None:
                # Es ist naiv, wir nehmen an, es sollte UTC sein und machen es aware
                print(f"WARNUNG: last_scan_time für Laptop {laptop_instance.id} ist offset-naive ({last_scan_time_val}). Nehme UTC an.")
                last_scan_time_val = last_scan_time_val.replace(tzinfo=timezone.utc)
            else:
                # Es ist bereits aware, konvertiere es sicherheitshalber nach UTC, falls es eine andere Zeitzone wäre
                last_scan_time_val = last_scan_time_val.astimezone(timezone.utc)
            
            # Jetzt sollte die Subtraktion funktionieren
            assert isinstance(last_scan_time_val, datetime) and last_scan_time_val.tzinfo is not None # Nur zur Sicherheit
            time_since_last_scan = now_utc - last_scan_time_val

            if last_scan_threats_found_val is True:
                status_info = {"text": "Bedrohung(en) gefunden!", "color_class": "status-red"}
            else: 
                is_recent_scan = time_since_last_scan <= timedelta(hours=5)
                if is_recent_scan:
                    status_info = {"text": "OK (aktuell)", "color_class": "status-green"}
                else: 
                    status_info = {"text": "OK (älter als 5h)", "color_class": "status-yellow"}
        else:
            status_info = {"text": "Kein Scan bisher", "color_class": "status-white"}

        laptops_with_status.append({
            "db_data": laptop_instance,
            "scan_status": status_info
        })

    return templates.TemplateResponse("laptops_overview.html", {
        "request": request,
        "laptops_list": laptops_with_status,
        "title": "Laptop Übersicht"
    })

# API-Endpunkt für den Update-Check
@app.get("/api/v1/reports/last_update_timestamp", include_in_schema=False)
async def get_last_report_timestamp(db: Session = Depends(get_db)):
    last_report_time_db = db.query(func.max(models.ScanReport.report_time_on_server)).scalar() # Umbenannt für Klarheit
    
    if last_report_time_db is not None:
        # Auch hier sicherstellen, dass es aware ist, bevor isoformat aufgerufen wird, obwohl es aus der DB kommen sollte.
        # SQLAlchemy mit timezone=True sollte das eigentlich schon handhaben.
        if last_report_time_db.tzinfo is None or last_report_time_db.tzinfo.utcoffset(last_report_time_db) is None:
            print(f"WARNUNG: last_report_time_db aus Query ist offset-naive ({last_report_time_db}). Nehme UTC an.")
            last_report_time_db = last_report_time_db.replace(tzinfo=timezone.utc)
        else:
            last_report_time_db = last_report_time_db.astimezone(timezone.utc)
        return {"last_update": last_report_time_db.isoformat()}
    return {"last_update": None}