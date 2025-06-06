# app/api/endpoints/reports.py
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List
import json 
import pprint 
from pydantic import ValidationError
from datetime import timezone

from app import crud, models, schemas
from app.database import get_db
from app.security import get_api_key

router = APIRouter(
    prefix="/scanreports",
    tags=["Scan Reports"],
    # Die globale Dependency wird entfernt, um den Schutz pro Route zu steuern.
    # dependencies=[Depends(get_api_key)]
)

# =======================================================================================
# Diese Routen sind für die Client-Skripte und benötigen einen API-Schlüssel
# =======================================================================================

@router.post("", response_model=schemas.ScanReport, status_code=status.HTTP_201_CREATED, dependencies=[Depends(get_api_key)])
async def submit_scan_report(
    request: Request, 
    db: Session = Depends(get_db)
):
    try:
        raw_body_bytes = await request.body()
        raw_body_str = raw_body_bytes.decode('utf-8')
        print(f"--- RAW REQUEST BODY (reports.py, Länge: {len(raw_body_bytes)}) ---")
        # print(raw_body_str) # Optional: Bei Bedarf für Debugging einkommentieren
        print(f"--- END RAW REQUEST BODY ---")
        
        parsed_json_data = json.loads(raw_body_str)
        report_payload = schemas.ScanReportCreate(**parsed_json_data)

    except json.JSONDecodeError as e:
        # Detailliertes Logging für JSON-Fehler
        print(f"!!! JSONDecodeError: {e} !!!")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Ungültiges JSON-Format: {e.msg}")
    except ValidationError as e:
        print(f"!!! Pydantic ValidationError: {e} !!!")
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.errors())
    except Exception as e: 
        print(f"!!! Allgemeiner Fehler bei der Body-Verarbeitung: {type(e).__name__} - {e} !!!")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Fehler bei der Verarbeitung der Anfrage.")

    db_laptop_check = crud.get_laptop_by_identifier(db, identifier=report_payload.laptop_identifier)
    if not db_laptop_check:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Laptop mit Kennung '{report_payload.laptop_identifier}' für Report nicht gefunden."
        )
    
    created_report = crud.create_scan_report(db=db, report_payload=report_payload)
    if created_report is None: 
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fehler beim Speichern des Reports für Laptop '{report_payload.laptop_identifier}'."
        )
    return created_report


@router.get("/laptop/{laptop_identifier:path}", response_model=List[schemas.ScanReport], dependencies=[Depends(get_api_key)])
def read_reports_for_laptop(laptop_identifier: str, skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    db_laptop = crud.get_laptop_by_identifier(db, identifier=laptop_identifier)
    if db_laptop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden")
    
    # Pylance wird hier möglicherweise meckern, aber der Code ist zur Laufzeit korrekt.
    # `db_laptop.id` ist ein Integer.
    reports = crud.get_scan_reports_for_laptop(db, laptop_id=db_laptop.id, skip=skip, limit=limit) # type: ignore
    return reports


@router.get("", response_model=List[schemas.ScanReport], dependencies=[Depends(get_api_key)])
def read_all_reports(skip: int = 0, limit: int = 1000, db: Session = Depends(get_db)):
    reports = crud.get_all_scan_reports(db, skip=skip, limit=limit)
    return reports


# =======================================================================================
# Diese Route ist für das Web-Frontend und benötigt KEINEN API-Schlüssel
# =======================================================================================
@router.get("/last_update_timestamp", include_in_schema=False)
async def get_last_report_timestamp(db: Session = Depends(get_db)):
    last_report_time_db = db.query(func.max(models.ScanReport.report_time_on_server)).scalar()
    
    if last_report_time_db is not None:
        # Sicherstellen, dass die Zeit als UTC-aware behandelt wird
        if last_report_time_db.tzinfo is None:
            last_report_time_db = last_report_time_db.replace(tzinfo=timezone.utc)
        else:
            last_report_time_db = last_report_time_db.astimezone(timezone.utc)
        return {"last_update": last_report_time_db.isoformat()}
    return {"last_update": None}