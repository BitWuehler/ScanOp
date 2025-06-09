<#
.SYNOPSIS
    Client-Skript zum Pollen von Befehlen vom ScanOp-Server und Ausführen von Aktionen.
.DESCRIPTION
    Dieses Skript liest eine Konfiguration, pollt periodisch einen Server-API-Endpunkt
    und führt basierend auf den empfangenen Befehlen Aktionen aus. Ein Virenscan wird als 
    Hintergrund-Job gestartet, sodass das Polling weiterlaufen kann. Das Ergebnis wird
    gemeldet, sobald der Scan abgeschlossen ist.
    BENÖTIGT ADMINISTRATORBERECHTIGUNGEN für Start-MpScan und Get-WinEvent.
#>

# --- Konfiguration und Initialisierung ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "client_config.json"
$LastReportTimeFilePath = Join-Path -Path $ScriptDir -ChildPath "last_report_time.txt"

Write-Host "Lese Konfiguration von: $ConfigFilePath"

if (-not (Test-Path $ConfigFilePath)) {
    Write-Error "Konfigurationsdatei nicht gefunden: $ConfigFilePath"; exit 1
}
try {
    $Config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Error "Fehler beim Lesen oder Parsen der Konfigurationsdatei '$ConfigFilePath': $($_.Exception.Message)"; exit 1
}

$AliasName = $Config.AliasName
$ServerBaseUrl = $Config.ServerBaseUrl
$ApiKey = $Config.ApiKey 
$PollingIntervalSeconds = $Config.PollingIntervalSeconds
$InterimCheckIntervalMinutes = $Config.InterimCheckIntervalMinutes 

if (-not $ApiKey) {
    Write-Error "Unvollständige Konfiguration: ApiKey ist erforderlich."; exit 1
}
if (-not $AliasName -or -not $ServerBaseUrl -or -not $PollingIntervalSeconds) {
    Write-Error "Unvollständige Konfiguration: AliasName, ServerBaseUrl, PollingIntervalSeconds sind erforderlich."; exit 1
}
if (-not $InterimCheckIntervalMinutes) {
    Write-Warning "Kein 'InterimCheckIntervalMinutes' in Config gefunden. Setze auf 60 Minuten."
    $InterimCheckIntervalMinutes = 60
}

# --- Globale/Script-Variablen für die Zustandsverwaltung ---
$Script:ActiveScanJob = $null
$Script:ScanInitiationTimeUTC = $null
$Script:ScanTypeForActiveJob = $null

$Global:LastSuccessfulReportTimeUTC = $null
if (Test-Path $LastReportTimeFilePath) {
    try {
        $loadedTimeRaw = Get-Content -Path $LastReportTimeFilePath -Raw -ErrorAction Stop
        $Global:LastSuccessfulReportTimeUTC = ([datetime]($loadedTimeRaw | ConvertFrom-Json)).ToUniversalTime()
        if ($Global:LastSuccessfulReportTimeUTC) { Write-Host "Letzte erfolgreiche Report-Zeit geladen: $($Global:LastSuccessfulReportTimeUTC.ToLocalTime())" }
    } catch { Write-Warning "Fehler beim Laden von '$LastReportTimeFilePath': $($_.Exception.Message)." }
}
if ($null -eq $Global:LastSuccessfulReportTimeUTC) {
    Write-Host "Keine gültige letzte Report-Zeit gefunden. Setze auf Startdatum für Event-Suche."
    $Global:LastSuccessfulReportTimeUTC = (Get-Date "1970-01-01").ToUniversalTime() 
}
$Global:LastInterimCheckTimeUTC = (Get-Date).ToUniversalTime()

Write-Host "Client gestartet für Alias: $AliasName"; Write-Host "Server URL: $ServerBaseUrl"
Write-Host "Polling Intervall: $PollingIntervalSeconds Sekunden"

$CommandUrl = "$ServerBaseUrl/clientcommands/$AliasName"; $ReportUrl = "$ServerBaseUrl/scanreports/"

