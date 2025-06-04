from pydantic import BaseModel, Field
from typing import Optional, List # List wird für LaptopResponse verwendet
from datetime import datetime, timezone

# ----- Laptop Schemas -----
class LaptopBase(BaseModel):
    hostname: str
    alias_name: str = Field(min_length=3, max_length=50) # '...' ist nicht nötig, wenn kein Default da ist

class LaptopCreate(LaptopBase):
    pass 

class LaptopUpdate(BaseModel): 
    hostname: Optional[str] = None
    alias_name: Optional[str] = Field(None, min_length=3, max_length=50) # Gut
    pending_command: Optional[str] = None
    command_issue_time: Optional[datetime] = None

class Laptop(LaptopBase): 
    id: int
    first_seen: datetime
    last_api_contact: Optional[datetime] = None
    last_scan_time: Optional[datetime] = None
    last_scan_type: Optional[str] = None
    last_scan_result_message: Optional[str] = None
    last_scan_threats_found: Optional[bool] = None
    pending_command: Optional[str] = None
    command_issue_time: Optional[datetime] = None

    # Pydantic V2 Konfiguration
    model_config = {
        "from_attributes": True
    }

# ----- ScanReport Schemas -----
class ScanReportBase(BaseModel):
    client_scan_time: datetime
    scan_type: str
    scan_result_message: str
    threats_found: bool
    threat_details: Optional[str] = None

class ScanReportCreate(ScanReportBase):
    laptop_identifier: str 

class ScanReport(ScanReportBase): 
    id: int
    laptop_id: int
    report_time_on_server: datetime
    
    # Pydantic V2 Konfiguration
    model_config = {
        "from_attributes": True
    }

# ----- Schemas für spezifische API-Antworten (Optional, aber gut für Klarheit) -----
# Diese können verwendet werden, wenn die Antwortstruktur von den Basis-DB-Leseschemas abweicht
# oder wenn man expliziter sein möchte.

class LaptopResponse(LaptopBase): # Wird verwendet, wenn ein Laptop z.B. mit seinen Reports zurückgegeben wird
    id: int
    first_seen: datetime
    last_api_contact: Optional[datetime] = None
    last_scan_time: Optional[datetime] = None
    last_scan_type: Optional[str] = None
    last_scan_result_message: Optional[str] = None
    last_scan_threats_found: Optional[bool] = None
    pending_command: Optional[str] = None
    command_issue_time: Optional[datetime] = None
    # scan_reports: List[ScanReport] = [] # Einkommentieren, wenn Berichte immer mitgeladen werden sollen

    # Pydantic V2 Konfiguration
    model_config = {
        "from_attributes": True
    }

class ScanReportResponse(ScanReportBase): # Ähnlich wie ScanReport, kann für explizite Antworten dienen
    id: int
    laptop_id: int
    report_time_on_server: datetime
    
    # Pydantic V2 Konfiguration
    model_config = {
        "from_attributes": True
    }


# ----- Client Command Schemas -----
class ClientCommand(BaseModel):
    command: Optional[str] = None
    scan_type: Optional[str] = None

class ClientCommandResponse(ClientCommand): # <--- HIER IST ES!
    # Erbt vorerst alle Felder von ClientCommand.
    # Kann später erweitert werden, falls die Antwort zusätzliche Infos enthalten soll.
    pass

# ----- Client Error Schema -----
class ClientErrorCreate(BaseModel):
    laptop_identifier: str 
    error_message: str
    # default_factory=datetime.utcnow ist ok, aber für timezone-aware:
    # default_factory=lambda: datetime.now(timezone.utc) # Benötigt `from datetime import timezone`
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))