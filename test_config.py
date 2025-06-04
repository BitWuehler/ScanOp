from app.config import settings # Stellen Sie sicher, dass dies nicht unterkringelt ist

print(f"DATABASE_URL aus settings: {settings.database_url}")
if settings.database_url:
    print("Erfolgreich geladen!")
else:
    # Dieser Zweig sollte nicht erreicht werden, wenn .env fehlt,
    # da Pydantic vorher einen Fehler werfen würde.
    print("Fehler beim Laden der DATABASE_URL (sollte nicht passieren, Pydantic Fehler erwartet)!")