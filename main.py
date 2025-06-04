from fastapi import FastAPI

app = FastAPI(
    title="Virenscan Management API | ScanOp",
    description="API zur Steuerung und Überwachung von Virenscans auf Client-Laptops.",
    version="0.1.0",
)

@app.get("/")
async def read_root():
    return {"message": "Willkommen zu ScanOp!"}

@app.get("/api/health")
async def health_check():
    return {"status": "ok"}

# Hier werden später die eigentlichen API-Endpunkte für Scan-Reports, Befehle etc. hinkommen.