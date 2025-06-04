from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List

from app import crud, models, schemas # models wird hier nicht direkt verwendet, könnte entfernt werden
from app.database import get_db

router = APIRouter(
    prefix="/scanreports",
    tags=["Scan Reports"], # Gut für die API-Doku
)

@router.post("/", response_model=schemas.ScanReport, status_code=status.HTTP_201_CREATED)
def submit_scan_report(
    report_payload: schemas.ScanReportCreate, # Korrekt angepasst!
    db: Session = Depends(get_db)
    # TODO: Hier später API-Key-Authentifizierung für den Client hinzufügen
):
    # Die Logik hier ist gut:
    # 1. Prüfen, ob der Laptop existiert (obwohl crud.create_scan_report das auch tut)
    # 2. Kontaktzeit aktualisieren
    # 3. Report erstellen
    # 4. Fehlerbehandlung, falls Report-Erstellung fehlschlägt (z.B. Laptop nicht gefunden)

    # Optional: Man könnte die Existenzprüfung des Laptops hier entfernen,
    # da crud.create_scan_report bereits None zurückgibt, wenn der Laptop nicht existiert,
    # und das wird unten abgefangen. Das würde den Code hier etwas verkürzen.
    # Aber es schadet auch nicht, es hier zu haben, um ggf. die Kontaktzeit nur für bekannte Laptops zu aktualisieren.

    # Prüfung, ob der Laptop überhaupt existiert, bevor update_laptop_contact aufgerufen wird
    db_laptop_check = crud.get_laptop_by_identifier(db, identifier=report_payload.laptop_identifier)
    if not db_laptop_check:
        # Wenn der Laptop nicht existiert, wird create_scan_report auch fehlschlagen.
        # Wir können hier schon einen Fehler auslösen oder es der create_scan_report Logik überlassen.
        # Für Konsistenz mit der unteren Fehlerbehandlung ist es gut, es create_scan_report zu überlassen.
        pass # create_scan_report wird None zurückgeben und den Fehler unten auslösen

    # Nur Kontakt aktualisieren, wenn der Laptop bekannt ist
    if db_laptop_check:
        crud.update_laptop_contact(db=db, laptop_identifier=report_payload.laptop_identifier)
    
    created_report = crud.create_scan_report(db=db, report_payload=report_payload)
    if created_report is None:
        # Dieser Fall tritt ein, wenn der Laptop-Identifier in create_scan_report nicht gefunden wurde.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Laptop mit Kennung '{report_payload.laptop_identifier}' nicht gefunden. Report konnte nicht gespeichert werden."
        )
    return created_report


@router.get("/laptop/{laptop_identifier}", response_model=List[schemas.ScanReport])
def read_reports_for_laptop(laptop_identifier: str, skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    db_laptop = crud.get_laptop_by_identifier(db, identifier=laptop_identifier)
    if db_laptop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden")
    
    # Pylance könnte hier immer noch db_laptop.id fälschlicherweise als Column[int] sehen.
    # Wir wissen, es ist zur Laufzeit ein int.
    reports = crud.get_scan_reports_for_laptop(
        db, 
        laptop_id=db_laptop.id,  # type: ignore[arg-type]
        skip=skip, 
        limit=limit
    )
    return reports

@router.get("/", response_model=List[schemas.ScanReport])
def read_all_reports(skip: int = 0, limit: int = 1000, db: Session = Depends(get_db)):
    reports = crud.get_all_scan_reports(db, skip=skip, limit=limit)
    return reports