# hash_password.py
from passlib.context import CryptContext

# Diese Datei ist nur ein Hilfsskript und nicht Teil der Hauptanwendung.
# Führen Sie es einmal aus, um einen Hash für Ihr gewünschtes Passwort zu erstellen.

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Geben Sie hier das Passwort ein, das Sie verwenden möchten:
password_to_hash = "U7CWP2Xgr!Xq"

hashed_password = pwd_context.hash(password_to_hash)

print("Passwort-Hash erfolgreich erstellt!")
print("Fügen Sie diesen Hash in Ihre .env-Datei für die Variable APP_PASSWORD ein:")
print(f"APP_PASSWORD={hashed_password}")