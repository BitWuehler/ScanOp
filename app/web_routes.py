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
    all_laptops_db = sorted(all_laptops_db, key=lambda x: (x.alias_name or "").lower())
    
    laptops_with_status = []
    now_utc = datetime.now(timezone.utc)
    for laptop_instance in all_laptops_db:
        is_online = False
        if laptop_instance.last_api_contact:
            contact_aware = laptop_instance.last_api_contact.replace(tzinfo=timezone.utc)
            if (now_utc - contact_aware) <= timedelta(minutes=5):
                is_online = True
                
        status_info = {"text": "Unbekannt", "color_class": "status-unknown", "style": ""} 
        if laptop_instance.last_scan_time is not None:
            last_scan_time_aware = laptop_instance.last_scan_time.replace(tzinfo=timezone.utc)
            time_since_last_scan = now_utc - last_scan_time_aware
            hours_since = time_since_last_scan.total_seconds() / 3600.0
            hours_rounded = round(hours_since)
            
            if laptop_instance.last_scan_threats_found is True:
                status_info = {"text": "Bedrohung(en) gefunden!", "color_class": "status-red", "style": ""}
            else:
                if hours_since <= 5:
                    hue = 120 # Green
                elif hours_since <= 12:
                    ratio = (hours_since - 5) / 7.0
                    hue = 120 - (ratio * 90)
                elif hours_since <= 24:
                    ratio = (hours_since - 12) / 12.0
                    hue = 30 - (ratio * 30)
                else:
                    hue = 0 # Red
                
                status_info = {
                    "text": f"OK ({hours_rounded}h)", 
                    "color_class": "", 
                    "style": f"color: hsl({hue}, 80%, 50%); font-weight: bold;"
                }
        else:
            status_info = {"text": "Kein Scan bisher", "color_class": "status-white", "style": ""}
            hours_rounded = 999999 # So it's always considered outdated if never scanned
            
        simplified_result_message = "N/A"
        if laptop_instance.last_scan_result_message:
            msg = laptop_instance.last_scan_result_message
            if "erfolgreich abgeschlossen" in msg:
                simplified_result_message = "OK"
            else:
                simplified_result_message = msg[:30] + ("..." if len(msg) > 30 else "")
                
        
        has_error = False
        has_threat = False
        msg_lower = (laptop_instance.last_scan_result_message or "").lower()
        if "fehler" in msg_lower:
            has_error = True
        if "fund!" in msg_lower or "siehe bericht" in msg_lower or "bedrohung" in msg_lower:
            has_threat = True
            
        laptops_with_status.append({
            "db_data": laptop_instance, 
            "scan_status": status_info,
            "is_online": is_online,
            "scan_hours": hours_rounded,
            "simplified_result_message": simplified_result_message,
            "has_error": has_error,
            "has_threat": has_threat
        })
    return templates.TemplateResponse("laptops_overview.html", {"request": request, "laptops_list": laptops_with_status, "title": "Laptop Übersicht", "user": user})

