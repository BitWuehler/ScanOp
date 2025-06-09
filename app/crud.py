# app/crud.py
from sqlalchemy.orm import Session
from sqlalchemy import or_
from datetime import datetime, timezone
from typing import Union, List # WICHTIG: Union und List importieren

from . import models
from . import schemas

# === Laptop CRUD Funktionen ===

# KORREKTUR: `models.Laptop | None` wird zu `Union[models.Laptop, None]`
def get_laptop_by_id(db: Session, laptop_id: int) -> Union[models.Laptop, None]:
    return db.query(models.Laptop).filter(models.Laptop.id == laptop_id).first()

def get_laptop_by_hostname(db: Session, hostname: str) -> Union[models.Laptop, None]:
    return db.query(models.Laptop).filter(models.Laptop.hostname == hostname).first()

def get_laptop_by_alias(db: Session, alias_name: str) -> Union[models.Laptop, None]:
    return db.query(models.Laptop).filter(models.Laptop.alias_name == alias_name).first()

def get_laptop_by_identifier(db: Session, identifier: str) -> Union[models.Laptop, None]:
    """Sucht einen Laptop anhand von Hostname ODER Alias."""
    return db.query(models.Laptop).filter(
        or_(models.Laptop.hostname == identifier, models.Laptop.alias_name == identifier)
    ).first()

def get_laptops(db: Session, skip: int = 0, limit: int = 100) -> List[models.Laptop]:
    return db.query(models.Laptop).offset(skip).limit(limit).all()

def create_laptop(db: Session, laptop: schemas.LaptopCreate) -> models.Laptop:
    db_laptop = models.Laptop(
        hostname=laptop.hostname,
        alias_name=laptop.alias_name,
    )
    db.add(db_laptop)
    db.commit()
    db.refresh(db_laptop)
    return db_laptop

def delete_laptop_by_identifier(db: Session, laptop_identifier: str) -> Union[models.Laptop, None]:
    """Löscht einen Laptop anhand seines Identifiers (Hostname oder Alias)."""
    db_laptop = get_laptop_by_identifier(db, identifier=laptop_identifier)
    if db_laptop:
        db.delete(db_laptop)
        db.commit()
    return db_laptop


def update_laptop_contact(db: Session, laptop_identifier: str) -> Union[models.Laptop, None]:
    db_laptop = get_laptop_by_identifier(db=db, identifier=laptop_identifier)
    if db_laptop:
        db_laptop.last_api_contact = datetime.now(timezone.utc)
        db.commit()
        db.refresh(db_laptop)
    return db_laptop

def update_laptop_command(db: Session, laptop_identifier: str, command: Union[str, None], scan_type: Union[str, None] = None) -> Union[models.Laptop, None]:
    db_laptop = get_laptop_by_identifier(db=db, identifier=laptop_identifier)
    if db_laptop:
        db_laptop.pending_command = command
        if command: 
            db_laptop.command_issue_time = datetime.now(timezone.utc)
            db_laptop.pending_scan_type = scan_type
        else:
            db_laptop.command_issue_time = None
            db_laptop.pending_scan_type = None
        db.commit()
        db.refresh(db_laptop)
    return db_laptop

def clear_laptop_command(db: Session, laptop_identifier: str) -> Union[models.Laptop, None]:
    """Löscht einen pending_command und pending_scan_type von einem Laptop."""
    return update_laptop_command(db=db, laptop_identifier=laptop_identifier, command=None, scan_type=None)


# === ScanReport CRUD Funktionen ===

def create_scan_report(db: Session, report_payload: schemas.ScanReportCreate) -> Union[models.ScanReport, None]:
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
    )
    db.add(db_report)
    
    db_laptop.last_scan_time = report_payload.client_scan_time
    db_laptop.last_scan_type = report_payload.scan_type
    db_laptop.last_scan_result_message = report_payload.scan_result_message
    db_laptop.last_scan_threats_found = report_payload.threats_found
    
    db_laptop.last_api_contact = datetime.now(timezone.utc)
    db_laptop.pending_command = None
    db_laptop.command_issue_time = None

    db.commit()
    db.refresh(db_report)
    db.refresh(db_laptop) 
    return db_report

def get_scan_reports_for_laptop(db: Session, laptop_id: int, skip: int = 0, limit: int = 100) -> List[models.ScanReport]:
    return db.query(models.ScanReport).filter(models.ScanReport.laptop_id == laptop_id).order_by(models.ScanReport.client_scan_time.desc()).offset(skip).limit(limit).all()

def get_all_scan_reports(db: Session, skip: int = 0, limit: int = 1000) -> List[models.ScanReport]:
    return db.query(models.ScanReport).order_by(models.ScanReport.report_time_on_server.desc()).offset(skip).limit(limit).all()