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
import csv

# API Router und App-Module
from app.api.endpoints import laptops, reports, commands
from app.database import get_db
from app import crud, models, schemas

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
    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    
    laptops_with_status = []
    now_utc = datetime.now(timezone.utc)

    for laptop_instance in all_laptops_db:
        status_info = {"text": "Unbekannt", "color_class": "status-unknown"} 
        
        last_scan_time_val = laptop_instance.last_scan_time
        last_scan_threats_found_val = laptop_instance.last_scan_threats_found

        # Pylance-Korrektur: Expliziter `is not None` Check
        if last_scan_time_val is not None:
            if last_scan_time_val.tzinfo is None or last_scan_time_val.tzinfo.utcoffset(last_scan_time_val) is None:
                last_scan_time_val = last_scan_time_val.replace(tzinfo=timezone.utc)
            else:
                last_scan_time_val = last_scan_time_val.astimezone(timezone.utc)
            
            time_since_last_scan = now_utc - last_scan_time_val

            if last_scan_threats_found_val is True:
                status_info = {"text": "Bedrohung(en) gefunden!", "color_class": "status-red"}
            elif time_since_last_scan <= timedelta(hours=5):
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


# KORREKTUR: Die Export-Funktion wird direkt vor der Funktion platziert, die sie im Template aufruft.
@app.get("/dashboard/daily_report/csv", response_class=StreamingResponse)
async def export_daily_report_csv(
    request: Request,
    report_date_str: str | None = None, 
    db: Session = Depends(get_db)
):
    target_date: date
    if report_date_str:
        try:
            target_date = date.fromisoformat(report_date_str)
        except (ValueError, TypeError):
            target_date = date.today()
    else:
        target_date = date.today()

    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    report_data = []
    now_utc = datetime.now(timezone.utc)

    for laptop in all_laptops_db:
        status_text = "N/A"
        scan_time_for_report_display = "N/A"
        scan_result_display = "N/A"
        threats_found_display = "N/A"
        
        if laptop.last_scan_time is not None:
            last_scan_time_aware = laptop.last_scan_time.astimezone(timezone.utc)
            scan_time_for_report_display = last_scan_time_aware.strftime('%Y-%m-%d %H:%M:%S UTC')
            scan_result_display = laptop.last_scan_result_message or "Keine Details"
            
            if laptop.last_scan_threats_found is True:
                threats_found_display = "Ja"
                status_text = "Bedrohung(en)!"
            elif laptop.last_scan_threats_found is False:
                threats_found_display = "Nein"
                if (now_utc.date() == last_scan_time_aware.date()) and (now_utc - last_scan_time_aware) <= timedelta(days=1):
                    status_text = "OK (Scan heute)"
                elif (now_utc - last_scan_time_aware) <= timedelta(days=1):
                    status_text = "OK (Scan <24h)"
                else:
                    status_text = "OK (Scan älter)"
            else:
                 threats_found_display = "Unbekannt"
                 status_text = "OK (Status unklar)"
        else:
            status_text = "Kein Scan bisher"

        report_data.append({
            "alias_name": laptop.alias_name,
            "hostname": laptop.hostname,
            "last_scan_time_display": scan_time_for_report_display,
            "last_scan_result": scan_result_display,
            "threats_found": threats_found_display,
            "status_text": status_text,
        })
    
    output = io.StringIO()
    writer = csv.writer(output, delimiter=';', quotechar='"', quoting=csv.QUOTE_MINIMAL)

    header = ["Alias", "Hostname", "Letzter Scan (UTC)", "Scan Ergebnis", "Bedrohungen gefunden", "Status"]
    writer.writerow(header)

    for laptop_report in report_data:
        writer.writerow([
            laptop_report["alias_name"],
            laptop_report["hostname"],
            laptop_report["last_scan_time_display"],
            laptop_report["last_scan_result"],
            laptop_report["threats_found"],
            laptop_report["status_text"]
        ])

    output.seek(0)
    
    csv_filename = f"scanop_tagesbericht_{target_date.strftime('%Y-%m-%d')}.csv"
    headers = {
        "Content-Disposition": f"attachment; filename=\"{csv_filename}\""
    }
    
    bom = "\ufeff".encode("utf-8")
    
    return StreamingResponse(
        iter([bom + output.getvalue().encode("utf-8")]),
        media_type="text/csv",
        headers=headers
    )


@app.get("/dashboard/daily_report", response_class=HTMLResponse)
async def web_daily_report(
    request: Request,
    report_date_str: str | None = None, 
    db: Session = Depends(get_db)
):
    target_date: date
    report_title: str

    # Pylance-Korrektur: Sicherstellen, dass report_title in allen Pfaden zugewiesen wird.
    if report_date_str:
        try:
            target_date = date.fromisoformat(report_date_str)
            report_title = f"Tagesbericht für {target_date.strftime('%d.%m.%Y')}"
        except (ValueError, TypeError):
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

        # Pylance-Korrektur: Expliziter `is not None` Check
        if laptop.last_scan_time is not None:
            last_scan_time_aware = laptop.last_scan_time.astimezone(timezone.utc)
            scan_time_for_report_utc_iso = last_scan_time_aware.isoformat()
            scan_time_for_report_display = last_scan_time_aware.strftime('%Y-%m-%d %H:%M:%S UTC')
            scan_result_display = laptop.last_scan_result_message or "Keine Details"
            threats_found_for_report = laptop.last_scan_threats_found

            if threats_found_for_report is True:
                status_text = "Bedrohung(en)!"
                color_class = "status-red"
            elif (now_utc.date() == last_scan_time_aware.date()) and (now_utc - last_scan_time_aware) <= timedelta(days=1) :
                status_text = "OK (Scan heute)"
                color_class = "status-green"
            elif (now_utc - last_scan_time_aware) <= timedelta(days=1):
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
            "threats_found": threats_found_for_report,
            "status_text": status_text,
            "status_color_class": color_class
        })

    return templates.TemplateResponse("daily_report.html", {
        "request": request,
        "report_date_iso": target_date.isoformat(),
        "report_date_display": target_date.strftime('%d.%m.%Y'),
        "laptops_report_data": report_data,
        "title": report_title
    })


# --- API Endpunkte ---
@app.get("/api/health")
async def health_check():
    return {"status": "ok", "message": "API ist betriebsbereit."}

app.include_router(laptops.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(commands.router, prefix="/api/v1")

@app.get("/api/v1/reports/last_update_timestamp", include_in_schema=False)
async def get_last_report_timestamp(db: Session = Depends(get_db)):
    last_report_time_db = db.query(func.max(models.ScanReport.report_time_on_server)).scalar()
    
    if last_report_time_db is not None:
        if last_report_time_db.tzinfo is None or last_report_time_db.tzinfo.utcoffset(last_report_time_db) is None:
            last_report_time_db = last_report_time_db.replace(tzinfo=timezone.utc)
        else:
            last_report_time_db = last_report_time_db.astimezone(timezone.utc)
        return {"last_update": last_report_time_db.isoformat()}
    return {"last_update": None}