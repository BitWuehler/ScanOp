from fastapi import APIRouter, Depends, HTTPException, status, Body
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app import crud, schemas
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

    command_to_send = schemas.ClientCommandResponse()
    
    if db_laptop.pending_command is not None: 
        command_to_send.command = db_laptop.pending_command  # type: ignore[assignment]
        # Den gespeicherten pending_scan_type aus dem Laptop-Modell holen
        if db_laptop.pending_scan_type: # Prüfen, ob ein Wert vorhanden ist # type: ignore[assignment]
            command_to_send.scan_type = db_laptop.pending_scan_type # type: ignore[assignment]
            
    return command_to_send

class TriggerScanPayload(BaseModel):
    scan_type: str = "FullScan"

@router.post("/trigger_scan/{laptop_identifier_or_all}", status_code=status.HTTP_202_ACCEPTED)
def trigger_scan_for_client(
    laptop_identifier_or_all: str, # Dieser Parameter ist ein str
    payload: TriggerScanPayload = Body(TriggerScanPayload()),
    db: Session = Depends(get_db)
):
    command_to_set = "START_SCAN"
    scan_type_to_set = payload.scan_type

    if laptop_identifier_or_all.lower() == "all":
        laptops = crud.get_laptops(db, limit=10000)
        if not laptops:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Keine Laptops zum Triggern gefunden.")
        count = 0
        for laptop_item in laptops:
            crud.update_laptop_command(
                db=db,
                laptop_identifier=laptop_item.alias_name, # laptop_item.alias_name ist hier der problematische Punkt für Pylance # type: ignore[arg-type] 
                command=command_to_set,
                scan_type=scan_type_to_set
            )  # type: ignore[arg-type] # Für Pylance-Fehler bei laptop_item.alias_name
            count += 1
        return {"message": f"Scan-Befehl '{command_to_set}' (Typ: {scan_type_to_set}) für {count} Laptops gesetzt."}
    else:
        # laptop_identifier_or_all ist hier definitiv ein str aus dem Pfadparameter
        updated_laptop = crud.update_laptop_command(
            db=db,
            laptop_identifier=laptop_identifier_or_all, # Pylance meldet hier fälschlicherweise ein Problem
            command=command_to_set,
            scan_type=scan_type_to_set
        ) # type: ignore[arg-type] # Hinzugefügt, um Pylance zu beruhigen
        if not updated_laptop:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden.")
        return {"message": f"Scan-Befehl '{command_to_set}' (Typ: {scan_type_to_set}) für Laptop '{laptop_identifier_or_all}' gesetzt."}