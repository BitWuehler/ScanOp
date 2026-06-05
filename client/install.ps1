<#
.SYNOPSIS
    Finales, robustes Installations- und Update-Skript fÃ¼r den ScanOp Client.
.DESCRIPTION
    Dieses Skript verwendet die bewÃ¤hrte Logik der ursprÃ¼nglichen Version fÃ¼r
    die Alias-Verwaltung und Server-Kommunikation und kombiniert sie mit dem
    robusten Update-Prozess. Die Server-Kommunikation wird jetzt transparent angezeigt.
    BENÃ–TIGT ADMINISTRATORBERECHTIGUNGEN.
#>

param(
    [string]$RepoUrl = "",
    [string]$Version = "",
    [switch]$IsUnattendedUpdate
)

# Block A: Preamble und Umgebungseinstellungen
# ====================================================================
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Fehler: Administratorrechte sind erforderlich."
    if (-not $IsUnattendedUpdate) {
        Read-Host "Bitte fÃ¼hren Sie das Skript Ã¼ber die 'start_installer.cmd'-Datei aus. DrÃ¼cken Sie Enter zum SchlieÃŸen."
    }
    exit 1
}

$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$InstallerBaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = "C:\Program Files\ScanOpClient"
$ClientScriptSourcePath = Join-Path -Path $InstallerBaseDir -ChildPath "ScanOpClient.ps1"
$PreconfigPath = Join-Path -Path $InstallerBaseDir -ChildPath "client_config.json"
$ClientScriptDestPath = Join-Path -Path $InstallDir -ChildPath "ScanOpClient.ps1"
$ConfigDestPath = Join-Path -Path $InstallDir -ChildPath "client_config.json"
$taskName = "ScanOpClientService"
$isUpdateScenario = Test-Path -Path $InstallDir

Clear-Host
Write-Host "======================================" -ForegroundColor Green
Write-Host "     ScanOp Client Installer/Updater"
Write-Host "======================================" -ForegroundColor Green
Write-Host "Dieses Skript installiert oder aktualisiert den ScanOp-Dienst."
Write-Host ""


# Block B: Technisches Update (falls nÃ¶tig)
# ====================================================================
if ($isUpdateScenario) {
    if ($IsUnattendedUpdate) {
        $downloadRepoUrl = if ([string]::IsNullOrWhiteSpace($RepoUrl)) { "https://github.com/BitWuehler/ScanOp" } else { $RepoUrl.TrimEnd('/') }
        $downloadVersion = if ([string]::IsNullOrWhiteSpace($Version)) { "main" } else { $Version }
        $clientScriptUrl = "$downloadRepoUrl/raw/$downloadVersion/client/ScanOpClient.ps1"
        $downloadedScriptPath = Join-Path -Path $InstallerBaseDir -ChildPath "ScanOpClient_update.ps1"
        try {
            Invoke-WebRequest -Uri $clientScriptUrl -OutFile $downloadedScriptPath -UseBasicParsing
            $ClientScriptSourcePath = $downloadedScriptPath
            Write-Host "-> Neues Client-Skript heruntergeladen ($downloadVersion)." -ForegroundColor Green
        } catch {
            Write-Warning "Fehler beim Herunterladen des neuen Client-Skripts. Verwende lokales Fallback."
        }
    }

    if (Test-Path $ClientScriptSourcePath) { $sourceVersionDate = (Get-Item $ClientScriptSourcePath).LastWriteTime } else { $sourceVersionDate = [datetime]::MinValue }
    if (Test-Path $ClientScriptDestPath) { $installedVersionDate = (Get-Item $ClientScriptDestPath).LastWriteTime } else { $installedVersionDate = [datetime]::MinValue }
    
    if ($sourceVersionDate -gt $installedVersionDate -or $IsUnattendedUpdate) {
        Write-Host "Eine neuere Version des Client-Skripts ist verfÃ¼gbar oder Update wurde erzwungen!" -ForegroundColor Yellow
        if (-not $IsUnattendedUpdate) {
            $choice = Read-Host "MÃ¶chten Sie das technische Update jetzt durchfÃ¼hren? (J/n) [Standard: J]"
            if ($choice.ToLower() -eq 'n') {
                Write-Host "Update abgebrochen. Das Skript wird beendet." -ForegroundColor Red; Read-Host "DrÃ¼cken Sie Enter."; exit
            }
        }

        Write-Host "`nStarte Update-Prozess (inkl. Dienst-Korrektur)..." -ForegroundColor Yellow
        try {
            # ... (Der bewÃ¤hrte Update-Prozess bleibt erhalten)
            Write-Host "1. Stoppe den aktuell laufenden Dienst..."
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Write-Host "2. Kopiere neue Skript-Version..."
            Copy-Item -Path $ClientScriptSourcePath -Destination $ClientScriptDestPath -Force
            Write-Host "3. Aktualisiere die Dienst-Einstellungen..."
            $taskUser = "NT AUTHORITY\SYSTEM"
            $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ClientScriptDestPath`""
            $taskTrigger = New-ScheduledTaskTrigger -AtStartup
            $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType ServiceAccount
            $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit ([TimeSpan]::Zero)
            Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
            Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "FÃ¼hrt den ScanOp Client fÃ¼r die Server-Kommunikation im Hintergrund aus." -Force
            Write-Host "4. Starte den aktualisierten Dienst..."
            Start-ScheduledTask -TaskName $taskName
            Write-Host "`nTechnisches Update erfolgreich abgeschlossen!" -ForegroundColor Green
        } catch {
            Write-Error "Ein Fehler ist wÃ¤hrend des Updates aufgetreten: $($_.Exception.Message)"; Read-Host "DrÃ¼cken Sie Enter."; exit
        }
    } else {
        Write-Host "-> Die installierte Version ist bereits aktuell." -ForegroundColor Green
    }
}

