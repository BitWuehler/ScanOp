# main.py
from fastapi import FastAPI, Request, Form, status # KORREKTUR: 'status' hier wieder hinzugefügt
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware
from datetime import datetime, timezone

from pathlib import Path
from app.config import settings
from app.auth import verify_password
from app.api.endpoints import laptops, reports, commands
from app.web_routes import router as web_router

# --- App-Konfiguration ---
PROJECT_ROOT_DIR = Path(__file__).resolve().parent
app = FastAPI(title="ScanOp")
app.add_middleware(SessionMiddleware, secret_key=settings.secret_key)
STATIC_FILES_DIR = PROJECT_ROOT_DIR / "static"
TEMPLATES_DIR = PROJECT_ROOT_DIR / "templates"
app.mount("/static", StaticFiles(directory=STATIC_FILES_DIR), name="static")

# WICHTIG: Die `templates` Instanz wird jetzt in den jeweiligen Router-Dateien erstellt.
# Wir behalten die Definition der Hilfsfunktion hier, da sie logisch zu `main` gehört.
def to_utc_iso_string(dt: datetime | None) -> str:
    if dt is None: return ""
    if dt.tzinfo is None: dt_utc = dt.replace(tzinfo=timezone.utc)
    else: dt_utc = dt.astimezone(timezone.utc)
    return dt_utc.isoformat().replace('+00:00', 'Z')

# --- UNGESCHÜTZTE Auth-Routen ---
# Diese bleiben hier, da sie keine komplexen Abhängigkeiten haben.
templates_for_login = Jinja2Templates(directory=TEMPLATES_DIR)
# Wir registrieren die globale Funktion auch für dieses Template-Objekt
templates_for_login.env.globals['to_utc_iso'] = to_utc_iso_string

@app.get("/login", response_class=HTMLResponse)
async def login_form(request: Request):
    return templates_for_login.TemplateResponse("login.html", {"request": request})

@app.post("/login", response_class=HTMLResponse)
async def login_submit(request: Request, username: str = Form(...), password: str = Form(...)):
    if username == settings.app_username and verify_password(password, settings.app_password):
        request.session['user'] = username
        return RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)
    return templates_for_login.TemplateResponse("login.html", {"request": request, "error": "Falscher Benutzername oder Passwort"})

@app.get("/logout")
async def logout(request: Request):
    request.session.clear()
    return RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)

# --- Einbinden der Router ---
# API Endpunkte (BLEIBEN UNGESCHÜTZT FÜR DIE CLIENTS)
app.include_router(laptops.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(commands.router, prefix="/api/v1")
# Geschützte Web-Seiten
app.include_router(web_router)