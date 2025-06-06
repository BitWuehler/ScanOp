<#
.SYNOPSIS
    Intelligentes Installations- und Update-Skript für den ScanOp Client.
.DESCRIPTION
    Dieses Skript installiert oder aktualisiert den ScanOp Client. Es erkennt
    eine bestehende Installation, fragt nach, ob der Alias geändert werden soll,
    und prüft, ob der Client bereits am Server registriert ist.
    BENÖTIGT ADMINISTRATORBERECHTIGUNGEN.
#>

# Block A: Preamble und Prüfung
# ====================================================================
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
$isUpdate = Test-Path -Path $InstallDir
$Hostname = $env:COMPUTERNAME

Clear-Host
Write-Host "======================================" -ForegroundColor Green
if ($isUpdate) { Write-Host "     ScanOp Client Updater" } 
else { Write-Host "     ScanOp Client Installer" }
Write-Host "======================================" -ForegroundColor Green
Write-Host ""


# Block B (FINAL UND KORREKT): Robuste, hierarchische Konfigurationslogik
# ====================================================================
Write-Host "Konfiguration wird geladen und geprüft..."
$ServerBaseUrl = ""
$ApiKey = ""
$AliasName = ""

# Priorität 1: Lade bestehende Konfiguration aus dem Installationsverzeichnis (falls Update)
if ($isUpdate -and (Test-Path $ConfigDestPath)) {
    Write-Host "-> Bestehende Installation gefunden. Lade Konfiguration aus '$ConfigDestPath'..." -ForegroundColor Cyan
    try {
        $existingConfig = Get-Content -Path $ConfigDestPath -Raw | ConvertFrom-Json
        # Explizite Zuweisung, um Typfehler zu vermeiden
        if ($existingConfig.PSObject.Properties.Name -contains 'ServerBaseUrl') { $ServerBaseUrl = $existingConfig.ServerBaseUrl }
        if ($existingConfig.PSObject.Properties.Name -contains 'ApiKey') { $ApiKey = $existingConfig.ApiKey }
        if ($existingConfig.PSObject.Properties.Name -contains 'AliasName') { $AliasName = $existingConfig.AliasName }
    } catch {
        Write-Warning "Konnte bestehende Konfigurationsdatei nicht lesen. Werte werden neu abgefragt."
    }
}

# Priorität 2: Lade Vorkonfiguration aus dem Installer-Ordner, falls Werte noch fehlen
if (Test-Path $PreconfigPath) {
    if ([string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "-> Prüfe 'client_config.json' im Installer-Verzeichnis auf fehlende Werte..."
        try {
            $preconfig = Get-Content -Path $PreconfigPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($ServerBaseUrl) -and $preconfig.PSObject.Properties.Name -contains 'ServerBaseUrl') { $ServerBaseUrl = $preconfig.ServerBaseUrl }
            if ([string]::IsNullOrWhiteSpace($ApiKey) -and $preconfig.PSObject.Properties.Name -contains 'ApiKey') { $ApiKey = $preconfig.ApiKey }
        } catch { Write-Warning "Konnte vorkonfigurierte Datei nicht lesen." }
    }
}

# Priorität 3: Frage den Benutzer interaktiv nach Werten, die immer noch fehlen.
if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) { 
    $ServerBaseUrl = Read-Host -Prompt "[EINGABE ERFORDERLICH] Geben Sie die Basis-URL des ScanOp-Servers ein (z.B. 'http://server/api/v1')" 
} else { 
    Write-Host "   [OK] Server-URL geladen: $ServerBaseUrl" 
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) { 
    $ApiKey = Read-Host -Prompt "[EINGABE ERFORDERLICH] Geben Sie den geheimen API-Schlüssel des Servers ein" 
} else { 
    Write-Host "   [OK] API-Schlüssel wurde geladen." 
}

# Behandle den Alias
if ($isUpdate -and -not [string]::IsNullOrWhiteSpace($AliasName)) {
    Write-Host "-> Ein Client mit dem Alias '$AliasName' ist bereits installiert."
    $changeAlias = Read-Host "Möchten Sie den Alias ändern? (j/n) [Standard: n]"
    if ($changeAlias.ToLower() -eq 'j') {
        $AliasName = Read-Host -Prompt "Geben Sie den neuen, eindeutigen Alias für diesen Computer ein"
    }
} else {
    $AliasName = Read-Host -Prompt "[EINGABE ERFORDERLICH] Geben Sie einen eindeutigen Alias für diesen Computer ein"
}

