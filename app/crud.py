from sqlalchemy.orm import Session
from sqlalchemy import or_ # Für ODER-Bedingungen in Abfragen
from datetime import datetime, timezone # timezone importieren für tz-aware datetime

from . import models
from . import schemas

# === Laptop CRUD Funktionen ===

def get_laptop_by_id(db: Session, laptop_id: int) -> models.Laptop | None:
    return db.query(models.Laptop).filter(models.Laptop.id == laptop_id).first()

def get_laptop_by_hostname(db: Session, hostname: str) -> models.Laptop | None:
    return db.query(models.Laptop).filter(models.Laptop.hostname == hostname).first()

def get_laptop_by_alias(db: Session, alias_name: str) -> models.Laptop | None:
    return db.query(models.Laptop).filter(models.Laptop.alias_name == alias_name).first()

def get_laptop_by_identifier(db: Session, identifier: str) -> models.Laptop | None:
    """Sucht einen Laptop anhand von Hostname ODER Alias."""
    return db.query(models.Laptop).filter(
        or_(models.Laptop.hostname == identifier, models.Laptop.alias_name == identifier)
    ).first()

def get_laptops(db: Session, skip: int = 0, limit: int = 100) -> list[models.Laptop]:
    return db.query(models.Laptop).offset(skip).limit(limit).all()

def create_laptop(db: Session, laptop: schemas.LaptopCreate) -> models.Laptop:
    now_utc = datetime.now(timezone.utc) # Explizit UTC
    db_laptop = models.Laptop(
        hostname=laptop.hostname,
        alias_name=laptop.alias_name,
        first_seen=now_utc,        # Setzt UTC
        last_api_contact=now_utc   # Setzt UTC (initial)
    )
    db.add(db_laptop)
    db.commit()
    db.refresh(db_laptop)
    return db_laptop

def update_laptop_contact(db: Session, laptop_identifier: str) -> models.Laptop | None:
    db_laptop = get_laptop_by_identifier(db=db, identifier=laptop_identifier)
    if db_laptop:
        db_laptop.last_api_contact = datetime.now(timezone.utc)  # type: ignore[assignment] # Explizit UTC
        db.commit()
        db.refresh(db_laptop)
    return db_laptop

def update_laptop_command(db: Session, laptop_identifier: str, command: str | None, scan_type: str | None = None) -> models.Laptop | None:
    db_laptop = get_laptop_by_identifier(db=db, identifier=laptop_identifier)
    if db_laptop:
        db_laptop.pending_command = command             # type: ignore[assignment]
        if command: 
            db_laptop.command_issue_time = datetime.now(timezone.utc) # type: ignore[assignment]
            db_laptop.pending_scan_type = scan_type     # type: ignore[assignment] # HIER speichern wir den scan_type
        else: # Befehl wird gelöscht
            db_laptop.command_issue_time = None         # type: ignore[assignment]
            db_laptop.pending_scan_type = None          # type: ignore[assignment] # Auch den scan_type löschen
        db.commit()
        db.refresh(db_laptop)
    return db_laptop

def clear_laptop_command(db: Session, laptop_identifier: str) -> models.Laptop | None:
    """Löscht einen pending_command von einem Laptop."""
    return update_laptop_command(db=db, laptop_identifier=laptop_identifier, command=None)


# === ScanReport CRUD Funktionen ===

def create_scan_report(db: Session, report_payload: schemas.ScanReportCreate) -> models.ScanReport | None:
    """
    Erstellt einen neuen Scan-Bericht für einen Laptop.
    Der Laptop wird anhand des laptop_identifier (Hostname oder Alias) gesucht.
    """
    db_laptop = get_laptop_by_identifier(db=db, identifier=report_payload.laptop_identifier)
    if not db_laptop:
        return None 

    db_report = models.ScanReport(
        laptop_id=db_laptop.id,
        client_scan_time=report_payload.client_scan_time,
        scan_type=report_payload.scan_type,
        scan_result_message=report_payload.scan_result_message,
        threats_found=report_payload.threats_found,
        threat_details=report_payload.threat_details
        # report_time_on_server wird durch server_default in models.py gesetzt
    )
    db.add(db_report)
    
    # Aktualisiere den Laptop-Status mit den neuesten Scan-Informationen
    db_laptop.last_scan_time = report_payload.client_scan_time         # Korrigiert (war vorher schon richtig) # type: ignore[assignment]
    db_laptop.last_scan_type = report_payload.scan_type            # Korrigiert (war vorher schon richtig) # type: ignore[assignment]
    db_laptop.last_scan_result_message = report_payload.scan_result_message # *** HIER WAR DER FEHLER: report_data zu report_payload geändert *** # type: ignore[assignment]
    db_laptop.last_scan_threats_found = report_payload.threats_found      # *** HIER WAR DER FEHLER: report_data zu report_payload geändert *** # type: ignore[assignment]
    
    db_laptop.last_api_contact = datetime.now(timezone.utc)      # type: ignore[assignment]
    db_laptop.pending_command = None                             # type: ignore[assignment]
    db_laptop.command_issue_time = None                          # type: ignore[assignment]

    db.commit()
    db.refresh(db_report)
    db.refresh(db_laptop) 
    return db_report

def get_scan_reports_for_laptop(db: Session, laptop_id: int, skip: int = 0, limit: int = 100) -> list[models.ScanReport]:
    return db.query(models.ScanReport).filter(models.ScanReport.laptop_id == laptop_id).order_by(models.ScanReport.client_scan_time.desc()).offset(skip).limit(limit).all()

def get_all_scan_reports(db: Session, skip: int = 0, limit: int = 1000) -> list[models.ScanReport]:
    return db.query(models.ScanReport).order_by(models.ScanReport.report_time_on_server.desc()).offset(skip).limit(limit).all()


# === Client Error CRUD (optional, aber nützlich) ===
# (Keine Änderungen hier)


# === Client Error CRUD (optional, aber nützlich) ===

# Wir erstellen hier kein eigenes Modell für Client-Fehler, sondern loggen sie einfach.
# Für eine komplexere Fehlerbehandlung könnte man ein ClientError-Modell und CRUD-Funktionen erstellen.
# Fürs Erste reicht es, wenn die API-Endpunkte die Fehler entgegennehmen und z.B. loggen.
# Hier könnte aber eine Funktion stehen, um Fehler in einer separaten Tabelle zu speichern:
# def create_client_error(db: Session, error_data: schemas.ClientErrorCreate, laptop_id: int):
#     pass