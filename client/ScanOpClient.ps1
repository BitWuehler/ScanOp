<#
.SYNOPSIS
    GehÃ¤rtetes Client-Skript zum Pollen von Befehlen mit Failsafe-Timeout und robuster Scan-Erkennung.
.DESCRIPTION
    Diese finale Version verwendet die bewÃ¤hrte Job-Start-Logik aus der funktionierenden
    Referenzversion und kombiniert sie mit der robusten dreifachen PrÃ¼fung 
    (Job-Status, Failsafe-Timeout, Event-Log-Analyse) zur Erkennung des Scan-Abschlusses.
    BENÃ–TIGT ADMINISTRATORBERECHTIGUNGEN fÃ¼r Start-MpScan und Get-WinEvent.
#>

# --- Konfiguration und Initialisierung ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "client_config.json"
$LastReportTimeFilePath = Join-Path -Path $ScriptDir -ChildPath "last_report_time.txt"
$LogFilePath = Join-Path -Path $ScriptDir -ChildPath "client_virenscan.log"
$LogFileMaxSizeMB = 5 

# --- Log-Datei-Rotation ---
try {
    if (Test-Path $LogFilePath) {
        $logFileSize = (Get-Item $LogFilePath).Length / 1MB
        if ($logFileSize -gt $LogFileMaxSizeMB) {
            Move-Item -Path $LogFilePath -Destination "$($LogFilePath).old" -Force
            Write-Host "LOG: Log-Datei wurde rotiert."
        }
    }
} catch { Write-Warning "LOG WARN: Fehler beim Rotieren der Log-Datei: $($_.Exception.Message)" }

# --- Log-Funktion ---
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        $Level = "INFO" 
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] - $Message"
    switch ($Level) {
        "INFO"  { Write-Host $logEntry }
        "WARN"  { Write-Warning $Message }
        "ERROR" { Write-Error $Message }
    }
    try {
        Add-Content -Path $LogFilePath -Value $logEntry
    } catch {
        Write-Error "KRITISCH: Konnte nicht in die Log-Datei '$LogFilePath' schreiben. Fehler: $($_.Exception.Message)"
    }
}

