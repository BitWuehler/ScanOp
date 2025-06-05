<#
.SYNOPSIS
    Client-Skript zum Pollen von Befehlen vom ScanOp-Server und Ausführen von Aktionen.
.DESCRIPTION
    Dieses Skript liest eine Konfiguration, pollt periodisch einen Server-API-Endpunkt
    und führt basierend auf den empfangenen Befehlen Aktionen aus (z.B. Starten eines Virenscans
    und Melden des Ergebnisses mit interpretierten Defender-Statuscodes, inklusive "Zwischendurch"-Funde).
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

if (-not $AliasName -or -not $ServerBaseUrl -or -not $PollingIntervalSeconds) {
    Write-Error "Unvollständige Konfiguration: AliasName, ServerBaseUrl, PollingIntervalSeconds sind erforderlich."; exit 1
}
if (-not $InterimCheckIntervalMinutes) {
    Write-Warning "Kein 'InterimCheckIntervalMinutes' in Config gefunden. Setze auf 60 Minuten."
    $InterimCheckIntervalMinutes = 60
}

$Global:LastSuccessfulReportTimeUTC = $null
if (Test-Path $LastReportTimeFilePath) {
    try {
        $loadedTimeRaw = Get-Content -Path $LastReportTimeFilePath -Raw -ErrorAction Stop
        $loadedTimeJson = $loadedTimeRaw | ConvertFrom-Json -ErrorAction Stop
        if ($loadedTimeJson -is [string]) {
            try { $Global:LastSuccessfulReportTimeUTC = [datetime]::ParseExact($loadedTimeJson, "o", $null).ToUniversalTime() }
            catch { Write-Warning "Konnte String '$loadedTimeJson' nicht mit ParseExact('o') parsen."; try { $Global:LastSuccessfulReportTimeUTC = ([datetime]$loadedTimeJson).ToUniversalTime() } catch {}}
        }
        if ($Global:LastSuccessfulReportTimeUTC) { Write-Host "Letzte erfolgreiche Report-Zeit geladen: $($Global:LastSuccessfulReportTimeUTC.ToLocalTime()) ($($Global:LastSuccessfulReportTimeUTC.ToString("o")) UTC)"}
        else { Write-Warning "Konnte Zeitstempel nicht korrekt als DateTime parsen aus '$LastReportTimeFilePath' (Inhalt: '$loadedTimeRaw')." }
    } catch { Write-Warning "Fehler beim Laden/Parsen von '$LastReportTimeFilePath': $($_.Exception.Message)."; $Global:LastSuccessfulReportTimeUTC = $null }
} 
if ($null -eq $Global:LastSuccessfulReportTimeUTC) {
    Write-Host "Keine gültige '$LastReportTimeFilePath' gefunden/geladen. Setze auf Startdatum für Event-Suche."
    $Global:LastSuccessfulReportTimeUTC = (Get-Date "1970-01-01").ToUniversalTime() 
}
$Global:LastInterimCheckTimeUTC = (Get-Date).ToUniversalTime() 

Write-Host "Client gestartet für Alias: $AliasName"; Write-Host "Server URL: $ServerBaseUrl"
Write-Host "Polling Intervall: $PollingIntervalSeconds Sekunden"; Write-Host "Intervall für Zwischen-Event-Prüfung: $InterimCheckIntervalMinutes Minuten"

$CommandUrl = "$ServerBaseUrl/clientcommands/$AliasName"; $ReportUrl = "$ServerBaseUrl/scanreports/"

