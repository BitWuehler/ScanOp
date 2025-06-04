from fastapi import FastAPI

# Importieren Sie die Router aus Ihren Endpoint-Modulen
from app.api.endpoints import laptops, reports, commands
# from app.database import engine, Base # Nicht mehr unbedingt hier nötig, wenn Alembic verwendet wird
# Base.metadata.create_all(bind=engine) # Nicht mehr nötig, Alembic macht das!

app = FastAPI(
    title="Willkommen zu ScanOp!",
    description="API zur Steuerung und Überwachung von Virenscans auf Client-Laptops.",
    version="0.1.0",
    # docs_url="/docs", # Standard
    # redoc_url="/redoc", # Standard
)

@app.get("/")
async def read_root():
    return {"message": "Willkommen zur Virenscan Management API! Besuchen Sie /docs für die API-Dokumentation."}

@app.get("/api/health")
async def health_check():
    # Hier könnte man später auch eine DB-Verbindung prüfen
    return {"status": "ok", "message": "API ist betriebsbereit."}

# Einbinden der Router
# Der Prefix hier wird dem Prefix im jeweiligen Router vorangestellt
app.include_router(laptops.router, prefix="/api/v1")
app.include_router(reports.router, prefix="/api/v1")
app.include_router(commands.router, prefix="/api/v1")

# Hier könnten später noch Endpunkte für das Webinterface selbst hinzukommen,
# oder das Webinterface wird als separate statische Anwendung bereitgestellt
# und greift nur auf diese API zu.