# --- Hilfsfunktionen (unverändert, daher gekürzt zur Übersicht) ---
# ... (Funktionen Send-ScanReport, Get-SimplifiedEventInfo, ConvertFrom-DefenderEvent, Get-InterimDefenderThreatEvents bleiben unverändert) ...
# HINWEIS: Aus Platzgründen werden die unveränderten Hilfsfunktionen hier nicht wiederholt. 
# Sie sollten aus dem Originalskript übernommen werden. Ich füge sie hier aber komplett ein, damit die Datei lauffähig ist.

function Send-ScanReport {
    param(
        [Parameter(Mandatory=$true)][string]$ScanTime,
        [Parameter(Mandatory=$true)][string]$ScanType,
        [Parameter(Mandatory=$true)][string]$ScanResultMessage,
        [Parameter(Mandatory=$true)][bool]$ThreatsFound,
        [string]$ThreatDetails = $null
    )
    Write-Host "Sende Scan-Bericht an: $ReportUrl"
    if ([string]::IsNullOrWhiteSpace($ScanTime)) { $ScanTime = (Get-Date "1970-01-01").ToUniversalTime().ToString("o") }
    if ([string]::IsNullOrWhiteSpace($ScanType)) { $ScanType = "Unbekannt" }
    if ([string]::IsNullOrWhiteSpace($ScanResultMessage)) { $ScanResultMessage = "Keine Meldung" }

    $CleanResultMessage = $ScanResultMessage -replace '[\x00-\x1F\x7F]', '' 
    $CleanThreatDetails = if ($ThreatDetails) { $ThreatDetails -replace '[\x00-\x1F\x7F]', '' } else { $null }

    $payloadContent = @{
        laptop_identifier = $AliasName; client_scan_time = $ScanTime; scan_type = $ScanType;
        scan_result_message = $CleanResultMessage; threats_found = $ThreatsFound
    }
    if ($null -ne $CleanThreatDetails -and (-not [string]::IsNullOrWhiteSpace($CleanThreatDetails))) { $payloadContent.threat_details = $CleanThreatDetails }
    else { $payloadContent.threat_details = $null }
    
    $payloadBodyJson = $payloadContent | ConvertTo-Json -Depth 5 -Compress
    
    $utf8Encoding = [System.Text.Encoding]::UTF8
    $payloadBytes = $utf8Encoding.GetBytes($payloadBodyJson)

    $requestHeaders = @{ 
        "Content-Type" = "application/json; charset=utf-8";
        "X-API-Key"    = $ApiKey
    }
    
    $ErrorActionPreferenceBackup = $ErrorActionPreference; $ErrorActionPreference = "Stop"
    try {
        Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payloadBytes -Headers $requestHeaders -TimeoutSec 120 
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan-Bericht erfolgreich an Server gesendet."
        
        $Global:LastSuccessfulReportTimeUTC = (Get-Date).ToUniversalTime()
        try {
            ($Global:LastSuccessfulReportTimeUTC.ToString("o") | ConvertTo-Json -Compress) | Set-Content -Path $LastReportTimeFilePath -Force -Encoding UTF8
            Write-Host "Letzte erfolgreiche Report-Zeit gespeichert: $($Global:LastSuccessfulReportTimeUTC.ToLocalTime()) ($($Global:LastSuccessfulReportTimeUTC.ToString("o")) UTC)"
        } catch { Write-Warning "Fehler beim Speichern von '$LastReportTimeFilePath': $($_.Exception.Message)" }
    } catch {
        $CaughtException = $_; Write-Error "FEHLER Send-ScanReport: $($CaughtException.ToString())" 
        if ($CaughtException.Exception -is [System.Net.WebException] -and $null -ne $CaughtException.Exception.Response) {
            $webEx = $CaughtException.Exception
            $httpResponse = $webEx.Response
            $actualHttpStatusCode = [int]$httpResponse.StatusCode
            Write-Error "  HTTP Status: $actualHttpStatusCode"
            try { 
                $responseStream = $httpResponse.GetResponseStream()
                $streamReader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8) 
                $errorBodyContent = $streamReader.ReadToEnd()
                $streamReader.Close(); $responseStream.Close() 
                Write-Error "  Fehler-Body Server: $errorBodyContent" 
            } catch { Write-Error "  Fehler beim Lesen des Fehler-Bodys: $($_.Exception.Message)" }
        }
    } finally {
        $ErrorActionPreference = $ErrorActionPreferenceBackup
    }
}