# --- Hilfsfunktionen ---
function Send-ScanReport {
    param(
        [Parameter(Mandatory=$true)][string]$ScanTime,
        [Parameter(Mandatory=$true)][string]$ScanType,
        [Parameter(Mandatory=$true)][string]$ScanResultMessage,
        [Parameter(Mandatory=$true)][bool]$ThreatsFound,
        [string]$ThreatDetails = $null
    )
    Write-Host "DEBUG: Betrete Send-ScanReport Funktion."
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
    Write-Host "DEBUG: Erstellter Payload für Report (Länge: $($payloadBodyJson.Length)): $payloadBodyJson" 

    $utf8Encoding = [System.Text.Encoding]::UTF8
    $payloadBytes = $utf8Encoding.GetBytes($payloadBodyJson)

    $requestHeaders = @{ "Content-Type" = "application/json; charset=utf-8" }
    # if ($ApiKey) { $requestHeaders["X-API-Key"] = $ApiKey } 
    
    $ErrorActionPreferenceBackup = $ErrorActionPreference; $ErrorActionPreference = "Stop"
    $responseVariable = $null; $actualHttpStatusCode = 0
    try {
        Write-Host "DEBUG: Vor Invoke-RestMethod für Report-Senden (mit UTF-8 Bytes)..."
        $responseVariable = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payloadBytes -Headers $requestHeaders -TimeoutSec 120 
        $actualHttpStatusCode = 201 
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan-Bericht erfolgreich an Server gesendet. (Status: $actualHttpStatusCode angenommen)"
        if ($responseVariable) { Write-Host "Server Antwort (Erfolg): $($responseVariable | ConvertTo-Json -Depth 3 -Compress)" }
        
        $Global:LastSuccessfulReportTimeUTC = (Get-Date).ToUniversalTime()
        try {
            ($Global:LastSuccessfulReportTimeUTC.ToString("o") | ConvertTo-Json -Compress) | Set-Content -Path $LastReportTimeFilePath -Force -Encoding UTF8
            Write-Host "Letzte erfolgreiche Report-Zeit gespeichert: $($Global:LastSuccessfulReportTimeUTC.ToLocalTime()) ($($Global:LastSuccessfulReportTimeUTC.ToString("o")) UTC)"
        } catch { Write-Warning "Fehler beim Speichern von '$LastReportTimeFilePath': $($_.Exception.Message)" }
    } catch {
        $CaughtException = $_; Write-Error "FEHLER Send-ScanReport: $($CaughtException.ToString())" 
        if ($CaughtException.Exception) {
            Write-Error "  Exception Typ: $($CaughtException.Exception.GetType().FullName)"
            Write-Error "  Exception Nachricht: $($CaughtException.Exception.Message)"
            if ($CaughtException.Exception.InnerException) {
                Write-Error "  INNERE Exception Typ: $($CaughtException.Exception.InnerException.GetType().FullName)"
                Write-Error "  INNERE Exception Nachricht: $($CaughtException.Exception.InnerException.Message)"
            }
            if ($CaughtException.Exception -is [System.Net.WebException]) {
                $webEx = $CaughtException.Exception; Write-Error "  Status WebException: $($webEx.Status)"
                if ($null -ne $webEx.Response) {
                    $httpResponse = $webEx.Response; $actualHttpStatusCode = [int]$httpResponse.StatusCode
                    Write-Error "  HTTP Status: $actualHttpStatusCode"; $errorBodyContent = "<Fehler Body>"
                    try { 
                        $responseStream = $httpResponse.GetResponseStream()
                        if ($responseStream.CanRead){ 
                            $streamReader = New-Object System.IO.StreamReader($responseStream, [System.Text.Encoding]::UTF8) 
                            $errorBodyContent = $streamReader.ReadToEnd()
                            $streamReader.Close() 
                        } else { $errorBodyContent = "<Stream nicht lesbar>" }
                        $responseStream.Close() 
                    } catch { $errorBodyContent = "<Ex Body: $($_.Exception.Message)>" }
                    Write-Error "  Fehler-Body Server: $errorBodyContent" 
                } else { Write-Warning "  WebException ohne Response-Objekt." }
            }
        }
    } finally {
        $ErrorActionPreference = $ErrorActionPreferenceBackup
        Write-Host "DEBUG: Send-ScanReport beendet. HTTP-Status: $actualHttpStatusCode"
    }
}

