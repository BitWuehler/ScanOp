from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, DateTime, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func # Für Default-Zeitstempel

from .database import Base # Importiert Base von unserer database.py

class Laptop(Base):
    __tablename__ = "laptops"

    id = Column(Integer, primary_key=True, index=True)
    hostname = Column(String, unique=True, index=True, nullable=False)
    alias_name = Column(String, unique=True, index=True, nullable=False) # Alias muss auch eindeutig sein
    
    first_seen = Column(DateTime(timezone=True), server_default=func.now())
    last_api_contact = Column(DateTime(timezone=True), onupdate=func.now(), nullable=True) # Zeit des letzten API-Kontakts (Polling oder Report)
    
    last_scan_time = Column(DateTime(timezone=True), nullable=True) # Wann der Scan auf dem Client lief
    last_scan_type = Column(String, nullable=True)
    last_scan_result_message = Column(Text, nullable=True)
    last_scan_threats_found = Column(Boolean, nullable=True)

    pending_command = Column(String, nullable=True) # z.B. "START_FULL_SCAN"
    command_issue_time = Column(DateTime(timezone=True), nullable=True)

    # Beziehung zu ScanReports
    # 'back_populates' muss auf den Namen der Beziehung in ScanReport zeigen
    scan_reports = relationship("ScanReport", back_populates="laptop")


class ScanReport(Base):
    __tablename__ = "scan_reports"

    id = Column(Integer, primary_key=True, index=True)
    laptop_id = Column(Integer, ForeignKey("laptops.id"), nullable=False) # Fremdschlüssel zu laptops.id
    
    report_time_on_server = Column(DateTime(timezone=True), server_default=func.now()) # Wann der Report beim Server ankam
    client_scan_time = Column(DateTime(timezone=True), nullable=False) # Wann der Scan auf dem Client lief
    scan_type = Column(String, nullable=False)
    scan_result_message = Column(Text, nullable=False)
    threats_found = Column(Boolean, default=False, nullable=False)
    
    # Details zu gefundenen Bedrohungen, falls vorhanden (kann JSON als String sein oder eine separate Tabelle)
    threat_details = Column(Text, nullable=True)

    # Beziehung zu Laptop
    # 'back_populates' muss auf den Namen der Beziehung in Laptop zeigen
    laptop = relationship("Laptop", back_populates="scan_reports")