from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from .config import settings # Importiert unsere Konfiguration

SQLALCHEMY_DATABASE_URL = settings.database_url

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    # connect_args ist nur für SQLite nötig, um Threading-Probleme zu vermeiden
    connect_args={"check_same_thread": False}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

# Dependency für FastAPI, um eine DB-Session pro Request zu erhalten
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()