# Block C: Konfigurations-Management (wiederhergestellte Original-Logik)
# ====================================================================
Write-Host "`n--- Konfigurations-Management ---" -ForegroundColor Cyan

# Variablen initialisieren
$ServerBaseUrl = ""; $ApiKey = ""; $AliasName = ""

# PrioritÃ¤t 1: Lade bestehende Konfiguration
if ($isUpdateScenario -and (Test-Path $ConfigDestPath)) {
    Write-Host "-> Lade bestehende Konfiguration..."
    try {
        $existingConfig = Get-Content -Path $ConfigDestPath -Raw | ConvertFrom-Json
        $ServerBaseUrl = $existingConfig.ServerBaseUrl
        $ApiKey = $existingConfig.ApiKey
        $AliasName = $existingConfig.AliasName
    } catch { Write-Warning "Konnte bestehende Konfigurationsdatei nicht lesen." }
}

# PrioritÃ¤t 2: Vorkonfiguration laden
if (Test-Path $PreconfigPath) {
    if ([string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
        try {
            $preconfig = Get-Content -Path $PreconfigPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) { $ServerBaseUrl = $preconfig.ServerBaseUrl }
            if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = $preconfig.ApiKey }
        } catch { Write-Warning "Konnte vorkonfigurierte Datei nicht lesen." }
    }
}

# PrioritÃ¤t 3: Interaktive Abfrage
if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) { $ServerBaseUrl = Read-Host -Prompt "Geben Sie die Basis-URL des ScanOp-Servers ein" }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = Read-Host -Prompt "Geben Sie den geheimen API-SchlÃ¼ssel ein" }

# Alias-Management
if ($isUpdateScenario -and -not [string]::IsNullOrWhiteSpace($AliasName)) {
    Write-Host "-> Der aktuell konfigurierte Alias ist '$AliasName'."
    if (-not $IsUnattendedUpdate) {
        $changeAlias = Read-Host "MÃ¶chten Sie den Alias Ã¤ndern? (j/N) [Standard: N]"
        if ($changeAlias.ToLower() -eq 'j') {
            $AliasName = Read-Host -Prompt "Geben Sie den neuen, eindeutigen Alias ein"
        }
    }
} else {
    if (-not $IsUnattendedUpdate) {
        $AliasName = Read-Host -Prompt "Bitte geben Sie einen eindeutigen Alias fÃ¼r diesen Computer ein"
    }
}

