<#
.SYNOPSIS
    Finales, robustes Installations- und Update-Skript für den ScanOp Client.
.DESCRIPTION
    Dieses Skript verwendet die bewährte Logik der ursprünglichen Version für
    die Alias-Verwaltung und Server-Kommunikation und kombiniert sie mit dem
    robusten Update-Prozess. Die Server-Kommunikation wird jetzt transparent angezeigt.
    BENÖTIGT ADMINISTRATORBERECHTIGUNGEN.
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
        Read-Host "Bitte führen Sie das Skript über die 'start_installer.cmd'-Datei aus. Drücken Sie Enter zum Schließen."
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


# Block B: Technisches Update (falls nötig)
# ====================================================================
if ($isUpdateScenario) {
    if ($IsUnattendedUpdate) {
        $downloadRepoUrl = if ([string]::IsNullOrWhiteSpace($RepoUrl)) { "https://github.com/BitWuehler/ScanOp" } else { $RepoUrl.TrimEnd('/') }
        $downloadVersion = if ([string]::IsNullOrWhiteSpace($Version)) { "main" } else { $Version }
        $zipUrl = "$downloadRepoUrl/releases/download/$downloadVersion/ScanOp-Client.zip"
        $zipPath = Join-Path -Path $InstallerBaseDir -ChildPath "ScanOp-Client.zip"
        $extractPath = Join-Path -Path $InstallerBaseDir -ChildPath "extracted_update"
        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
            if (Test-Path $extractPath) { Remove-Item -Path $extractPath -Recurse -Force }
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            $ClientScriptSourcePath = Join-Path -Path $extractPath -ChildPath "ScanOpClient.ps1"
            Write-Host "-> Release-ZIP heruntergeladen und entpackt ($downloadVersion)." -ForegroundColor Green
        } catch {
            Write-Warning "Fehler beim Herunterladen der Release-ZIP. Versuche RAW-Download als Fallback..."
            $clientScriptUrl = "$downloadRepoUrl/raw/$downloadVersion/client/ScanOpClient.ps1"
            $downloadedScriptPath = Join-Path -Path $InstallerBaseDir -ChildPath "ScanOpClient_update.ps1"
            try {
                Invoke-WebRequest -Uri $clientScriptUrl -OutFile $downloadedScriptPath -UseBasicParsing
                $ClientScriptSourcePath = $downloadedScriptPath
            } catch {}
        }
    }

    if (Test-Path $ClientScriptSourcePath) { $sourceVersionDate = (Get-Item $ClientScriptSourcePath).LastWriteTime } else { $sourceVersionDate = [datetime]::MinValue }
    if (Test-Path $ClientScriptDestPath) { $installedVersionDate = (Get-Item $ClientScriptDestPath).LastWriteTime } else { $installedVersionDate = [datetime]::MinValue }
    
    if ($sourceVersionDate -gt $installedVersionDate -or $IsUnattendedUpdate) {
        Write-Host "Eine neuere Version des Client-Skripts ist verfügbar oder Update wurde erzwungen!" -ForegroundColor Yellow
        if (-not $IsUnattendedUpdate) {
            $choice = Read-Host "Möchten Sie das technische Update jetzt durchführen? (J/n) [Standard: J]"
            if ($choice.ToLower() -eq 'n') {
                Write-Host "Update abgebrochen. Das Skript wird beendet." -ForegroundColor Red; Read-Host "Drücken Sie Enter."; exit
            }
        }

        Write-Host "`nStarte Update-Prozess (inkl. Dienst-Korrektur)..." -ForegroundColor Yellow
        try {
            # ... (Der bewährte Update-Prozess bleibt erhalten)
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
            Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "Führt den ScanOp Client für die Server-Kommunikation im Hintergrund aus." -Force
            Write-Host "4. Starte den aktualisierten Dienst..."
            Start-ScheduledTask -TaskName $taskName
            Write-Host "`nTechnisches Update erfolgreich abgeschlossen!" -ForegroundColor Green
        } catch {
            Write-Error "Ein Fehler ist während des Updates aufgetreten: $($_.Exception.Message)"; Read-Host "Drücken Sie Enter."; exit
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

# Priorität 1: Lade bestehende Konfiguration
if ($isUpdateScenario -and (Test-Path $ConfigDestPath)) {
    Write-Host "-> Lade bestehende Konfiguration..."
    try {
        $existingConfig = Get-Content -Path $ConfigDestPath -Raw | ConvertFrom-Json
        $ServerBaseUrl = $existingConfig.ServerBaseUrl
        $ApiKey = $existingConfig.ApiKey
        $AliasName = $existingConfig.AliasName
    } catch { Write-Warning "Konnte bestehende Konfigurationsdatei nicht lesen." }
}

# Priorität 2: Vorkonfiguration laden
if (Test-Path $PreconfigPath) {
    if ([string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
        try {
            $preconfig = Get-Content -Path $PreconfigPath -Raw | ConvertFrom-Json
            if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) { $ServerBaseUrl = $preconfig.ServerBaseUrl }
            if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = $preconfig.ApiKey }
        } catch { Write-Warning "Konnte vorkonfigurierte Datei nicht lesen." }
    }
}

# Priorität 3: Interaktive Abfrage
if ([string]::IsNullOrWhiteSpace($ServerBaseUrl)) { $ServerBaseUrl = Read-Host -Prompt "Geben Sie die Basis-URL des ScanOp-Servers ein" }
if ([string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey = Read-Host -Prompt "Geben Sie den geheimen API-Schlüssel ein" }

# Alias-Management
if ($isUpdateScenario -and -not [string]::IsNullOrWhiteSpace($AliasName)) {
    Write-Host "-> Der aktuell konfigurierte Alias ist '$AliasName'."
    if (-not $IsUnattendedUpdate) {
        $changeAlias = Read-Host "Möchten Sie den Alias ändern? (j/N) [Standard: N]"
        if ($changeAlias.ToLower() -eq 'j') {
            $AliasName = Read-Host -Prompt "Geben Sie den neuen, eindeutigen Alias ein"
        }
    }
} else {
    if (-not $IsUnattendedUpdate) {
        $AliasName = Read-Host -Prompt "Bitte geben Sie einen eindeutigen Alias für diesen Computer ein"
    }
}

$ChangeHostname = $false
if (-not $IsUnattendedUpdate) {
    $askChangeHost = Read-Host "Möchten Sie den Hostname des Rechners an den Alias anpassen? (j/N) [Standard: N]"
    if ($askChangeHost.ToLower() -eq 'j') {
        $ChangeHostname = $true
    }
}

if ([string]::IsNullOrWhiteSpace($AliasName) -or [string]::IsNullOrWhiteSpace($ServerBaseUrl) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
    Write-Error "Alle Konfigurationsfelder sind erforderlich. Abbruch."; Read-Host "Drücken Sie Enter."; exit 1
}

# Verzeichnis erstellen, falls es nicht existiert, BEVOR die Konfiguration geschrieben wird
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

# Standard-Werte für Repo, falls leer
$finalRepoUrl = if ([string]::IsNullOrWhiteSpace($RepoUrl)) { "https://github.com/BitWuehler/ScanOp" } else { $RepoUrl }
$finalVersion = if ([string]::IsNullOrWhiteSpace($Version)) { "main" } else { $Version }

# Konfiguration in Datei speichern
$finalConfigObject = [PSCustomObject]@{ AliasName = $AliasName; ServerBaseUrl = $ServerBaseUrl.TrimEnd('/'); ApiKey = $ApiKey; GitHubRepoUrl = $finalRepoUrl; GitHubVersion = $finalVersion; PollingIntervalSeconds = 60; InterimCheckIntervalMinutes = 30 }
$finalConfigObject | ConvertTo-Json -Depth 3 | Set-Content -Path $ConfigDestPath -Encoding UTF8 -Force
Write-Host "-> Konfiguration wurde lokal gespeichert." -ForegroundColor Green


# Block D: Server-Synchronisation (wiederhergestellte Original-Logik)
# ====================================================================
Write-Host "`nPrüfe Client-Registrierung am Server für Alias '$AliasName'..." -ForegroundColor Yellow
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
        Write-Error "Fehler bei der Prüfung des Clients: $($_.Exception.Message)"; Read-Host "Drücken Sie Enter."; exit 1
    }
}

