@echo off
REM Dieses Skript startet den PowerShell-Installer mit Administratorrechten.

:: Prüfen, ob bereits Administratorrechte vorhanden sind
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Fordere Administratorrechte an...
    goto UACPrompt
) else (
    goto gotAdmin
)

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%~dp0"
    
    echo Administratorrechte vorhanden. Starte den PowerShell-Installer...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1"
    
    pause
    popd
```Dieses CMD-Skript nutzt einen Standard-Trick, um sich selbst mit Administratorrechten neu zu starten und ruft dann unser `install.ps1`-Skript mit der `-ExecutionPolicy Bypass`-Flag auf. Der Benutzer muss jetzt nur noch `start_installer.cmd` doppelklicken und die UAC-Abfrage bestätigen.

---

### Schritt 2: `install.ps1` finalisieren

Wir passen die Texte an, um den Update-Prozess zu verdeutlichen, und stellen sicher, dass der geplante Task die Execution Policy umgeht.

**Ersetzen Sie den Inhalt Ihrer `install.ps1`-Datei vollständig mit diesem finalen Code:**
```powershell
<#
.SYNOPSIS
    Installations- und Update-Skript für den ScanOp Client.
.DESCRIPTION
    Dieses Skript installiert oder aktualisiert den ScanOp Client. Es kann eine optionale,
    vorbefüllte 'client_config.json' verwenden. Fehlende Werte werden interaktiv
    abgefragt. BENÖTIGT ADMINISTRATORBERECHTIGUNGEN.
#>

# Block A: Preamble und Administrator-Prüfung
# ====================================================================
# Die Administrator-Prüfung wird jetzt primär durch start_installer.cmd gehandhabt,
# aber wir behalten sie als Sicherheitsnetz bei.
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Fehler: Administratorrechte sind erforderlich."
    Read-Host "Bitte führen Sie das Skript über die 'start_installer.cmd'-Datei aus. Drücken Sie Enter zum Schließen."
    exit 1
}

$InstallerBaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = "C:\Program Files\ScanOpClient"
$ClientScriptSourcePath = Join-Path -Path $InstallerBaseDir -ChildPath "ScanOpClient.ps1"
$PreconfigPath = Join-Path -Path $InstallerBaseDir -ChildPath "client_config.json"
$ClientScriptDestPath = Join-Path -Path $InstallDir -ChildPath "ScanOpClient.ps1"
$ConfigDestPath = Join-Path -Path $InstallDir -ChildPath "client_config.json"
$taskName = "ScanOpClientService"

# Prüfen, ob eine bestehende Installation vorhanden ist (für die Textausgaben)
$isUpdate = Test-Path -Path $InstallDir

Clear-Host
Write-Host "======================================" -ForegroundColor Green
if ($isUpdate) {
    Write-Host "     ScanOp Client Updater"
} else {
    Write-Host "     ScanOp Client Installer"
}
Write-Host "======================================" -ForegroundColor Green
Write-Host ""


# Block B: Intelligente Konfiguration und Benutzereingaben
# ====================================================================
Write-Host "Konfiguration wird geladen und geprüft..."
$ServerBaseUrl = $null
$ApiKey = $null

# Nur bei einer Neuinstallation die Konfigurationsdatei prüfen. Bei Updates behalten wir die bestehende bei.
if (-NOT $isUpdate) {
    if (Test-Path $PreconfigPath) {
        Write-Host "-> Vorkonfigurierte 'client_config.json' gefunden." -ForegroundColor Cyan
        try {
            $preconfig = Get-Content -Path $PreconfigPath -Raw | ConvertFrom-Json
            $ServerBaseUrl = $preconfig.ServerBaseUrl
            $ApiKey = $preconfig.ApiKey
        } catch { Write-Warning "Konnte die vorkonfigurierte Datei nicht lesen. Werte werden manuell abgefragt." }
    }
} else {
    Write-Host "-> Bestehende Installation gefunden. Konfiguration wird für das Update beibehalten." -ForegroundColor Cyan
    # Bestehende Konfiguration laden, um sie für die Registrierungsprüfung zu haben (falls nötig)
    if (Test-Path $ConfigDestPath) {
        $existingConfig = Get-Content -Path $ConfigDestPath -Raw | ConvertFrom-Json
        $ServerBaseUrl = $existingConfig.ServerBaseUrl
        $ApiKey = $existingConfig.ApiKey
        $AliasName = $existingConfig.AliasName
    }
}

if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) { $ServerBaseUrl = Read-Host -Prompt "Geben Sie die Basis-URL des ScanOp-Servers ein (z.B. 'http://ihre-server-adresse/api/v1')" } 
else { Write-Host "-> Server-URL: $ServerBaseUrl" }

if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = Read-Host -Prompt "Geben Sie den geheimen API-Schlüssel des Servers ein" } 
else { Write-Host "-> API-Schlüssel wurde geladen." }

