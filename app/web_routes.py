# app/web_routes.py
from fastapi import APIRouter, Request, Depends
from fastapi.responses import HTMLResponse, RedirectResponse, StreamingResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import date, datetime, timezone, timedelta
from pathlib import Path
import io
import csv
from typing import Union, Optional # KORREKTUR: Union und Optional importieren

from app.database import get_db
from app import crud
from app.auth import get_current_user_or_none 

# --- Konfiguration für diesen Router ---
PROJECT_ROOT_DIR = Path(__file__).resolve().parent.parent
TEMPLATES_DIR = PROJECT_ROOT_DIR / "templates"
templates = Jinja2Templates(directory=TEMPLATES_DIR)

# KORREKTUR: `datetime | None` wird zu `Union[datetime, None]`
def to_utc_iso_string(dt: Union[datetime, None]) -> str:
    if dt is None: return ""
    if dt.tzinfo is None: dt_utc = dt.replace(tzinfo=timezone.utc)
    else: dt_utc = dt.astimezone(timezone.utc)
    return dt_utc.isoformat().replace('+00:00', 'Z')
templates.env.globals['to_utc_iso'] = to_utc_iso_string


# --- Router-Definition mit Schutzmechanismus ---
router = APIRouter()

async def check_auth(user: Optional[str]) -> Union[RedirectResponse, None]:
    if not user:
        return RedirectResponse(url="/login")
    return None

@router.get("/", response_class=HTMLResponse)
async def read_root_html(user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect
    return RedirectResponse(url="/dashboard/laptops")

@router.get("/dashboard/laptops", response_class=HTMLResponse)
async def web_laptops_overview(request: Request, db: Session = Depends(get_db), user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect
        
    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    laptops_with_status = []
    now_utc = datetime.now(timezone.utc)
    for laptop_instance in all_laptops_db:
        status_info = {"text": "Unbekannt", "color_class": "status-unknown"} 
        if laptop_instance.last_scan_time is not None:
            last_scan_time_aware = laptop_instance.last_scan_time.astimezone(timezone.utc)
            time_since_last_scan = now_utc - last_scan_time_aware
            if laptop_instance.last_scan_threats_found is True:
                status_info = {"text": "Bedrohung(en) gefunden!", "color_class": "status-red"}
            elif time_since_last_scan <= timedelta(hours=5):
                status_info = {"text": "OK (aktuell)", "color_class": "status-green"}
            else: 
                status_info = {"text": "OK (älter als 5h)", "color_class": "status-yellow"}
        else:
            status_info = {"text": "Kein Scan bisher", "color_class": "status-white"}
        laptops_with_status.append({"db_data": laptop_instance, "scan_status": status_info})
    return templates.TemplateResponse("laptops_overview.html", {"request": request, "laptops_list": laptops_with_status, "title": "Laptop Übersicht", "user": user})

@router.get("/dashboard/daily_report/csv", response_class=StreamingResponse)
async def export_daily_report_csv(request: Request, report_date_str: Optional[str] = None, db: Session = Depends(get_db), user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect

    target_date: date
    if report_date_str:
        try: target_date = date.fromisoformat(report_date_str)
        except (ValueError, TypeError): target_date = date.today()
    else: target_date = date.today()
    
    # ... (Rest der CSV-Logik hier einfügen)
    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    output = io.StringIO()
    writer = csv.writer(output, delimiter=';')
    writer.writerow(["Alias", "Hostname", "Letzter Scan (UTC)", "Status", "Bedrohungen"])
    for laptop in all_laptops_db:
        writer.writerow([laptop.alias_name, laptop.hostname, to_utc_iso_string(laptop.last_scan_time), "OK", "Nein"]) # Beispiel
    output.seek(0)
    
    return StreamingResponse(io.BytesIO(output.getvalue().encode('utf-8-sig')), media_type="text/csv", headers={"Content-Disposition": f"attachment;filename=scanop_tagesbericht_{target_date.isoformat()}.csv"})


@router.get("/dashboard/daily_report", response_class=HTMLResponse)
async def web_daily_report(request: Request, report_date_str: Optional[str] = None, db: Session = Depends(get_db), user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect
        
    target_date: date
    report_title: str
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
        status_text, color_class = "N/A", "status-white"
        if laptop.last_scan_time is not None:
            last_scan_time_aware = laptop.last_scan_time.astimezone(timezone.utc)
            if laptop.last_scan_threats_found is True:
                status_text, color_class = "Bedrohung(en)!", "status-red"
            elif (now_utc.date() == last_scan_time_aware.date()) and (now_utc - last_scan_time_aware) <= timedelta(days=1):
                status_text, color_class = "OK (Scan heute)", "status-green"
            elif (now_utc - last_scan_time_aware) <= timedelta(days=1):
                status_text, color_class = "OK (Scan <24h)", "status-green"
            else:
                status_text, color_class = "OK (Scan älter)", "status-yellow"
        else:
            status_text, color_class = "Kein Scan bisher", "status-white"
        report_data.append({"db_data": laptop, "status_text": status_text, "status_color_class": color_class})
    return templates.TemplateResponse("daily_report.html", {"request": request, "report_date_iso": target_date.isoformat(), "report_date_display": target_date.strftime('%d.%m.%Y'), "laptops_report_data": report_data, "title": report_title, "user": user})