function Get-SimplifiedEventInfo {
    param(
        [Parameter(Mandatory=$true)] $EventMessageInput, 
        [Parameter(Mandatory=$true)] $EventId
    )
    $CleanedEventMessage = ($EventMessageInput -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '').Trim()
    $simplified = @{ Message = "Event ${EventId}: " + ($CleanedEventMessage -split '\r?\n')[0]; Details = $null }

    if ($CleanedEventMessage -match "Name: (.*?)\s*(ID:.*?)?Pfad: (.*?)\s*(Aktion: (.*?)\s*)?Erkennungsquelle: (.*?)\s*(Benutzer:.*?)?$") {
        $name = $Matches[1].Trim()
        $path = $Matches[3].Trim()
        $action = if ($Matches[5]) { $Matches[5].Trim() } else { "Unbekannt" }
        $source = $Matches[6].Trim()
        $simplified.Message = "Bedrohung: $($name -replace '[\x00-\x1F\x7F]','') ($($source -replace '[\x00-\x1F\x7F]',''))"
        $simplified.Details = "Pfad: $($path -replace '[\x00-\x1F\x7F]',''), Aktion: $($action -replace '[\x00-\x1F\x7F]','')"
    } elseif ($CleanedEventMessage -match "Scan (erfolgreich beendet|abgebrochen|Fehler während Scan)") {
        $status = $Matches[1]
        $simplified.Message = "Scan-Status: $status"
        if ($CleanedEventMessage -match "Bedrohungen gefunden") { $simplified.Message += " (Bedrohungen gefunden)"}
    }
    $simplified.Message = ($simplified.Message -replace '[\x00-\x1F\x7F]','').Trim()
    if ($simplified.Details) {
        $simplified.Details = ($simplified.Details -replace '[\x00-\x1F\x7F]','').Trim()
    }
    return $simplified
}

function ConvertFrom-DefenderEvent {
    param( [Parameter(Mandatory=$true)] $Event )
    $eventTimeUTC = $Event.TimeCreated.ToUniversalTime().ToString("o") 
    $simplifiedInfo = Get-SimplifiedEventInfo -EventMessage $Event.Message -EventId $Event.Id
    
    $result = @{ 
        ScanTime = $eventTimeUTC
        ResultMessage = $simplifiedInfo.Message
        ThreatsFound = $false 
        ThreatDetails = $simplifiedInfo.Details 
    }
    
    switch ($Event.Id) {
        1001 { $result.ThreatsFound = $false } 
        1002 { $result.ThreatsFound = $true  } 
        1005 {} 
        1116 { $result.ThreatsFound = $true }
        1117 { $result.ThreatsFound = $true }
        1118 { $result.ThreatsFound = $true }
        1119 {}
        default { Write-Warning "Unbekannte Event ID $($Event.Id) für ConvertFrom-DefenderEvent." }
    }
    if (-not $result.ThreatDetails -and $result.ThreatsFound -and $Event.Message -match "Name: ") {
        $result.ThreatDetails = "Details: " + (($Event.Message -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '').Trim() -split '\r?\n')[0..2] -join " " 
    }
    return $result
}

