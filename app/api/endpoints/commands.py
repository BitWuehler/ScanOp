# app/api/endpoints/commands.py
from fastapi import APIRouter, Depends, HTTPException, status, Body
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import cast # Für explizites Type-Casting, um Pylance zu helfen

from app import crud, schemas, models 
from app.database import get_db

router = APIRouter(
    prefix="/clientcommands",
    tags=["Client Commands"],
)

@router.get("/{laptop_identifier}", response_model=schemas.ClientCommandResponse)
def get_client_command(laptop_identifier: str, db: Session = Depends(get_db)):
    db_laptop = crud.get_laptop_by_identifier(db, identifier=laptop_identifier)
    if not db_laptop: 
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht registriert oder Kennung unbekannt.")

    crud.update_laptop_contact(db=db, laptop_identifier=laptop_identifier)

    command_to_send = schemas.ClientCommandResponse() # Default ist command=None, scan_type=None
    
    # Pylance-Fehler 1 & 2: `db_laptop.pending_command` wird als Column[str] gesehen
    # Wir wissen, dass es zur Laufzeit str | None ist.
    pending_command_val: str | None = db_laptop.pending_command # type: ignore[assignment]
    pending_scan_type_val: str | None = db_laptop.pending_scan_type # type: ignore[assignment]

    if pending_command_val is not None: 
        command_to_send.command = pending_command_val
        # Pylance-Fehler 3: `db_laptop.pending_scan_type` wird als Column[str] gesehen
        if pending_scan_type_val:
            command_to_send.scan_type = pending_scan_type_val
            
    return command_to_send


class TriggerScanPayload(BaseModel):
    scan_type: str = "FullScan"

@router.post("/trigger_scan/{laptop_identifier_or_all}", status_code=status.HTTP_202_ACCEPTED)
def trigger_scan_for_client(
    laptop_identifier_or_all: str,
    payload: TriggerScanPayload = Body(default_factory=TriggerScanPayload),
    db: Session = Depends(get_db)
):
    command_to_set = "START_SCAN"
    scan_type_to_set = payload.scan_type

    if laptop_identifier_or_all.lower() == "all":
        laptops_to_update: list[models.Laptop] = crud.get_laptops(db, limit=10000)
        if not laptops_to_update:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Keine Laptops zum Triggern gefunden.")
        count = 0
        for laptop_item in laptops_to_update:
            # Pylance-Fehler 4: laptop_item.alias_name wird als Column[str] gesehen
            # Wir wissen, dass es ein str ist.
            crud.update_laptop_command(
                db=db,
                laptop_identifier=cast(str, laptop_item.alias_name), # Explizites Casting oder type: ignore
                command=command_to_set,
                scan_type=scan_type_to_set
            )
            count += 1
        return {"message": f"Scan-Befehl '{command_to_set}' (Typ: {scan_type_to_set}) für {count} Laptops gesetzt."}
    else:
        updated_laptop = crud.update_laptop_command(
            db=db,
            laptop_identifier=laptop_identifier_or_all, # Hier ist laptop_identifier_or_all schon str
            command=command_to_set,
            scan_type=scan_type_to_set
        )
        if not updated_laptop:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden.")
        return {"message": f"Scan-Befehl '{command_to_set}' (Typ: {scan_type_to_set}) für Laptop '{laptop_identifier_or_all}' gesetzt."}


@router.post("/cancel_command/{laptop_identifier_or_all}", status_code=status.HTTP_200_OK)
def cancel_pending_command(
    laptop_identifier_or_all: str,
    db: Session = Depends(get_db)
):
    """Bricht den ausstehenden Befehl für einen oder alle Laptops ab."""
    if laptop_identifier_or_all.lower() == "all":
        laptops_to_cancel: list[models.Laptop] = crud.get_laptops(db, limit=10000)
        if not laptops_to_cancel:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Keine Laptops gefunden, um Befehle abzubrechen.")
        count = 0
        for laptop_item in laptops_to_cancel:
            # Pylance-Fehler 5: laptop_item.alias_name wird als Column[str] gesehen
            crud.update_laptop_command(
                db=db, 
                laptop_identifier=cast(str, laptop_item.alias_name), # Explizites Casting oder type: ignore
                command=None, 
                scan_type=None
            )
            count += 1
        return {"message": f"Ausstehende Befehle für {count} Laptops abgebrochen/gelöscht."}
    else:
        updated_laptop = crud.update_laptop_command(
            db=db, 
            laptop_identifier=laptop_identifier_or_all, 
            command=None, 
            scan_type=None
        )
        if not updated_laptop:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden.")
        return {"message": f"Ausstehender Befehl für Laptop '{laptop_identifier_or_all}' abgebrochen/gelöscht."}