if (-NOT $clientExistsOnServer) {
    $Hostname = $env:COMPUTERNAME
    $hostnameChanged = $false
    $registrationUrl = "$($finalConfigObject.ServerBaseUrl)/api/v1/laptops"

    if ($ChangeHostname) {
        $Hostname = $AliasName.ToUpper()
        if ($Hostname.Length -gt 15) {
            $Hostname = $Hostname.Substring($Hostname.Length - 15)
        }
        Write-Host "-> Hostname wird auf '$Hostname' geändert..." -ForegroundColor Yellow
        try { 
            Rename-Computer -NewName $Hostname -Force -ErrorAction Stop 
            $hostnameChanged = $true
        } catch { 
            Write-Warning "Konnte Hostname nicht sofort ändern: $($_.Exception.Message)" 
        }
    }

    Write-Host "Registriere neuen Client '$AliasName' (Hostname: $Hostname)..."
    
    $registrationBody = @{ hostname = $Hostname; alias_name = $AliasName } | ConvertTo-Json
    Write-Host "-> Sende an Server ($registrationUrl):"
    Write-Host ($registrationBody | ConvertTo-Json -Depth 3) -ForegroundColor Gray

    try {
        Invoke-RestMethod -Uri $registrationUrl -Method Post -Headers $headers -Body $registrationBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "-> Client erfolgreich beim Server registriert!" -ForegroundColor Green
    } catch {
        $statusCode = 0
        $responseBody = ""
        if ($_.Exception.Response) { 
            $statusCode = [int]$_.Exception.Response.StatusCode
            $responseBody = $_.Exception.Response.GetResponseStream() | ForEach-Object { (New-Object System.IO.StreamReader($_)).ReadToEnd() }
        }
        
        $askAgain = 'n'
        if (-not $IsUnattendedUpdate) {
            Write-Warning "Registrierung fehlgeschlagen. Möglicher Grund: Hostname '$Hostname' ist bereits vergeben."
            Write-Warning "Server meldet (HTTP $statusCode): $responseBody"
            $askAgain = Read-Host "Soll der Hostname des Rechners auf den Alias geändert werden, um Konflikte zu vermeiden? (J/n) [Standard: J]"
        }
        
        if ($askAgain.ToLower() -ne 'n') {
            $Hostname = $AliasName.ToUpper()
            if ($Hostname.Length -gt 15) {
                $Hostname = $Hostname.Substring($Hostname.Length - 15)
            }
            Write-Host "-> Ändere System-Hostname auf: $Hostname" -ForegroundColor Yellow
            try { 
                Rename-Computer -NewName $Hostname -Force -ErrorAction Stop 
                $hostnameChanged = $true
            } catch { 
                Write-Warning "Fehler beim Ändern des Hostnames: $($_.Exception.Message)" 
            }
            
            $registrationBody = @{ hostname = $Hostname; alias_name = $AliasName } | ConvertTo-Json
            try {
                Invoke-RestMethod -Uri $registrationUrl -Method Post -Headers $headers -Body $registrationBody -ContentType "application/json" -ErrorAction Stop
                Write-Host "-> Client erfolgreich mit neuem Hostname beim Server registriert!" -ForegroundColor Green
            } catch {
                Write-Error "Fehler bei der erneuten Registrierung des Clients: $($_.Exception.Message)"
                Write-Host "Drücken Sie eine beliebige Taste zum Beenden..."
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                exit 1
            }
        } else {
            Write-Error "Registrierung abgebrochen."
            Write-Host "Drücken Sie eine beliebige Taste zum Beenden..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit 1
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
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description "Führt den ScanOp Client für die Server-Kommunikation im Hintergrund aus." -Force
    Write-Host "-> Hintergrunddienst '$taskName' erfolgreich installiert."

    $startChoice = Read-Host "Möchten Sie den Dienst jetzt sofort starten? (J/n) [Standard: J]"
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

if ($hostnameChanged -and (-not $IsUnattendedUpdate)) {
    Write-Host ""
    $askReboot = Read-Host "Der Hostname wurde geändert. Ein Neustart ist erforderlich. Möchten Sie den Rechner jetzt neu starten? (J/n) [Standard: J]"
    if ($askReboot.ToLower() -ne 'n') {
        Write-Host "Starte neu..." -ForegroundColor Yellow
        Restart-Computer -Force
    }
}

Write-Host ""
Write-Host "Vorgang erfolgreich abgeschlossen." -ForegroundColor Green
if (-not $IsUnattendedUpdate) {
    Write-Host "Drücken Sie eine beliebige Taste zum Schließen..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
exit 0
