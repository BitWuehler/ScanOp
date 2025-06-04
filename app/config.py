from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

# Basisverzeichnis des Projekts bestimmen (ScanOp)
# Path(__file__) ist der Pfad zur aktuellen Datei (config.py)
# .parent ist der 'app'-Ordner
# .parent.parent ist der 'ScanOp'-Ordner (das Projekt-Root)
PROJECT_ROOT = Path(__file__).parent.parent
DOTENV_PATH = PROJECT_ROOT / ".env"

class Settings(BaseSettings):
    database_url: str  # Pydantic wird einen Fehler werfen, wenn dies nicht aus .env geladen werden kann
    # secret_key: str # Falls Sie später einen Secret Key benötigen

    model_config = SettingsConfigDict(
        env_file=DOTENV_PATH,  # Expliziter Pfad zur .env Datei
        env_file_encoding='utf-8', # Gute Praxis, die Kodierung anzugeben
        extra="ignore"
    )

settings = Settings()  # type: ignore[call-arg]

# Testausgabe (kann später entfernt oder auskommentiert werden)
# print(f"DEBUG: In config.py - DOTENV_PATH: {DOTENV_PATH}")
# print(f"DEBUG: In config.py - DATABASE_URL aus settings: {settings.database_url if hasattr(settings, 'database_url') else 'NICHT GELADEN'}")