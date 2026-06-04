# app/auth.py
from fastapi import Request
import bcrypt
from typing import Optional

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception:
        return False

def get_current_user_or_none(request: Request) -> Optional[str]:
    """Gibt den User aus der Session zurück oder None, wenn nicht vorhanden."""
    return request.session.get('user')