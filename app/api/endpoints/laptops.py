from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app import crud, models, schemas
from app.database import get_db # Unsere Dependency für die DB-Session

router = APIRouter(
    prefix="/laptops",
    tags=["Laptops"], # Für die API-Dokumentation
)

# API-Key Abhängigkeit (vereinfacht für den Anfang)
# In einer echten Anwendung sollte dies sicherer sein und der Key nicht hardcoded werden.
# Wir definieren hier noch keinen API Key, fügen ihn aber später hinzu.
# Fürs Erste lassen wir die Endpunkte ohne expliziten API-Key-Schutz,
# um die grundlegende Funktionalität zu testen.

@router.post("/", response_model=schemas.Laptop, status_code=status.HTTP_201_CREATED)
def create_new_laptop(laptop: schemas.LaptopCreate, db: Session = Depends(get_db)):
    # Prüfen, ob Hostname oder Alias bereits existieren
    db_laptop_hostname = crud.get_laptop_by_hostname(db, hostname=laptop.hostname)
    if db_laptop_hostname:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Laptop mit Hostname '{laptop.hostname}' existiert bereits.")
    db_laptop_alias = crud.get_laptop_by_alias(db, alias_name=laptop.alias_name)
    if db_laptop_alias:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Laptop mit Alias '{laptop.alias_name}' existiert bereits.")
    
    return crud.create_laptop(db=db, laptop=laptop)

@router.get("/", response_model=List[schemas.Laptop])
def read_laptops_list(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    laptops = crud.get_laptops(db, skip=skip, limit=limit)
    return laptops

@router.get("/{laptop_identifier}", response_model=schemas.Laptop)
def read_laptop_details(laptop_identifier: str, db: Session = Depends(get_db)):
    db_laptop = crud.get_laptop_by_identifier(db, identifier=laptop_identifier)
    if db_laptop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden")
    return db_laptop

# Weitere Endpunkte für Update und Delete könnten hier folgen,
# sind aber für die Client-Kommunikation vielleicht nicht primär nötig.
# Ein Update-Endpunkt für den Admin (z.B. Alias ändern) wäre aber sinnvoll für das Webinterface.