# --- Ã„USSERE SCHLEIFE FÃœR MAXIMALE ROBUSTHEIT ---
$Global:FatalErrorCount = 0
while ($true) {
    try {
        Write-Log -Message "================== Skript-Zyklus wird gestartet =================="

        # --- Konfiguration laden ---
        if (-not (Test-Path $ConfigFilePath)) {
            Write-Log -Level ERROR -Message "Konfigurationsdatei nicht gefunden: $ConfigFilePath. Warte 60s."
            Start-Sleep -Seconds 60; continue
        }
        try {
            $Config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Log -Level ERROR -Message "Fehler beim Parsen der Konfigurationsdatei '$ConfigFilePath': $($_.Exception.Message). Warte 60s."
            Start-Sleep -Seconds 60; continue
        }

        $AliasName = $Config.AliasName; $ServerBaseUrl = $Config.ServerBaseUrl; $ApiKey = $Config.ApiKey 
        $PollingIntervalSeconds = $Config.PollingIntervalSeconds; $InitialRetryDelaySeconds = 60; $MaxRetryDelaySeconds = 1800
        $ClientVersion = if ($Config.GitHubVersion) { $Config.GitHubVersion } else { "1.0.0" }
        
        $Script:ActiveScanJob = $null; $Script:ScanInitiationTimeUTC = $null; $Script:ScanTypeForActiveJob = $null
        $Global:LastSuccessfulReportTimeUTC = $null
        if (Test-Path $LastReportTimeFilePath) {
            try {
                $loadedTimeRaw = Get-Content -Path $LastReportTimeFilePath -Raw
                $Global:LastSuccessfulReportTimeUTC = ([datetime]($loadedTimeRaw | ConvertFrom-Json)).ToUniversalTime()
                if ($Global:LastSuccessfulReportTimeUTC) { Write-Log -Message "Letzte erfolgreiche Report-Zeit geladen: $($Global:LastSuccessfulReportTimeUTC.ToLocalTime())" }
            } catch { Write-Log -Level WARN -Message "Fehler beim Laden von '$LastReportTimeFilePath'." }
        }
        if ($null -eq $Global:LastSuccessfulReportTimeUTC) {
            Write-Log -Message "Keine gültige letzte Report-Zeit gefunden."
            $Global:LastSuccessfulReportTimeUTC = (Get-Date "1970-01-01").ToUniversalTime() 
        }

        Write-Log -Message "Client konfiguriert für Alias: $AliasName / Server URL: $ServerBaseUrl / Version: $ClientVersion"
        $CommandUrl = "$ServerBaseUrl/api/v1/clientcommands/$AliasName?version=$ClientVersion"; $ReportUrl = "$ServerBaseUrl/api/v1/scanreports/"

        # --- Hilfsfunktionen (unverändert) ---
        function Send-ScanReport { param( [Parameter(Mandatory=$true)][string]$ScanTime, [Parameter(Mandatory=$true)][string]$ScanType, [Parameter(Mandatory=$true)][string]$ScanResultMessage, [Parameter(Mandatory=$true)][bool]$ThreatsFound, [string]$ThreatDetails = $null ); Write-Log -Message "Bereite Scan-Bericht ($ScanType) für Versand vor."; if ([string]::IsNullOrWhiteSpace($ScanTime)) { $ScanTime = (Get-Date "1970-01-01").ToUniversalTime().ToString("o") } ; if ([string]::IsNullOrWhiteSpace($ScanType)) { $ScanType = "Unbekannt" } ; if ([string]::IsNullOrWhiteSpace($ScanResultMessage)) { $ScanResultMessage = "Keine Meldung" } ; $CleanResultMessage = $ScanResultMessage -replace '[\x00-\x1F\x7F]', '' ; $CleanThreatDetails = if ($ThreatDetails) { $ThreatDetails -replace '[\x00-\x1F\x7F]', '' } else { $null } ; $payloadContent = @{ laptop_identifier = $AliasName; client_scan_time = $ScanTime; scan_type = $ScanType; scan_result_message = $CleanResultMessage; threats_found = $ThreatsFound }; if ($null -ne $CleanThreatDetails -and (-not [string]::IsNullOrWhiteSpace($CleanThreatDetails))) { $payloadContent.threat_details = $CleanThreatDetails } else { $payloadContent.threat_details = $null } ; $payloadBodyJson = $payloadContent | ConvertTo-Json -Depth 5 -Compress; $utf8Encoding = [System.Text.Encoding]::UTF8; $payloadBytes = $utf8Encoding.GetBytes($payloadBodyJson); $requestHeaders = @{ "Content-Type" = "application/json; charset=utf-8"; "X-API-Key" = $ApiKey }; Write-Log -Message "Sende Bericht... (Länge: $($payloadBytes.Length) bytes)"; $ErrorActionPreferenceBackup = $ErrorActionPreference; $ErrorActionPreference = "Stop"; try { Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payloadBytes -Headers $requestHeaders -TimeoutSec 120; Write-Log -Message "Scan-Bericht erfolgreich an Server gesendet."; $Global:LastSuccessfulReportTimeUTC = (Get-Date).ToUniversalTime(); try { ($Global:LastSuccessfulReportTimeUTC.ToString("o") | ConvertTo-Json -Compress) | Set-Content -Path $LastReportTimeFilePath -Force -Encoding UTF8; Write-Log -Message "Letzte erfolgreiche Report-Zeit aktualisiert: $($Global:LastSuccessfulReportTimeUTC.ToLocalTime())" } catch { Write-Log -Level WARN -Message "Fehler beim Speichern von '$LastReportTimeFilePath': $($_.Exception.Message)" }; return $true } catch { $CaughtException = $_; Write-Log -Level ERROR -Message "FEHLER bei Send-ScanReport: $($CaughtException.ToString())"; if ($CaughtException.Exception -is [System.Net.WebException] -and $null -ne $CaughtException.Exception.Response) { $webEx = $CaughtException.Exception; $httpResponse = $webEx.Response; $actualHttpStatusCode = [int]$httpResponse.StatusCode; Write-Log -Level ERROR -Message "  HTTP Status: $actualHttpStatusCode"; try { $responseStream = $httpResponse.GetResponseStream(); $streamReader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8); $errorBodyContent = $streamReader.ReadToEnd(); $streamReader.Close(); $responseStream.Close(); Write-Log -Level ERROR -Message "  Fehler-Body vom Server: $errorBodyContent" } catch { Write-Log -Level ERROR -Message "  Zusätzlicher Fehler beim Lesen des Fehler-Bodys: $($_.Exception.Message)" } }; return $false } finally { $ErrorActionPreference = $ErrorActionPreferenceBackup } }; function ConvertFrom-DefenderEvent { param( [Parameter(Mandatory=$true)] $Event ); $eventTimeUTC = $Event.TimeCreated.ToUniversalTime().ToString("o"); $simplified = @{ Message = "Event $($Event.Id): " + (($Event.Message -replace '[\x00-\x1F\x7F]', '').Trim() -split '\r?\n')[0]; ThreatsFound = $false; ThreatDetails = $null }; if ($simplified.Message -match "Bedrohung gefunden") { $simplified.ThreatsFound = $true }; if ($Event.Id -in (1002, 1116, 1117, 1118)) { $simplified.ThreatsFound = $true }; if ($Event.Message -match "Name: (.*?)\s*Pfad: (.*?)\s*Aktion: (.*?)\s*") { $simplified.ThreatDetails = "Name: $($Matches[1].Trim()), Pfad: $($Matches[2].Trim()), Aktion: $($Matches[3].Trim())" }; return [PSCustomObject]$simplified }
        
        # --- HAUPT-POLLING-SCHLEIFE ---
        $currentRetryDelay = $InitialRetryDelaySeconds
        Write-Log -Message "Starte Haupt-Polling-Schleife..."
        while ($true) {
            $networkOperationSuccess = $true

            # --- 1. JOB-STATUS-PRÜFUNG mit FAILSAFE ---
            if ($null -ne $Script:ActiveScanJob) {

                $isTimedOut = $false; $completionEvent = $null
                $elapsedMinutes = ((Get-Date).ToUniversalTime() - $Script:ScanInitiationTimeUTC).TotalMinutes
                $timeoutLimitMinutes = if ($Script:ScanTypeForActiveJob -eq 'FullScan') { 180 } else { 30 }
                if ($elapsedMinutes -gt $timeoutLimitMinutes) { $isTimedOut = $true }

                if ($Script:ActiveScanJob.State -eq 'Running' -and (-not $isTimedOut)) {
                    try {
                        $completionEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 10 -ErrorAction SilentlyContinue | Where-Object { ($_.Id -in (1001, 1002, 1005)) -and ($_.TimeCreated.ToUniversalTime() -gt $Script:ScanInitiationTimeUTC) } | Sort-Object TimeCreated -Descending | Select-Object -First 1
                    } catch { Write-Log -Level WARN -Message "Fehler bei proaktiver Event-Suche: $($_.Exception.Message)" }
                }
                
                if ($Script:ActiveScanJob.State -in @('Completed', 'Failed', 'Stopped') -or $completionEvent -or $isTimedOut) {
                    Write-Log -Message "Scan-Abschluss erkannt. Grund: Job-Status='$($Script:ActiveScanJob.State)', Event-Gefunden='$($completionEvent -ne $null)', Timeout='$isTimedOut'."
                    if ($isTimedOut -and $Script:ActiveScanJob.State -notlike 'Stopped') {
                        Write-Log -Level WARN -Message "Scan hat das Zeitlimit von $timeoutLimitMinutes Minuten überschritten. Breche Job ab."
                        Stop-Job -Job $Script:ActiveScanJob -Force
                    }

                    $scanJobResult = Receive-Job -Job $Script:ActiveScanJob -Keep
                    $reportScanTime = $Script:ScanInitiationTimeUTC.ToString("o"); $reportResultMessageAggregator = [System.Text.StringBuilder]::new(); $reportThreatDetailsAggregator = [System.Text.StringBuilder]::new(); $reportThreatsFound = $false

                    [void]$reportResultMessageAggregator.AppendLine("Scan ($($Script:ScanTypeForActiveJob)) initiiert $($reportScanTime) wurde beendet. Job-Status: $($Script:ActiveScanJob.State).")
                    if ($isTimedOut) { $reportThreatsFound = $true; [void]$reportResultMessageAggregator.AppendLine("FEHLER: Scan wurde nach Überschreiten des Zeitlimits von $timeoutLimitMinutes Minuten abgebrochen.") }
                    if ($Script:ActiveScanJob.State -ne 'Completed' -or ($scanJobResult -is [System.Management.Automation.ErrorRecord])) { $reportThreatsFound = $true; [void]$reportResultMessageAggregator.AppendLine("Scan-Job meldete Fehler."); [void]$reportThreatDetailsAggregator.AppendLine("Job-Fehler: $($scanJobResult | Out-String)") }

                    $finalScanEvent = $completionEvent
                    if (-not $finalScanEvent) { $finalScanEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 20 | Where-Object { ($_.Id -in (1001,1002,1005)) -and ($_.TimeCreated.ToUniversalTime() -ge $Script:ScanInitiationTimeUTC) } | Sort-Object TimeCreated -Descending | Select-Object -First 1 }

                    if ($finalScanEvent) {
                        $interpreted = ConvertFrom-DefenderEvent -Event $finalScanEvent
                        [void]$reportResultMessageAggregator.AppendLine($interpreted.Message)
                        if ($interpreted.ThreatsFound) { $reportThreatsFound = $true }
                        if ($interpreted.ThreatDetails) { [void]$reportThreatDetailsAggregator.AppendLine($interpreted.ThreatDetails) }
                    } else { [void]$reportResultMessageAggregator.AppendLine("Kein offizielles Scan-Abschluss-Event gefunden.") }
                    
                    if ($reportThreatsFound -eq $false -and $Script:ActiveScanJob.State -eq 'Completed' -and (-not $isTimedOut)) {
                        $reportResultMessageAggregator.Clear(); [void]$reportResultMessageAggregator.Append("Scan ($($Script:ScanTypeForActiveJob)) erfolgreich abgeschlossen. Keine Bedrohungen gefunden."); $reportThreatDetailsAggregator.Clear()
                    }

                    if (Send-ScanReport -ScanTime $reportScanTime -ScanType $Script:ScanTypeForActiveJob -ScanResultMessage $reportResultMessageAggregator.ToString().Trim() -ThreatsFound $reportThreatsFound -ThreatDetails $reportThreatDetailsAggregator.ToString().Trim()) {
                        Write-Log -Message "Entferne abgeschlossenen Job und setze Zustand zurück."
                        Remove-Job -Job $Script:ActiveScanJob -Force
                        $Script:ActiveScanJob = $null; $Script:ScanInitiationTimeUTC = $null; $Script:ScanTypeForActiveJob = $null
                    } else { $networkOperationSuccess = $false; Write-Log -Level WARN -Message "Fehler beim Melden des Job-Ergebnisses. Job wird behalten, Versand wird erneut versucht." }
                } else {
                    Write-Log -Message "Ein Scan (Typ: $($Script:ScanTypeForActiveJob), Laufzeit: $([int]$elapsedMinutes) von $timeoutLimitMinutes min) läuft noch im Hintergrund. Warte auf Abschluss..."
                }
            }

            # --- 2. BEFEHLSABRUF ---
            if ($networkOperationSuccess) {
                Write-Log -Message "Frage Befehle vom Server ab: $CommandUrl"
                try {
                    $commandResponse = Invoke-RestMethod -Uri $CommandUrl -Method Get -Headers @{ "X-API-Key" = $ApiKey } -TimeoutSec 20 -ErrorAction Stop
                    $currentRetryDelay = $InitialRetryDelaySeconds
                    if ($null -ne $commandResponse -and $commandResponse.command) {
                        Write-Log -Message "Befehl erhalten: $($commandResponse.command)"
                        switch ($commandResponse.command) {
                            "START_SCAN" {
                                if ($null -ne $Script:ActiveScanJob) {
                                    Write-Log -Message "Ein Scan läuft bereits. Ignoriere neuen START_SCAN Befehl."
                                } else {
                                    $scanTypeToUse = if ($commandResponse.scan_type -in ("QuickScan", "FullScan")) { $commandResponse.scan_type } else { "FullScan" }
                                    Write-Log -Message "Aktion: Starte neuen Scan (Typ: $scanTypeToUse) als Hintergrund-Job..."
                                    $Script:ScanInitiationTimeUTC = (Get-Date).ToUniversalTime()
                                    $Script:ScanTypeForActiveJob = $scanTypeToUse

                                    # --- WIEDERHERGESTELLTE, FUNKTIONIERENDE JOB-LOGIK ---
                                    $Script:ActiveScanJob = Start-Job -ScriptBlock { 
                                        param($st) 
                                        try { 
                                            Start-MpScan -ScanType $st -ErrorAction Stop 
                                        } catch { 
                                            # Diese Fehlerbehandlung ist entscheidend, um Fehler aus dem Job zurückzugeben
                                            Write-Error "Fehler in Start-MpScan im Job: $($_.Exception.Message)"; return $_
                                        }
                                    } -ArgumentList $scanTypeToUse
                                    
                                    Write-Log -Message "Scan als Job gestartet mit ID: $($Script:ActiveScanJob.Id)."
                                }
                            }
                            "UPDATE_CLIENT" {
                                if ($null -ne $Script:ActiveScanJob) {
                                    Write-Log -Message "Ein Scan läuft derzeit. Ignoriere UPDATE_CLIENT bis zum Abschluss."
                                } else {
                                    Write-Log -Message "Aktion: Führe Client-Update durch..."
                                    try {
                                        if ($null -ne $commandResponse.payload) {
                                            $payloadObj = $commandResponse.payload | ConvertFrom-Json
                                            $repoUrl = if ($payloadObj.repo_url) { $payloadObj.repo_url.TrimEnd('/') } else { "https://github.com/BitWuehler/ScanOp" }
                                            $version = if ($payloadObj.version) { $payloadObj.version } else { "main" }
                                            
                                            Write-Log -Message "Update-Ziel: Repo=$repoUrl, Version=$version"
                                            
                                            $installerUrl = "$repoUrl/raw/$version/client/install.ps1"
                                            $installerPath = Join-Path -Path $ScriptDir -ChildPath "install_update.ps1"
                                            
                                            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
                                            
                                            Write-Log -Message "Installer heruntergeladen. Starte Update-Prozess im Hintergrund und beende mich."
                                            
                                            $startArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installerPath`" -RepoUrl `"$repoUrl`" -Version `"$version`" -IsUnattendedUpdate"
                                            Start-Process -FilePath "powershell.exe" -ArgumentList $startArgs -Verb RunAs
                                            
                                            Exit 0
                                        } else {
                                            Write-Log -Level ERROR -Message "UPDATE_CLIENT Befehl ohne Payload erhalten."
                                        }
                                    } catch {
                                        Write-Log -Level ERROR -Message "Fehler beim Update: $($_.Exception.Message)"
                                    }
                                }
                            }
                            default { Write-Log -Level WARN -Message "Unbekannter Befehl: $($commandResponse.command)" }
                        }
                    } else { Write-Log -Message "Kein Befehl vom Server." }
                } catch { Write-Log -Level ERROR -Message "Netzwerkfehler beim Abrufen von Befehlen: $($_.Exception.Message)"; $networkOperationSuccess = $false }
            }

            # --- 3. WARTEZEIT ---
            if (-not $networkOperationSuccess) {
                Write-Log -Level WARN -Message "Netzwerkproblem erkannt. NÃ¤chster Versuch in $currentRetryDelay Sekunden."
                Start-Sleep -Seconds $currentRetryDelay
                $currentRetryDelay = [math]::Min($currentRetryDelay * 2, $MaxRetryDelaySeconds)
            } else {
                $Global:FatalErrorCount = 0
                Write-Log -Message "Warte $PollingIntervalSeconds Sekunden bis zum nÃ¤chsten Zyklus..."
                Start-Sleep -Seconds $PollingIntervalSeconds
            }
        } # Ende innere while
    } catch {
        $Global:FatalErrorCount++
        Write-Log -Level ERROR -Message "FATALER FEHLER in der Hauptlogik: $($_.Exception.ToString()). Fehleranzahl: $Global:FatalErrorCount/5"
        
        if ($Global:FatalErrorCount -ge 5) {
            Write-Log -Level ERROR -Message "Zu viele aufeinanderfolgende Fehler! Versuche automatische Selbstheilung (Update)..."
            try {
                $repoUrl = if ($Config.GitHubRepoUrl) { $Config.GitHubRepoUrl.TrimEnd('/') } else { "https://github.com/BitWuehler/ScanOp" }
                $version = if ($Config.GitHubVersion) { $Config.GitHubVersion } else { "main" }
                $installerUrl = "$repoUrl/raw/$version/client/install.ps1"
                $installerPath = Join-Path -Path $ScriptDir -ChildPath "install_update.ps1"
                Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
                $startArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installerPath`" -RepoUrl `"$repoUrl`" -Version `"$version`" -IsUnattendedUpdate"
                Start-Process -FilePath "powershell.exe" -ArgumentList $startArgs -Verb RunAs
                Exit 0
            } catch {
                Write-Log -Level ERROR -Message "Selbstheilung fehlgeschlagen: $($_.Exception.Message)"
            }
        }
        
        Write-Log -Message "Das Skript wird in 60 Sekunden versuchen, neu zu starten."
        Start-Sleep -Seconds 60
    } finally {
        if ($null -ne $Script:ActiveScanJob) {
            Write-Log -Level WARN -Message "Skriptzyklus wird beendet. Stoppe sicherheitshalber laufenden Scan-Job (ID $($Script:ActiveScanJob.Id))."
            Stop-Job -Job $Script:ActiveScanJob -Force; Remove-Job -Job $Script:ActiveScanJob -Force
        }
        Write-Log -Message "================== Skript-Zyklus beendet =================="
    }
} # Ende Ã¤uÃŸere while
