# app/api/endpoints/laptops.py
from fastapi import APIRouter, Depends, HTTPException, status, Response
from sqlalchemy.orm import Session
from typing import List

from app import crud, models, schemas
from app.database import get_db
# NEU: Wir importieren BEIDE Sicherheitsmechanismen
from app.security import get_api_key
from app.auth import get_current_user_or_none

router = APIRouter(
    prefix="/laptops",
    tags=["Laptops"],
    # Die globale Dependency wird entfernt, um eine granulare Steuerung pro Route zu ermöglichen.
    # dependencies=[Depends(get_api_key)] # ENTFERNT
)

# =======================================================================================
# Diese Route ist für das Installations-Skript -> Benötigt API-Schlüssel
# =======================================================================================
@router.post("", response_model=schemas.Laptop, status_code=status.HTTP_201_CREATED, dependencies=[Depends(get_api_key)])
def create_new_laptop(laptop: schemas.LaptopCreate, db: Session = Depends(get_db)):
    db_laptop_hostname = crud.get_laptop_by_hostname(db, hostname=laptop.hostname)
    if db_laptop_hostname:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Laptop mit Hostname '{laptop.hostname}' existiert bereits.")
    db_laptop_alias = crud.get_laptop_by_alias(db, alias_name=laptop.alias_name)
    if db_laptop_alias:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Laptop mit Alias '{laptop.alias_name}' existiert bereits.")
    
    return crud.create_laptop(db=db, laptop=laptop)


# =======================================================================================
# Diese Route wird aktuell nicht vom Frontend genutzt, aber wir schützen sie für zukünftige Admin-Tools
# mit dem API-Schlüssel.
# =======================================================================================
@router.get("", response_model=List[schemas.Laptop], dependencies=[Depends(get_api_key)])
def read_laptops_list(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    laptops = crud.get_laptops(db, skip=skip, limit=limit)
    return laptops


# =======================================================================================
# Diese Route ist für das Installations-Skript (Prüfung) -> Benötigt API-Schlüssel
# =======================================================================================
@router.get("/{laptop_identifier:path}", response_model=schemas.Laptop, dependencies=[Depends(get_api_key)])
def read_laptop_details(laptop_identifier: str, db: Session = Depends(get_db)):
    db_laptop = crud.get_laptop_by_identifier(db, identifier=laptop_identifier)
    if db_laptop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden")
    return db_laptop


# =======================================================================================
# DIESE ROUTE IST FÜR DAS WEBINTERFACE -> Benötigt Login-Session
# =======================================================================================
@router.delete("/{laptop_identifier:path}", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(get_current_user_or_none)])
def delete_laptop(laptop_identifier: str, db: Session = Depends(get_db)):
    """Löscht einen Laptop und alle zugehörigen Scan-Berichte."""
    deleted_laptop = crud.delete_laptop_by_identifier(db=db, laptop_identifier=laptop_identifier)
    if deleted_laptop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden")
    return Response(status_code=status.HTTP_204_NO_CONTENT)