if ([string]::IsNullOrWhiteSpace($AliasName)) { $AliasName = Read-Host -Prompt "Geben Sie einen eindeutigen Alias für diesen Computer ein (z.B. 'LAPTOP-MARKETING-05')" }
else { Write-Host "-> Bestehender Alias wird verwendet: $AliasName" }

$Hostname = $env:COMPUTERNAME
Write-Host "-> Automatischer Hostname erkannt: $Hostname"

if ([string]::IsNullOrWhiteSpace($AliasName) -or [string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Error "Alle Felder sind erforderlich. Die Installation/das Update wird abgebrochen."
    Read-Host "Drücken Sie Enter zum Schließen."; exit 1
}
$ServerBaseUrl = $ServerBaseUrl.TrimEnd('/')


# Block C: Konfigurationsdatei erstellen und Installation/Update durchführen
# ====================================================================
if ($isUpdate) {
    Write-Host "`nAktualisiere Installation in '$InstallDir'..." -ForegroundColor Yellow
} else {
    Write-Host "`nVorbereitung der Installation in '$InstallDir'..." -ForegroundColor Yellow
    if (-NOT (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
    Write-Host "-> Installationsverzeichnis erstellt."
}

$finalConfigObject = [PSCustomObject]@{
    AliasName = $AliasName; ServerBaseUrl = $ServerBaseUrl; ApiKey = $ApiKey
    PollingIntervalSeconds = 60; InterimCheckIntervalMinutes = 30
}
$finalConfigObject | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigDestPath -Encoding UTF8 -Force
Write-Host "-> Konfigurationsdatei wurde geschrieben/aktualisiert."

Copy-Item -Path $ClientScriptSourcePath -Destination $ClientScriptDestPath -Force
Write-Host "-> Client-Skript wurde kopiert/aktualisiert."


# Block D: Client beim Server registrieren (nur bei Neuinstallation)
# ====================================================================
if (-NOT $isUpdate) {
    Write-Host "`nRegistriere Client '$AliasName' (Hostname: $Hostname) beim Server..." -ForegroundColor Yellow
    $registrationUrl = "$ServerBaseUrl/laptops/"
    $registrationBody = @{ hostname = $Hostname; alias_name = $AliasName } | ConvertTo-Json
    try {
        $headers = @{ "X-API-Key" = $ApiKey }
        Invoke-RestMethod -Uri $registrationUrl -Method Post -Headers $headers -Body $registrationBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "-> Client erfolgreich beim Server registriert!" -ForegroundColor Green
    } catch {
        $errorMessage = "Fehler bei der Registrierung des Clients."
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $responseBody = $_.Exception.Response.GetResponseStream() | ForEach-Object { (New-Object System.IO.StreamReader($_)).ReadToEnd() }
            $errorMessage += " (HTTP $statusCode): $responseBody"
            if ($statusCode -eq 400) { $errorMessage += "`n-> MÖGLICHE URSACHE: Der Alias oder Hostname existiert bereits auf dem Server." }
        } else { $errorMessage += ": $($_.Exception.Message)" }
        Write-Error $errorMessage; Read-Host "Drücken Sie Enter zum Schließen."; exit 1
    }
}


# Block E: Geplanten Task (als "Dienst") installieren oder aktualisieren
# ====================================================================
Write-Host "`nInstalliere/Aktualisiere Hintergrunddienst (geplanten Task)..." -ForegroundColor Yellow
$taskUser = "NT AUTHORITY\SYSTEM"
# KORREKTUR: -ExecutionPolicy Bypass direkt in den Task-Befehl integrieren
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ClientScriptDestPath`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType ServiceAccount
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

try {
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    Write-Host "-> Alter Task (falls vorhanden) entfernt."
    
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "Führt den ScanOp Client für die Server-Kommunikation im Hintergrund aus." -Force
    Write-Host "-> Hintergrunddienst '$taskName' erfolgreich installiert/aktualisiert."
    Write-Host "-> Der Dienst wird nach dem nächsten Neustart automatisch gestartet."
    
    $startNow = Read-Host "Möchten Sie den Dienst jetzt sofort (neu) starten? (j/n)"
    if ($startNow -eq 'j') {
        # Stoppen, falls er noch von einem alten Update läuft
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $taskName
        Write-Host "-> Dienst '$taskName' wurde gestartet."
    }
} catch {
    Write-Error "Konnte den Hintergrunddienst nicht installieren: $($_.Exception.Message)"; Read-Host "Drücken Sie Enter zum Schließen."; exit 1
}


# Block F: Abschluss
# ====================================================================
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
if ($isUpdate) {
    Write-Host "    Update erfolgreich!"
} else {
    Write-Host "    Installation erfolgreich!"
}
Write-Host "======================================" -ForegroundColor Green
Write-Host "Der ScanOp Client ist nun auf diesem Computer eingerichtet."
Read-Host "Drücken Sie Enter, um das Fenster zu schließen."