function Get-InterimDefenderThreatEvents {
    param(
        [Parameter(Mandatory=$true)]
        [datetime]$SinceTimeUTCtoQuery
    )
    Write-Host "Suche nach Defender-Bedrohungs-Events seit $($SinceTimeUTCtoQuery.ToLocalTime()) ($($SinceTimeUTCtoQuery.ToString("o")) UTC)..."
    $relevantEventIds = @(1002, 1005, 1116, 1117, 1118, 1119) 
    try {
        $events = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 200 -ErrorAction SilentlyContinue |
            Where-Object { ($_.TimeCreated.ToUniversalTime() -gt $SinceTimeUTCtoQuery) -and ($_.Id -in $relevantEventIds) } |
            Sort-Object TimeCreated
        if ($events) { Write-Host "> $($events.Count) relevante 'Zwischendurch'-Events gefunden." }
        else { Write-Host "> Keine relevanten 'Zwischendurch'-Defender-Events gefunden." }
        return $events
    } catch { Write-Warning "Fehler beim Abrufen von 'Zwischendurch'-Events: $($_.Exception.Message)"; return $null }
}

# --- Haupt-Polling-Schleife ---
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starte Haupt-Polling-Schleife..."
try {
    while ($true) {
        $currentLoopTimeUTC = (Get-Date).ToUniversalTime()

        # ######################################################################
        # ### KORRIGIERTER BEREICH START: Zustandsprüfung des Scan-Jobs      ###
        # ######################################################################

        # ZUERST: Prüfen, ob ein Scan-Job abgeschlossen ist, bevor wir neue Befehle holen.
        if ($null -ne $Script:ActiveScanJob) {
            if ($Script:ActiveScanJob.State -in @('Completed', 'Failed', 'Stopped')) {
                Write-Host "Hintergrund-Scan-Job (ID $($Script:ActiveScanJob.Id)) ist beendet mit Status: $($Script:ActiveScanJob.State)."
                
                # --- Ergebnisse des abgeschlossenen Scans sammeln und melden ---
                $scanJobResult = Receive-Job -Job $Script:ActiveScanJob -Keep
                
                $scanEndTimeUTC = (Get-Date).ToUniversalTime()
                $scanStartTimeForQuery = $Script:ScanInitiationTimeUTC.AddMinutes(-2)
                
                $reportScanTime = $Script:ScanInitiationTimeUTC.ToString("o")
                $reportResultMessageAggregator = [System.Text.StringBuilder]::new()
                $reportThreatDetailsAggregator = [System.Text.StringBuilder]::new()
                $reportThreatsFound = $false

                [void]$reportResultMessageAggregator.AppendLine("Scan ($($Script:ScanTypeForActiveJob)) initiiert $($reportScanTime) wurde beendet.")
                [void]$reportResultMessageAggregator.AppendLine("Job-Status: $($Script:ActiveScanJob.State).")

                if ($Script:ActiveScanJob.State -ne 'Completed' -or ($scanJobResult -is [System.Management.Automation.ErrorRecord])) {
                    $reportThreatsFound = $true
                    [void]$reportResultMessageAggregator.AppendLine("Scan-Job meldete Fehler.")
                    [void]$reportThreatDetailsAggregator.AppendLine("Job-Fehler: $($scanJobResult | Out-String)")
                }

                # Suche nach relevanten Events im Zeitraum des Scans
                $finalScanEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 20 |
                    Where-Object { ($_.Id -in (1001,1002,1005)) -and ($_.TimeCreated.ToUniversalTime() -ge $scanStartTimeForQuery) } | 
                    Sort-Object TimeCreated -Descending | Select-Object -First 1

                if ($finalScanEvent) {
                    $interpretedScanEndResult = ConvertFrom-DefenderEvent -Event $finalScanEvent
                    [void]$reportResultMessageAggregator.AppendLine("Scan-Abschluss-Event (ID $($finalScanEvent.Id)): $($interpretedScanEndResult.ResultMessage)")
                    if ($interpretedScanEndResult.ThreatsFound) { $reportThreatsFound = $true }
                    if ($interpretedScanEndResult.ThreatDetails) { [void]$reportThreatDetailsAggregator.AppendLine($interpretedScanEndResult.ThreatDetails) }
                } else {
                    [void]$reportResultMessageAggregator.AppendLine("Kein offizielles Scan-Abschluss-Event (1001/1002/1005) gefunden.")
                }
                
                $threatEventsDuringScan = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 50 |
                    Where-Object { ($_.Id -in (1116,1117,1118)) -and ($_.TimeCreated.ToUniversalTime() -ge $scanStartTimeForQuery) -and ($_.TimeCreated.ToUniversalTime() -le $scanEndTimeUTC) } |
                    Sort-Object TimeCreated

                if ($threatEventsDuringScan) {
                    [void]$reportResultMessageAggregator.AppendLine("Zusätzliche Bedrohungs-Events im Scan-Zeitraum:")
                    foreach ($thrEvt in $threatEventsDuringScan) {
                        $interpretedThreat = ConvertFrom-DefenderEvent -Event $thrEvt
                        [void]$reportResultMessageAggregator.AppendLine("- Event ID $($thrEvt.Id): $($interpretedThreat.ResultMessage)")
                        if ($interpretedThreat.ThreatsFound) { $reportThreatsFound = $true } 
                        if ($interpretedThreat.ThreatDetails) { [void]$reportThreatDetailsAggregator.AppendLine($interpretedThreat.ThreatDetails) }
                    }
                }

                # Bericht senden
                Send-ScanReport -ScanTime $reportScanTime -ScanType $Script:ScanTypeForActiveJob `
                    -ScanResultMessage $reportResultMessageAggregator.ToString().Trim() `
                    -ThreatsFound $reportThreatsFound `
                    -ThreatDetails $reportThreatDetailsAggregator.ToString().Trim()
                
                # Job aufräumen und Zustand zurücksetzen
                Write-Host "Entferne abgeschlossenen Job und setze Zustand zurück."
                Remove-Job -Job $Script:ActiveScanJob -Force
                $Script:ActiveScanJob = $null
                $Script:ScanInitiationTimeUTC = $null
                $Script:ScanTypeForActiveJob = $null
            
            } else {
                # Job läuft noch, nichts tun, außer eine Meldung ausgeben
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Ein Scan (Typ: $($Script:ScanTypeForActiveJob)) läuft noch im Hintergrund (Job-ID: $($Script:ActiveScanJob.Id)). Polling wird fortgesetzt..."
            }
        }
        
        # --- Interim-Events werden in jeder Schleife geprüft, egal ob ein Scan läuft ---
        # Diese Logik kann hier bleiben, wird aber nur berichtet, wenn KEIN Befehl vom Server kommt.
        $interimEventsFoundAndProcessed = $false
        $interimThreatDetailsAggregated = [System.Collections.Generic.List[string]]::new()
        $interimEventsSummaryMessages = [System.Collections.Generic.List[string]]::new()
        # ... Logik für Interim-Events bleibt hier ... (Ich lasse sie der Vollständigkeit halber drin)
        if ($Global:LastSuccessfulReportTimeUTC) {
            $collectedInterimEvents = Get-InterimDefenderThreatEvents -SinceTimeUTCtoQuery $Global:LastSuccessfulReportTimeUTC
            if ($collectedInterimEvents) {
                $interimEventsFoundAndProcessed = $true
                #... (Rest der Interim-Verarbeitung) ...
                $eventsToProcess = $collectedInterimEvents | Sort-Object TimeCreated -Descending
                $maxInterimEventsToReport = 5
                for ($i = 0; $i -lt $eventsToProcess.Count; $i++) {
                    $evt = $eventsToProcess[$i]; $interpretedEvt = ConvertFrom-DefenderEvent -Event $evt
                    if ($i -lt $maxInterimEventsToReport) {
                        $summaryMsg = "Interim (ID $($evt.Id) @ $($evt.TimeCreated.ToLocalTime())): $($interpretedEvt.ResultMessage)"
                        $interimEventsSummaryMessages.Add($summaryMsg)
                        if ($interpretedEvt.ThreatsFound -and $interpretedEvt.ThreatDetails) { $interimThreatDetailsAggregated.Add($interpretedEvt.ThreatDetails) }
                    } elseif ($i -eq $maxInterimEventsToReport) { $interimEventsSummaryMessages.Add("... und $($eventsToProcess.Count - $maxInterimEventsToReport) weitere."); break }
                }
            }
        }

        # DANN: Nur wenn kein Scan aktiv ist, neue Befehle abfragen und verarbeiten
        if ($null -eq $Script:ActiveScanJob) {
            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Frage Befehle vom Server ab: $CommandUrl"
            $commandResponse = $null
            try {
                $commandRequestHeaders = @{ "X-API-Key" = $ApiKey }
                $commandResponse = Invoke-RestMethod -Uri $CommandUrl -Method Get -Headers $commandRequestHeaders -TimeoutSec 20 -ErrorAction Stop 
            } catch {
                # Fehlerbehandlung für Befehlsabruf bleibt unverändert...
                $CaughtCmdException = $_; $apiErrorMessage = "Fehler Invoke-RestMethod: $($CaughtCmdException.Exception.Message)"
                # ...
                Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler Befehlsabruf: $apiErrorMessage"
            }

            if ($null -ne $commandResponse -and $commandResponse.command) {
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Befehl erhalten: $($commandResponse.command)"
                switch ($commandResponse.command) {
                    "START_SCAN" {
                        $scanTypeFromServer = $commandResponse.scan_type; $scanTypeToUse = "FullScan" 
                        if ($scanTypeFromServer -in ("QuickScan", "FullScan")) { $scanTypeToUse = $scanTypeFromServer }
                        
                        Write-Host "Aktion: Starte neuen Scan (Typ: $scanTypeToUse) als Hintergrund-Job..."
                        $Script:ScanInitiationTimeUTC = (Get-Date).ToUniversalTime()
                        $Script:ScanTypeForActiveJob = $scanTypeToUse

                        # Starte den Scan als Job und speichere das Job-Objekt
                        $Script:ActiveScanJob = Start-Job -ScriptBlock { 
                            param($st) 
                            try {
                                Start-MpScan -ScanType $st -ErrorAction Stop
                            } catch {
                                # Fehler innerhalb des Jobs als ErrorRecord zurückgeben
                                Write-Error "Fehler in Start-MpScan im Job: $($_.Exception.Message)"
                                return $_ # Gibt das ErrorRecord-Objekt zurück
                            }
                        } -ArgumentList $scanTypeToUse
                        
                        Write-Host "Scan als Job gestartet mit ID: $($Script:ActiveScanJob.Id). Das Skript pollt weiter."
                    }
                    default { Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unbekannter Befehl: $($commandResponse.command)" }
                }
            } elseif ($interimEventsFoundAndProcessed) {
                # Nur wenn kein Befehl kam, aber Interim-Events da sind, diese melden
                 Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Kein Server-Befehl, aber Zwischendurch-Ereignisse gefunden. Sende Bericht."
                 $reportTime = (Get-Date).ToUniversalTime().ToString("o")
                 Send-ScanReport -ScanTime $reportTime -ScanType "InterimRealtimeEvent" `
                     -ScanResultMessage ($interimEventsSummaryMessages -join ' | ') `
                     -ThreatsFound $true `
                     -ThreatDetails ($interimThreatDetailsAggregated -join ' | ')
            } else {
                 Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Kein Befehl vom Server und keine neuen Interim-Events."
            }
        }
        
        # ######################################################################
        # ### KORRIGIERTER BEREICH ENDE                                      ###
        # ######################################################################

        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Warte $PollingIntervalSeconds Sekunden bis zum nächsten Zyklus..."
        Start-Sleep -Seconds $PollingIntervalSeconds
    } # Ende while
} catch { 
    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unerwarteter Fehler Hauptschleife: $($_.Exception.ToString()). Skript beendet."; exit 1 
} finally {
    # Aufräumen, falls das Skript beendet wird, während ein Job läuft
    if ($null -ne $Script:ActiveScanJob) {
        Write-Warning "Skript wird beendet. Stoppe laufenden Scan-Job (ID $($Script:ActiveScanJob.Id))."
        Stop-Job -Job $Script:ActiveScanJob -Force
        Remove-Job -Job $Script:ActiveScanJob -Force
    }
}