if ([string]::IsNullOrWhiteSpace($AliasName) -or [string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Error "Alle Konfigurationsfelder sind erforderlich. Abbruch."; Read-Host "DrÃ¼cken Sie Enter."; exit 1
}

# Verzeichnis erstellen, falls es nicht existiert, BEVOR die Konfiguration geschrieben wird
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

# Standard-Werte fÃ¼r Repo, falls leer
$finalRepoUrl = if ([string]::IsNullOrWhiteSpace($RepoUrl)) { "https://github.com/BitWuehler/ScanOp" } else { $RepoUrl }
$finalVersion = if ([string]::IsNullOrWhiteSpace($Version)) { "main" } else { $Version }

# Konfiguration in Datei speichern
$finalConfigObject = [PSCustomObject]@{ AliasName = $AliasName; ServerBaseUrl = $ServerBaseUrl.TrimEnd('/'); ApiKey = $ApiKey; GitHubRepoUrl = $finalRepoUrl; GitHubVersion = $finalVersion; PollingIntervalSeconds = 60; InterimCheckIntervalMinutes = 30 }
$finalConfigObject | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigDestPath -Encoding UTF8 -Force
Write-Host "-> Konfiguration wurde lokal gespeichert." -ForegroundColor Green


# Block D: Server-Synchronisation (wiederhergestellte Original-Logik)
# ====================================================================
Write-Host "`nPrÃ¼fe Client-Registrierung am Server fÃ¼r Alias '$AliasName'..." -ForegroundColor Yellow
$checkUrl = "$($finalConfigObject.ServerBaseUrl)/api/v1/laptops/$AliasName"
$headers = @{ "X-API-Key" = $finalConfigObject.ApiKey }
$clientExistsOnServer = $false

# NEU: Transparente Ausgabe
Write-Host "-> Sende Anfrage an: $checkUrl"
try {
    Invoke-RestMethod -Uri $checkUrl -Method Get -Headers $headers -ErrorAction Stop
    Write-Host "-> Client mit Alias '$AliasName' ist bereits auf dem Server registriert." -ForegroundColor Cyan
    $clientExistsOnServer = $true
} catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
        Write-Host "-> Client mit Alias '$AliasName' ist noch nicht auf dem Server registriert."
    } else {
        Write-Error "Fehler bei der PrÃ¼fung des Clients: $($_.Exception.Message)"; Read-Host "DrÃ¼cken Sie Enter."; exit 1
    }
}

if (-NOT $clientExistsOnServer) {
    $Hostname = $env:COMPUTERNAME
    Write-Host "Registriere neuen Client '$AliasName' (Hostname: $Hostname)..."
    $registrationUrl = "$($finalConfigObject.ServerBaseUrl)/api/v1/laptops"
    $registrationBody = @{ hostname = $Hostname; alias_name = $AliasName } | ConvertTo-Json
    
    # NEU: Transparente Ausgabe
    Write-Host "-> Sende an Server ($registrationUrl):"
    Write-Host ($registrationBody | ConvertTo-Json -Depth 3) -ForegroundColor Gray

    try {
        Invoke-RestMethod -Uri $registrationUrl -Method Post -Headers $headers -Body $registrationBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "-> Client erfolgreich beim Server registriert!" -ForegroundColor Green
    } catch {
        $errorMessage = "Fehler bei der Registrierung des Clients."; if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode; $responseBody = $_.Exception.Response.GetResponseStream() | ForEach-Object { (New-Object System.IO.StreamReader($_)).ReadToEnd() }; $errorMessage += " (HTTP $statusCode): $responseBody"; if ($statusCode -eq 400) { $errorMessage += "`n-> MÃ–GLICHE URSACHE: Der Alias existiert bereits." } } else { $errorMessage += ": $($_.Exception.Message)" }; Write-Error $errorMessage; Read-Host "DrÃ¼cken Sie Enter."; exit 1
    }
}

# Block E: Neuinstallation-spezifische Aktionen
# ====================================================================
if (-not $isUpdateScenario) {
    Copy-Item -Path $ClientScriptSourcePath -Destination $ClientScriptDestPath -Force
    $taskUser = "NT AUTHORITY\SYSTEM"
    $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ClientScriptDestPath`""
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType ServiceAccount
    $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5) -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "FÃ¼hrt den ScanOp Client fÃ¼r die Server-Kommunikation im Hintergrund aus." -Force
    Write-Host "-> Hintergrunddienst '$taskName' erfolgreich installiert."

    $startChoice = Read-Host "MÃ¶chten Sie den Dienst jetzt sofort starten? (J/n) [Standard: J]"
    if ($startChoice.ToLower() -ne 'n') {
        Start-ScheduledTask -TaskName $taskName
        Write-Host "-> Dienst wurde gestartet." -ForegroundColor Green
    }
}

# Block F: Abschluss
# ====================================================================
try {
    $clearUrl = "$($finalConfigObject.ServerBaseUrl)/api/v1/clientcommands/$AliasName/clear"
    $clearHeaders = @{ "X-API-Key" = $finalConfigObject.ApiKey; "Content-Type" = "application/json" }
    $clearBody = @{ client_version = $finalConfigObject.GitHubVersion } | ConvertTo-Json
    Invoke-RestMethod -Uri $clearUrl -Method Post -Headers $clearHeaders -Body $clearBody -ErrorAction SilentlyContinue | Out-Null
    Write-Host "-> Status erfolgreich an Server gemeldet." -ForegroundColor Green
} catch {}

Write-Host ""
Write-Host "Vorgang erfolgreich abgeschlossen." -ForegroundColor Green
if (-not $IsUnattendedUpdate) {
    Read-Host "DrÃ¼cken Sie Enter zum SchlieÃŸen."
}