function Get-SimplifiedEventInfo {
    param(
        [Parameter(Mandatory=$true)] $EventMessageInput, 
        [Parameter(Mandatory=$true)] $EventId
    )
    $CleanedEventMessage = ($EventMessageInput -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '').Trim()
    # Korrigierter String-Interpolation
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
        # Write-Host "DEBUG_LOOP: Schleifenanfang - $($currentLoopTimeUTC.ToString("o"))" # Kann bei Bedarf einkommentiert werden

        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Frage Befehle vom Server ab: $CommandUrl"
        $commandResponse = $null; $commandErrorOccurred = $false; $commandActualHttpStatusCode = 0
        try {
            $commandResponse = Invoke-RestMethod -Uri $CommandUrl -Method Get -TimeoutSec 20 -ErrorAction Stop 
            $commandActualHttpStatusCode = 200; $commandErrorOccurred = $false
        } catch {
            $commandErrorOccurred = $true; $CaughtCmdException = $_
            $apiErrorMessage = "Fehler Invoke-RestMethod (Befehlsabfrage): $($CaughtCmdException.ToString())"
            if ($CaughtCmdException.Exception -is [System.Net.WebException] -and $null -ne $CaughtCmdException.Exception.Response) {
                $httpResponse = $CaughtCmdException.Exception.Response; $commandActualHttpStatusCode = [int]$httpResponse.StatusCode
                $errorBodyDetail = ""; try { $errStream = $httpResponse.GetResponseStream(); if ($errStream.CanRead){ $errReader = New-Object System.IO.StreamReader($errStream); $errorBodyDetail = $errReader.ReadToEnd(); $errReader.Close() } else { $errorBodyDetail = "<Stream nicht lesbar>" }; $errStream.Close() } catch { $errorBodyDetail = "<Ex beim Lesen: $($_.Exception.Message)>" }
                $apiErrorMessage = "HTTP Fehler $commandActualHttpStatusCode (Befehlsabfrage). Body: '$errorBodyDetail'. Urspr. Fehler: $($CaughtCmdException.Exception.Message)"
            } 
            if ($commandActualHttpStatusCode -eq 404) { Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FEHLER 404: Laptop '$AliasName' nicht registriert. $apiErrorMessage"; Start-Sleep -Seconds 3600 }
            else { Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler Befehlsabruf (Status $commandActualHttpStatusCode): $apiErrorMessage"; Start-Sleep -Seconds ($PollingIntervalSeconds * 2) }
        } 
        # Write-Host "DEBUG_LOOP: Nach Befehlsabruf" # Kann bei Bedarf einkommentiert werden

        $interimEventsFoundAndProcessed = $false 
        $interimThreatDetailsAggregated = [System.Collections.Generic.List[string]]::new()
        $interimEventsSummaryMessages = [System.Collections.Generic.List[string]]::new()
        $maxInterimEventsToReport = 5 

        if ($Global:LastSuccessfulReportTimeUTC) {
            # Write-Host "DEBUG_LOOP: Vor Get-InterimDefenderThreatEvents" # Kann bei Bedarf einkommentiert werden
            $collectedInterimEvents = Get-InterimDefenderThreatEvents -SinceTimeUTCtoQuery $Global:LastSuccessfulReportTimeUTC
            if ($collectedInterimEvents) {
                $interimEventsFoundAndProcessed = $true 
                Write-Warning "Zwischendurch-Ereignisse seit letztem Report gefunden! Verarbeite..."
                $eventsToProcess = $collectedInterimEvents | Sort-Object TimeCreated -Descending 
                
                for ($i = 0; $i -lt $eventsToProcess.Count; $i++) {
                    $evt = $eventsToProcess[$i]
                    $interpretedEvt = ConvertFrom-DefenderEvent -Event $evt
                    
                    if ($i -lt $maxInterimEventsToReport) {
                        $summaryMsg = "Interim (ID $($evt.Id) @ $($evt.TimeCreated.ToLocalTime())): $($interpretedEvt.ResultMessage)"
                        $interimEventsSummaryMessages.Add($summaryMsg)
                        if ($interpretedEvt.ThreatsFound -and $interpretedEvt.ThreatDetails) {
                            $interimThreatDetailsAggregated.Add($interpretedEvt.ThreatDetails)
                        }
                    } elseif ($i -eq $maxInterimEventsToReport) {
                        $interimEventsSummaryMessages.Add("... und $($eventsToProcess.Count - $maxInterimEventsToReport) weitere Interim-Event(s).")
                        break 
                    }
                }
            }
            # Write-Host "DEBUG_LOOP: Nach Get-InterimDefenderThreatEvents (Processed: $interimEventsFoundAndProcessed)" # Kann bei Bedarf einkommentiert werden
        }

        # Hauptlogik für Befehlsauswertung oder Interim-Report
        if (-not $commandErrorOccurred -and $null -ne $commandResponse) {
            if ($commandResponse.command) {
                # Write-Host "DEBUG_LOOP: Innerhalb if (commandResponse.command)" # Kann bei Bedarf einkommentiert werden
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Befehl: $($commandResponse.command), ScanTyp Server: $($commandResponse.scan_type)"
                switch ($commandResponse.command) {
                    "START_SCAN" {
                        $scanTypeFromServer = $commandResponse.scan_type; $scanTypeToUse = "FullScan" 
                        if ($scanTypeFromServer -in ("QuickScan", "FullScan")) { $scanTypeToUse = $scanTypeFromServer; Write-Host "Verwende Scan-Typ: $scanTypeToUse" }
                        else { Write-Warning "Ungültiger/Kein Scan-Typ '$scanTypeFromServer'. Verwende '$scanTypeToUse'." }
                        
                        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Aktion: Starte Scan (Typ: $scanTypeToUse)..."
                        $scanCommandInitiationTimeUTC = (Get-Date).ToUniversalTime(); $scanJob = $null 
                        try {
                            Write-Host "... Initiiere Scan ($scanTypeToUse) als Job..."
                            $scanJob = Start-Job -ScriptBlock { param($st) Start-MpScan -ScanType $st -ErrorAction Stop } -ArgumentList $scanTypeToUse
                            Write-Host "... Scan ($scanTypeToUse) als Job $($scanJob.Id) gestartet."
                            $scanInProgress = $true; $maxWaitMinutes = if ($scanTypeToUse -eq "QuickScan") { 30 } else { 360 }; $waitIntervalSeconds = 30; $elapsedWaitSeconds = 0
                            Write-Host "... Warte auf Scan-Abschluss (max. $maxWaitMinutes Min)..."
                            while ($scanInProgress -and ($elapsedWaitSeconds -lt ($maxWaitMinutes * 60))) {
                                Start-Sleep -Seconds $waitIntervalSeconds; $elapsedWaitSeconds += $waitIntervalSeconds
                                try { $mpStatus = Get-MpComputerStatus -EA SilentlyContinue; if ($mpStatus) { $scanInProgress = $mpStatus.MpScanInProgress; if (-not $scanInProgress) { Write-Host "... Scan nicht mehr 'in Progress'."; break } } else { if ($scanJob.State -notin ('Running','NotStarted')) {$scanInProgress=$false; Write-Warning "Job nicht aktiv: $($scanJob.State)"; break;}} } catch { Write-Warning "Get-MpComputerStatus Fehler: $($_.Exception.Message)." }
                                Write-Host "... Scan läuft (MpScanInProgress: $scanInProgress, Job: $($scanJob.State))... ca. $($elapsedWaitSeconds/60) Min."
                            }
                            if ($scanInProgress) { Write-Warning "... Scan Max-Wartezeit überschritten."; if ($scanJob.State -eq 'Running') { Stop-Job $scanJob -Force; Write-Warning "Job gestoppt."}}
                            Wait-Job $scanJob -Timeout 10 | Out-Null
                            $jobMessages = Receive-Job $scanJob -Keep; if ($jobMessages) { Write-Host "Job $($scanJob.Id) Meldungen:"; $jobMessages | ForEach-Object { Write-Host "  JOB: $_" }}

                            Write-Host "... Lese Event Log für Scan-Ergebnis und assoziierte Bedrohungen..."
                            Start-Sleep -Seconds 2
                            $scanEndTimeUTC = (Get-Date).ToUniversalTime() 
                            $currentScanEventsQueryStartTime = $scanCommandInitiationTimeUTC.AddMinutes(-2)

                            $reportScanTime = $scanCommandInitiationTimeUTC.ToString("o") 
                            $reportResultMessageAggregator = [System.Text.StringBuilder]::new()
                            $reportThreatDetailsAggregator = [System.Text.StringBuilder]::new()
                            $reportThreatsFound = $false
                            
                            [void]$reportResultMessageAggregator.AppendLine("Scan ($scanTypeToUse) initiiert $reportScanTime.")

                            if ($jobMessages -match "JOB_ERROR") { 
                                [void]$reportResultMessageAggregator.AppendLine("Scan-Job meldete Fehler: " + ($jobMessages -join "; "))
                                $reportThreatsFound = $true 
                                [void]$reportThreatDetailsAggregator.AppendLine("Scan-Job Fehler: " + ($jobMessages -join "; "))
                            }

                            $scanSpecificEventsFound = $false 

                            $finalScanEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 20 |
                                Where-Object { ($_.Id -in (1001,1002,1005,1119)) -and ($_.TimeCreated.ToUniversalTime() -ge $currentScanEventsQueryStartTime) -and ($_.TimeCreated.ToUniversalTime() -le $scanEndTimeUTC) } | 
                                Sort-Object TimeCreated -Descending | Select-Object -First 1

                            if ($finalScanEvent) {
                                $scanSpecificEventsFound = $true
                                $interpretedScanEndResult = ConvertFrom-DefenderEvent -Event $finalScanEvent
                                [void]$reportResultMessageAggregator.AppendLine("Scan-Abschluss-Event (ID $($finalScanEvent.Id)): $($interpretedScanEndResult.ResultMessage)")
                                if ($interpretedScanEndResult.ThreatsFound) { $reportThreatsFound = $true }
                                if ($interpretedScanEndResult.ThreatDetails) { [void]$reportThreatDetailsAggregator.AppendLine($interpretedScanEndResult.ThreatDetails) }
                            } else {
                                [void]$reportResultMessageAggregator.AppendLine("Kein offizielles Scan-Abschluss-Event (1001/1002) gefunden.")
                            }
                            
                            $threatEventsDuringThisScanPeriod = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 50 |
                                Where-Object { ($_.Id -in (1116,1117,1118)) -and ($_.TimeCreated.ToUniversalTime() -ge $currentScanEventsQueryStartTime) -and ($_.TimeCreated.ToUniversalTime() -le $scanEndTimeUTC) } |
                                Sort-Object TimeCreated

                            if ($threatEventsDuringThisScanPeriod) {
                                $scanSpecificEventsFound = $true
                                [void]$reportResultMessageAggregator.AppendLine("Zusätzliche Bedrohungs-Events im Scan-Zeitraum:")
                                foreach ($thrEvt in $threatEventsDuringThisScanPeriod) {
                                    $interpretedThreat = ConvertFrom-DefenderEvent -Event $thrEvt
                                    [void]$reportResultMessageAggregator.AppendLine("- Event ID $($thrEvt.Id) @ $($thrEvt.TimeCreated.ToLocalTime()): $($interpretedThreat.ResultMessage)")
                                    if ($interpretedThreat.ThreatsFound) { $reportThreatsFound = $true } 
                                    if ($interpretedThreat.ThreatDetails) { [void]$reportThreatDetailsAggregator.AppendLine($interpretedThreat.ThreatDetails) }
                                }
                            }
                            
                            if (-not $scanSpecificEventsFound) {
                                [void]$reportResultMessageAggregator.AppendLine("Keine spezifischen Scan- oder Bedrohungs-Events für diesen Scan-Vorgang gefunden.")
                            }

                            if ($interimEventsFoundAndProcessed) { 
                                [void]$reportResultMessageAggregator.Insert(0, "INTERIM EVENTS (seit letztem Report bis Scan-Start): $($interimEventsSummaryMessages -join ' | ') || SCAN-BEZOGEN: ")
                                $reportThreatsFound = $true 
                                if ($interimThreatDetailsAggregated.Count -gt 0) {
                                    $currentDetailsString = $reportThreatDetailsAggregator.ToString()
                                    $reportThreatDetailsAggregator.Clear()
                                    [void]$reportThreatDetailsAggregator.Append("INTERIM DETAILS: $($interimThreatDetailsAggregated -join ' | ')")
                                    if (-not [string]::IsNullOrWhiteSpace($currentDetailsString)) {
                                        [void]$reportThreatDetailsAggregator.Append(" || SCAN-BEZOGENE DETAILS: " + $currentDetailsString)
                                    }
                                }
                            }
                            Send-ScanReport -ScanTime $reportScanTime -ScanType $scanTypeToUse `
                                -ScanResultMessage $reportResultMessageAggregator.ToString().Trim() `
                                -ThreatsFound $reportThreatsFound `
                                -ThreatDetails $reportThreatDetailsAggregator.ToString().Trim()
                        } catch {
                            $scanErrorMsg = $_.Exception.Message; $fullError = $_.ToString()
                            Write-Error "... Fehler bei Start-MpScan/Ergebnisermittlung: $scanErrorMsg."
                            $errMsgForReport = [System.Text.StringBuilder]::new()
                            if ($interimEventsFoundAndProcessed) { [void]$errMsgForReport.Append("INTERIM EVENTS: $($interimEventsSummaryMessages -join ' | ') | DANN FEHLER: ") }
                            [void]$errMsgForReport.Append("Kritischer Fehler im Scan-Prozess: $scanErrorMsg")
                            
                            $detailsForReport = [System.Text.StringBuilder]::new()
                            [void]$detailsForReport.Append("PS Exception: $fullError")
                            if($interimThreatDetailsAggregated.Count -gt 0){ [void]$detailsForReport.Append("; INTERIM DETAILS: $($interimThreatDetailsAggregated -join ' | ')") }
                            
                            Send-ScanReport -ScanTime $scanCommandInitiationTimeUTC.ToString("o") -ScanType $scanTypeToUse `
                                -ScanResultMessage $errMsgForReport.ToString().Trim() `
                                -ThreatsFound $true `
                                -ThreatDetails $detailsForReport.ToString().Trim()
                        } finally {
                            if ($null -ne $scanJob) { Write-Host "... Entferne Job $($scanJob.Id) (Status: $($scanJob.State))."; Remove-Job $scanJob -Force }
                        }
                    } # Ende START_SCAN
                    default { Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unbekannter Befehl: $($commandResponse.command)" }
                } # Ende switch
                # Write-Host "DEBUG_LOOP: Nach Switch(commandResponse.command)" # Kann bei Bedarf einkommentiert werden
            } elseif ($interimEventsFoundAndProcessed) { 
                # Write-Host "DEBUG_LOOP: Innerhalb elseif (interimEventsFoundAndProcessed)" # Kann bei Bedarf einkommentiert werden
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Kein Server-Befehl, aber Zwischendurch-Ereignisse gefunden. Sende Bericht."
                $reportTime = (Get-Date).ToUniversalTime().ToString("o")
                Send-ScanReport -ScanTime $reportTime -ScanType "InterimRealtimeEvent" `
                    -ScanResultMessage ($interimEventsSummaryMessages -join ' | ') `
                    -ThreatsFound $true `
                    -ThreatDetails ($interimThreatDetailsAggregated -join ' | ')
                # Write-Host "DEBUG_LOOP: Nach Send-ScanReport für Interim-Events" # Kann bei Bedarf einkommentiert werden
            } else { 
                # Write-Host "DEBUG_LOOP: Innerhalb else (kein Befehl, keine Interim-Events)" # Kann bei Bedarf einkommentiert werden
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Kein spezifischer Befehl und keine Zwischendurch-Events seit letztem Report." 
            }
        } # Dies ist die schließende Klammer für if (-not $commandErrorOccurred -and $null -ne $commandResponse)

        # Write-Host "DEBUG_LOOP: Vor Heartbeat Check" # Kann bei Bedarf einkommentiert werden
        # Periodischer Check (Heartbeat)
        if ($Global:LastSuccessfulReportTimeUTC -and (($currentLoopTimeUTC - $Global:LastInterimCheckTimeUTC).TotalMinutes -ge $InterimCheckIntervalMinutes)) {
            Write-Host "Führe periodischen Check für Zwischendurch-Events durch (Intervall: $InterimCheckIntervalMinutes Min)..."
            $Global:LastInterimCheckTimeUTC = $currentLoopTimeUTC 
            
            if (($currentLoopTimeUTC - $Global:LastSuccessfulReportTimeUTC).TotalHours -ge ($InterimCheckIntervalMinutes / 60 * 2) ) { 
                 if (-not $interimEventsFoundAndProcessed) { 
                    Write-Host "Lange keinen Report gesendet und keine akuten Zwischendurch-Events in diesem Zyklus. Sende 'Heartbeat'."
                    Send-ScanReport -ScanTime $currentLoopTimeUTC.ToString("o") -ScanType "Heartbeat" -ScanResultMessage "Periodischer Check, alles ruhig seit letztem Report (basierend auf diesem Zyklus)." -ThreatsFound $false
                 }
            }
        }
        # Write-Host "DEBUG_LOOP: Nach Heartbeat Check" # Kann bei Bedarf einkommentiert werden

        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Warte $PollingIntervalSeconds Sekunden bis zum nächsten Poll..."
        Start-Sleep -Seconds $PollingIntervalSeconds
        # Write-Host "DEBUG_LOOP: Nach Start-Sleep, vor nächstem Schleifendurchlauf" # Kann bei Bedarf einkommentiert werden
    } # Ende while
} catch { 
    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unerwarteter Fehler Hauptschleife: $($_.Exception.ToString()). Skript beendet."; exit 1 
}