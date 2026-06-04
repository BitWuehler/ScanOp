import getpass
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

print("--- ScanOp Passwort Hash Generator ---")
password = getpass.getpass("Bitte geben Sie das gewünschte Passwort für das Web-Dashboard ein: ")

if not password:
    print("Fehler: Passwort darf nicht leer sein.")
    exit(1)

hashed_password = pwd_context.hash(password)

print("\nPasswort-Hash erfolgreich erstellt!")
print("Fügen Sie diesen kompletten String in Ihre docker-compose.yml (oder .env) als APP_PASSWORD ein:\n")
print(f"APP_PASSWORD={hashed_password}\n")