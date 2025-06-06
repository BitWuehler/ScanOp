# app/auth.py
from fastapi import Request
from passlib.context import CryptContext
from typing import Optional

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def get_current_user_or_none(request: Request) -> Optional[str]:
    """Gibt den User aus der Session zurück oder None, wenn nicht vorhanden."""
    return request.session.get('user')