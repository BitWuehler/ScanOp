# app/api/endpoints/reports.py
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from typing import List
import json 
import pprint 
from pydantic import ValidationError # Import für expliziten Exception-Typ

from app import crud, models, schemas
from app.database import get_db
from app.security import get_api_key

router = APIRouter(
    prefix="/scanreports",
    tags=["Scan Reports"],
    dependencies=[Depends(get_api_key)]
)

@router.post("/", response_model=schemas.ScanReport, status_code=status.HTTP_201_CREATED)
async def submit_scan_report(
    request: Request, 
    db: Session = Depends(get_db)
):
    raw_body_bytes: bytes = b"" # Initialisieren für den Fall eines Fehlers
    raw_body_str: str = ""
    report_payload: schemas.ScanReportCreate | None = None # Initialisieren

    try:
        raw_body_bytes = await request.body()
        raw_body_str = raw_body_bytes.decode('utf-8')
        print(f"--- RAW REQUEST BODY (reports.py, Länge: {len(raw_body_bytes)}) ---")
        print(raw_body_str)
        print(f"--- END RAW REQUEST BODY ---")

        try:
            parsed_json_data = json.loads(raw_body_str)
            # print("--- MANUELL GEPARSTER JSON (pretty) ---")
            # pprint.pprint(parsed_json_data)
            # print("--- ENDE MANUELL GEPARSTER JSON ---")
            
            report_payload = schemas.ScanReportCreate(**parsed_json_data)
            # print("--- Pydantic Validierung erfolgreich ---")

        except json.JSONDecodeError as e:
            print(f"!!! JSONDecodeError beim manuellen Parsen: {e} !!!")
            print(f"Fehler an Position: {e.pos}, Zeile: {e.lineno}, Spalte: {e.colno}")
            context_len = 40
            start = max(0, e.pos - context_len)
            end = min(len(raw_body_str), e.pos + context_len)
            error_context = raw_body_str[start:end].replace('\n', '\\n').replace('\r', '\\r')
            print(f"Kontext des Fehlers: ...{error_context[:context_len]}<-- HIER -->{error_context[context_len:]}...")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"JSONDecodeError: {e.msg} at pos {e.pos}")
        
        except ValidationError as e: # Explizit Pydantic ValidationError fangen
            print(f"!!! Pydantic ValidationError: {e} !!!")
            print("Pydantic Validation Errors:")
            pprint.pprint(e.errors()) # .errors() ist die Methode, um die Fehlerliste zu bekommen
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=e.errors())
            
        except Exception as e: 
            print(f"!!! Fehler bei Pydantic Instanziierung oder anderem: {type(e).__name__} - {e} !!!")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Error processing JSON data: {str(e)}")

    except UnicodeDecodeError as ude:
        print(f"!!! Kritischer Fehler: Konnte Request Body nicht als UTF-8 dekodieren: {ude} !!!")
        # raw_body_bytes ist bereits definiert, wenn wir hier sind
        print(f"Empfangene Bytes (teilweise): {raw_body_bytes[:100]}") 
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Error decoding request body as UTF-8.")
    except Exception as e:
        print(f"!!! Kritischer Fehler beim Lesen des Request Bodys: {type(e).__name__} - {e} !!!")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Error reading or processing request body.")

    # Wenn report_payload hier None ist (z.B. durch einen Fehler oben, der nicht erneut geworfen wurde),
    # müssen wir das abfangen, bevor wir darauf zugreifen.
    if report_payload is None:
        # Dieser Fall sollte eigentlich nicht eintreten, da Exceptions oben geworfen werden.
        print("!!! Kritischer interner Fehler: report_payload ist None nach Body-Verarbeitung !!!")
        raise HTTPException(status_code=500, detail="Internal server error processing report payload.")


    db_laptop_check = crud.get_laptop_by_identifier(db, identifier=report_payload.laptop_identifier)
    if not db_laptop_check:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Laptop mit Kennung '{report_payload.laptop_identifier}' für Report nicht gefunden."
        )

    # update_laptop_contact wird nun in create_scan_report aufgerufen, um Konsistenz zu wahren
    # und es nur bei erfolgreicher Reporterstellung zu tun.
    # if db_laptop_check:
    #     crud.update_laptop_contact(db=db, laptop_identifier=report_payload.laptop_identifier)
    
    created_report = crud.create_scan_report(db=db, report_payload=report_payload)
    if created_report is None: 
        # Dieser Fall sollte seltener werden, da crud.create_scan_report den Laptop-Check macht.
        # Aber es ist eine gute Absicherung.
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, # Oder 404, je nach genauer Ursache
            detail=f"Fehler beim Speichern des Reports für Laptop '{report_payload.laptop_identifier}'."
        )
    return created_report


@router.get("/laptop/{laptop_identifier}", response_model=List[schemas.ScanReport])
def read_reports_for_laptop(laptop_identifier: str, skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    db_laptop = crud.get_laptop_by_identifier(db, identifier=laptop_identifier)
    if db_laptop is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Laptop nicht gefunden")
    
    reports = crud.get_scan_reports_for_laptop(
        db, 
        laptop_id=db_laptop.id,  # type: ignore[arg-type] # Pylance versteht den Laufzeittyp hier nicht immer
        skip=skip, 
        limit=limit
    )
    return reports

@router.get("/", response_model=List[schemas.ScanReport])
def read_all_reports(skip: int = 0, limit: int = 1000, db: Session = Depends(get_db)):
    reports = crud.get_all_scan_reports(db, skip=skip, limit=limit)
    return reports