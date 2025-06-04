from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

import os
import sys
from dotenv import load_dotenv

# Pfad zum Hauptverzeichnis des Projekts hinzufügen, damit 'app' importiert werden kann
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PROJECT_DIR)
load_dotenv(os.path.join(PROJECT_DIR, ".env")) # Lädt die .env Datei

# Importieren Sie Ihre App-Einstellungen und die Base für Metadaten
from app.config import settings
from app.database import Base  # Base kommt von database.py

# --- BEGINN WICHTIGER ABSCHNITT FÜR MODELLERKENNUNG ---
# Importieren der Modelle. Der Kommentar soll Pylance signalisieren,
# dass der Import für Seiteneffekte (Registrierung der Modelle) benötigt wird.
import app.models  # noqa: F401 pylint: disable=unused-import
# Alternativ, um sicherzustellen, dass die Klassen gesehen werden:
# from app.models import Laptop, ScanReport # Wenn dies keine zyklischen Imports erzeugt

# --- ENDE WICHTIGER ABSCHNITT ---


# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

config.set_main_option('sqlalchemy.url', settings.database_url)

# add your model's MetaData object here
# for 'autogenerate' support
target_metadata = Base.metadata
# Um zu debuggen, was Alembic sieht (kann nach dem Test entfernt werden):
# print(f"DEBUG Alembic env.py: target_metadata.tables.keys() = {target_metadata.tables.keys()}")


def run_migrations_offline() -> None:
    context.configure(
        url=settings.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()

def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True,
        )
        with context.begin_transaction():
            context.run_migrations()

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()