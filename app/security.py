# app/security.py
from fastapi import Security, Depends, HTTPException, status
from fastapi.security import APIKeyHeader
import secrets

from app.config import settings

# Definiert, in welchem Header wir den API-Schlüssel erwarten.
# "X-API-Key" ist eine gängige Konvention.
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def get_api_key(api_key_header: str = Security(api_key_header)):
    """
    Dependency, die prüft, ob der übergebene API-Schlüssel mit dem
    auf dem Server konfigurierten Schlüssel übereinstimmt.
    """
    if not api_key_header:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="API Key fehlt im Header"
        )
    
    # `secrets.compare_digest` ist die sichere Methode, um Strings zu vergleichen,
    # da sie gegen Timing-Angriffe schützt.
    if secrets.compare_digest(api_key_header, settings.server_api_key):
        return api_key_header # Erfolg, gebe den Schlüssel zurück
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Ungültiger API Key"
        )