# app/config.py
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict

PROJECT_ROOT = Path(__file__).parent.parent
DOTENV_PATH = PROJECT_ROOT / ".env"

class Settings(BaseSettings):
    database_url: str
    secret_key: str
    app_username: str
    app_password: str

    server_api_key: str

    model_config = SettingsConfigDict(
        env_file=DOTENV_PATH,
        env_file_encoding='utf-8',
        extra="ignore"
    )

settings = Settings() # type: ignore[call-arg]