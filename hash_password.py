import bcrypt
import getpass

print("--- ScanOp Passwort Hash Generator ---")
password = getpass.getpass("Bitte geben Sie das gewünschte Passwort für das Web-Dashboard ein: ")

if not password:
    print("Fehler: Passwort darf nicht leer sein.")
    exit(1)

# Passwort mit bcrypt hashen
salt = bcrypt.gensalt()
hashed_password = bcrypt.hashpw(password.encode('utf-8'), salt)

# Ausgabe als lesbarer String
hashed_password_str = hashed_password.decode('utf-8')

print("\nPasswort-Hash erfolgreich erstellt!")
print("Fügen Sie diesen kompletten String in Ihre docker-compose.yml (oder .env) als APP_PASSWORD ein:\n")
print(f"APP_PASSWORD={hashed_password_str}\n")