@router.get("/dashboard/daily_report/csv", response_class=StreamingResponse)
async def export_daily_report_csv(request: Request, report_date_str: Optional[str] = None, selected_ids: Optional[str] = None, db: Session = Depends(get_db), user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect

    target_date: datetime
    if report_date_str:
        try:
            target_date = datetime.fromisoformat(report_date_str)
            if target_date.tzinfo is None:
                target_date = target_date.replace(tzinfo=timezone.utc)
        except (ValueError, TypeError):
            target_date = datetime.now(timezone.utc)
    else:
        target_date = datetime.now(timezone.utc)
    
    # ... (Rest der CSV-Logik hier einfügen)
    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    
    if selected_ids:
        try:
            id_list = [int(x) for x in selected_ids.split(',')]
            all_laptops_db = [l for l in all_laptops_db if l.id in id_list]
        except ValueError:
            pass # ignore invalid ids
            
    all_laptops_db = sorted(all_laptops_db, key=lambda x: (x.alias_name or "").lower())
    from zoneinfo import ZoneInfo
    berlin_tz = ZoneInfo("Europe/Berlin")

    output = io.StringIO()
    writer = csv.writer(output, delimiter=';')
    writer.writerow(["Alias", "Hostname", "Letzter Scan (Lokalzeit)", "Scan Ergebnis", "Bedrohungen"])
    
    now_utc = datetime.now(timezone.utc)
    
    for laptop in all_laptops_db:
        historical_report = crud.get_latest_scan_report_before(db, laptop.id, target_date)
        
        scan_time_str = "N/A"
        scan_result = "N/A"
        threats_str = "N/A"
        
        if historical_report:
            scan_time_berlin = historical_report.client_scan_time.replace(tzinfo=timezone.utc).astimezone(berlin_tz)
            scan_time_str = scan_time_berlin.strftime('%d.%m.%Y %H:%M:%S')
            
            if historical_report.threats_found is True:
                scan_result = "Fund!"
                threats_str = "Ja"
            else:
                scan_result = historical_report.scan_result_message or "Keine Meldung"
                if len(scan_result) > 50:
                    scan_result = scan_result[:50] + "..."
                threats_str = "Nein"

        writer.writerow([laptop.alias_name, laptop.hostname, scan_time_str, scan_result, threats_str])
        
    output.seek(0)
    
    return StreamingResponse(io.BytesIO(output.getvalue().encode('utf-8-sig')), media_type="text/csv", headers={"Content-Disposition": f"attachment;filename=scanop_tagesbericht_{target_date.isoformat()}.csv"})


@router.get("/dashboard/daily_report", response_class=HTMLResponse)
async def web_daily_report(request: Request, report_date_str: Optional[str] = None, db: Session = Depends(get_db), user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect
        
    target_date: datetime
    report_title: str
    if report_date_str:
        try:
            # Parse datetime string (YYYY-MM-DDThh:mm)
            target_date = datetime.fromisoformat(report_date_str)
            if target_date.tzinfo is None:
                target_date = target_date.replace(tzinfo=timezone.utc)
            report_title = f"Tagesbericht bis {target_date.strftime('%d.%m.%Y %H:%M')}"
        except (ValueError, TypeError):
            target_date = datetime.now(timezone.utc)
            report_title = f"Tagesbericht bis JETZT ({target_date.strftime('%d.%m.%Y %H:%M')}) - Ungültiges Datum angegeben"
    else:
        target_date = datetime.now(timezone.utc)
        report_title = f"Tagesbericht bis {target_date.strftime('%d.%m.%Y %H:%M')}"
    
    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    all_laptops_db = sorted(all_laptops_db, key=lambda x: (x.alias_name or "").lower())
    
    report_data = []
    now_utc = datetime.now(timezone.utc)
    
    for laptop in all_laptops_db:
        # Fetch historical report up to target_date
        historical_report = crud.get_latest_scan_report_before(db, laptop.id, target_date)
        
        # Override laptop properties temporarily with historical data
        if historical_report:
            laptop.last_scan_time = historical_report.client_scan_time
            laptop.last_scan_type = historical_report.scan_type
            laptop.last_scan_result_message = historical_report.scan_result_message
            laptop.last_scan_threats_found = historical_report.threats_found
            laptop.last_scan_duration_minutes = None # We don't have duration in historical reports right now
        else:
            laptop.last_scan_time = None
            laptop.last_scan_type = None
            laptop.last_scan_result_message = None
            laptop.last_scan_threats_found = None
            laptop.last_scan_duration_minutes = None

        status_text, color_class = "N/A", "status-white"
        if laptop.last_scan_time is not None:
            last_scan_time_aware = laptop.last_scan_time.replace(tzinfo=timezone.utc)
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
        
    # Format target_date into ISO string expected by input type="datetime-local"
    # Example: 2026-06-08T14:30
    iso_local_str = target_date.astimezone().strftime('%Y-%m-%dT%H:%M')
    return templates.TemplateResponse("daily_report.html", {"request": request, "report_date_iso": iso_local_str, "report_date_display": target_date.strftime('%d.%m.%Y %H:%M'), "laptops_report_data": report_data, "title": report_title, "user": user})

@router.get("/dashboard/updates", response_class=HTMLResponse)
async def web_client_updates(request: Request, db: Session = Depends(get_db), user: Optional[str] = Depends(get_current_user_or_none)):
    redirect = await check_auth(user)
    if redirect: return redirect
        
    all_laptops_db = crud.get_laptops(db=db, limit=10000)
    all_laptops_db = sorted(all_laptops_db, key=lambda x: (x.alias_name or "").lower())
    
    now_utc = datetime.now(timezone.utc)
    laptops_with_status = []
    
    for laptop in all_laptops_db:
        is_online = False
        status_text = "Offline"
        short_status_text = "Off"
        color_class = "status-red"
        
        if laptop.last_api_contact:
            contact_aware = laptop.last_api_contact.replace(tzinfo=timezone.utc)
            delta = now_utc - contact_aware
            if delta <= timedelta(minutes=5):
                is_online = True
                status_text = "Online"
                short_status_text = "Online"
                color_class = "status-green"
            else:
                mins = int(delta.total_seconds() / 60)
                if mins < 60:
                    status_text = f"Offline ({mins}m)"
                    short_status_text = f"{mins}m"
                elif mins < 1440:
                    status_text = f"Offline ({mins//60}h)"
                    short_status_text = f"{mins//60}h"
                else:
                    status_text = f"Offline ({mins//1440}d)"
                    short_status_text = f"{mins//1440}d"
                
        laptops_with_status.append({
            "db_data": laptop,
            "is_online": is_online,
            "status_text": status_text,
            "short_status_text": short_status_text,
            "color_class": color_class
        })
        
    return templates.TemplateResponse("client_updates.html", {"request": request, "laptops_list": laptops_with_status, "title": "Client Updates", "user": user})