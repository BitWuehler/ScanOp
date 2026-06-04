import bcrypt
import getpass
import secrets

print("--- ScanOp Setup: Generierung aller Zugangsdaten ---")
password = getpass.getpass("Bitte geben Sie das gewünschte Passwort für das Web-Dashboard ein: ")

if not password:
    print("Fehler: Passwort darf nicht leer sein.")
    exit(1)

# 1. Passwort mit bcrypt hashen
salt = bcrypt.gensalt()
hashed_password_str = bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

# 2. Secret Key generieren (für sichere Browser-Sessions)
secret_key = secrets.token_hex(32)

# 3. API Key generieren (für die Kommunikation der Laptops)
api_key = secrets.token_hex(32)

print("\nAlle Schlüssel erfolgreich generiert!")
print("Kopieren Sie den folgenden Block komplett und ersetzen Sie damit den 'environment:'-Bereich in Ihrer docker-compose.yml:\n")
print("-" * 60)
print("    environment:")
print(f"      - SECRET_KEY={secret_key}")
print(f"      - APP_PASSWORD={hashed_password_str}")
print(f"      - SERVER_API_KEY={api_key}")
print("-" * 60)
print("\nWICHTIG: Bewahren Sie den SERVER_API_KEY gut auf! Sie benötigen ihn bei der Installation der Laptops.")