Write-Host "-> Verwende Alias: '$AliasName' für Hostname: '$Hostname'"

if ([string]::IsNullOrWhiteSpace($AliasName) -or [string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Error "Alle Felder sind erforderlich. Abbruch."; Read-Host "Drücken Sie Enter."; exit 1
}
$ServerBaseUrl = $ServerBaseUrl.TrimEnd('/')

# Block C, D, E, F bleiben unverändert, da sie jetzt korrekte Variablen erhalten...
# (Ich füge sie hier zur Vollständigkeit ein)

# Block C: Dateien installieren/aktualisieren
# ====================================================================
if ($isUpdate) { Write-Host "`nAktualisiere Installation in '$InstallDir'..." -ForegroundColor Yellow } 
else {
    Write-Host "`nVorbereitung der Installation in '$InstallDir'..." -ForegroundColor Yellow
    if (-NOT (Test-Path $InstallDir)) { New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null }
}
$finalConfigObject = [PSCustomObject]@{
    AliasName = $AliasName; ServerBaseUrl = $ServerBaseUrl; ApiKey = $ApiKey
    PollingIntervalSeconds = 60; InterimCheckIntervalMinutes = 30
}
$finalConfigObject | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigDestPath -Encoding UTF8 -Force
Write-Host "-> Konfigurationsdatei wurde geschrieben/aktualisiert."
Copy-Item -Path $ClientScriptSourcePath -Destination $ClientScriptDestPath -Force
Write-Host "-> Client-Skript wurde kopiert/aktualisiert."

# Block D: Client-Existenz prüfen und ggf. registrieren
# ====================================================================
Write-Host "`nPrüfe Client-Registrierung am Server..." -ForegroundColor Yellow
$checkUrl = "$ServerBaseUrl/laptops/$AliasName"
$headers = @{ "X-API-Key" = $ApiKey }
$clientExistsOnServer = $false
try {
    Invoke-RestMethod -Uri $checkUrl -Method Get -Headers $headers -ErrorAction Stop
    Write-Host "-> Client mit Alias '$AliasName' ist bereits auf dem Server registriert." -ForegroundColor Cyan
    $clientExistsOnServer = $true
} catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
        Write-Host "-> Client ist noch nicht auf dem Server registriert."
    } else {
        Write-Error "Fehler bei der Prüfung des Clients: $($_.Exception.Message)"; Read-Host "Drücken Sie Enter."; exit 1
    }
}
if (-NOT $clientExistsOnServer) {
    Write-Host "Registriere neuen Client '$AliasName' (Hostname: $Hostname)..."
    $registrationUrl = "$ServerBaseUrl/laptops"
    $registrationBody = @{ hostname = $Hostname; alias_name = $AliasName } | ConvertTo-Json
    try {
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
        Write-Error $errorMessage; Read-Host "Drücken Sie Enter."; exit 1
    }
}

# Block E: Geplanten Task installieren/aktualisieren
# ====================================================================
Write-Host "`nInstalliere/Aktualisiere Hintergrunddienst..." -ForegroundColor Yellow
$taskUser = "NT AUTHORITY\SYSTEM"
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ClientScriptDestPath`""
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType ServiceAccount
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
try {
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "Führt den ScanOp Client für die Server-Kommunikation im Hintergrund aus." -Force
    Write-Host "-> Hintergrunddienst '$taskName' erfolgreich installiert/aktualisiert."
    $startNow = Read-Host "Möchten Sie den Dienst jetzt sofort (neu) starten? (j/n)"
    if ($startNow.ToLower() -eq 'j') {
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
if ($isUpdate) { Write-Host "    Update erfolgreich!" } 
else { Write-Host "    Installation erfolgreich!" }
Write-Host "======================================" -ForegroundColor Green
Write-Host "Der ScanOp Client ist nun auf diesem Computer eingerichtet."
Read-Host "Drücken Sie Enter zum Schließen."