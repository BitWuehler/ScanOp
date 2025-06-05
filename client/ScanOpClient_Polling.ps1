<#
.SYNOPSIS
    Client-Skript zum Pollen von Befehlen vom ScanOp-Server und Ausführen von Aktionen.
.DESCRIPTION
    Dieses Skript liest eine Konfiguration, pollt periodisch einen Server-API-Endpunkt
    und führt basierend auf den empfangenen Befehlen Aktionen aus (z.B. Starten eines Virenscans
    und Melden des Ergebnisses mit interpretierten Defender-Statuscodes).
    BENÖTIGT ADMINISTRATORBERECHTIGUNGEN für Start-MpScan und Get-WinEvent.
#>

# --- Konfiguration und Initialisierung ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFilePath = Join-Path -Path $ScriptDir -ChildPath "client_config.json"

Write-Host "Lese Konfiguration von: $ConfigFilePath"

if (-not (Test-Path $ConfigFilePath)) {
    Write-Error "Konfigurationsdatei nicht gefunden: $ConfigFilePath"
    exit 1
}

try {
    $Config = Get-Content -Path $ConfigFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Error "Fehler beim Lesen oder Parsen der Konfigurationsdatei '$ConfigFilePath': $($_.Exception.Message)"
    exit 1
}

$AliasName = $Config.AliasName
$ServerBaseUrl = $Config.ServerBaseUrl
$ApiKey = $Config.ApiKey
$PollingIntervalSeconds = $Config.PollingIntervalSeconds

if (-not $AliasName -or -not $ServerBaseUrl -or -not $PollingIntervalSeconds) {
    Write-Error "Unvollständige Konfiguration in '$ConfigFilePath'. AliasName, ServerBaseUrl und PollingIntervalSeconds sind erforderlich."
    exit 1
}

Write-Host "Client gestartet für Alias: $AliasName"
Write-Host "Server URL: $ServerBaseUrl"
Write-Host "Polling Intervall: $PollingIntervalSeconds Sekunden"

$CommandUrl = "$ServerBaseUrl/clientcommands/$AliasName"
$ReportUrl = "$ServerBaseUrl/scanreports/"

# --- Hilfsfunktion zum Senden von Scan-Berichten (angepasst für PS 5.1 Kompatibilität) ---
function Send-ScanReport {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScanTime,
        [Parameter(Mandatory=$true)]
        [string]$ScanType,
        [Parameter(Mandatory=$true)]
        [string]$ScanResultMessage,
        [Parameter(Mandatory=$true)]
        [bool]$ThreatsFound,
        [string]$ThreatDetails = $null
    )

    Write-Host "DEBUG: Betrete Send-ScanReport Funktion."
    Write-Host "Sende Scan-Bericht an: $ReportUrl"

    if ([string]::IsNullOrWhiteSpace($ScanTime)) { Write-Warning "ScanTime leer! Fallback."; $ScanTime = (Get-Date -Date "1970-01-01").ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    if ([string]::IsNullOrWhiteSpace($ScanType)) { Write-Warning "ScanType leer! Fallback."; $ScanType = "Unbekannt" }
    if ([string]::IsNullOrWhiteSpace($ScanResultMessage)) { Write-Warning "ScanResultMessage leer! Fallback."; $ScanResultMessage = "Keine Meldung" }

    $payloadContent = @{
        laptop_identifier = $AliasName
        client_scan_time = $ScanTime
        scan_type = $ScanType
        scan_result_message = $ScanResultMessage
        threats_found = $ThreatsFound
    }
    if ($null -ne $ThreatDetails -and (-not [string]::IsNullOrWhiteSpace($ThreatDetails))) { $payloadContent.threat_details = $ThreatDetails }
    else { $payloadContent.threat_details = $null }

    $payloadBodyJson = $payloadContent | ConvertTo-Json -Depth 5 -Compress
    Write-Host "DEBUG: Erstellter Payload für Report: $payloadBodyJson"

    $requestHeaders = @{ "Content-Type" = "application/json" }
    # if ($ApiKey) { $requestHeaders["X-API-Key"] = $ApiKey } # TODO: EINKOMMENTIEREN

    $ErrorActionPreferenceBackup = $ErrorActionPreference
    $ErrorActionPreference = "Stop" # Stellt sicher, dass Invoke-RestMethod bei HTTP-Fehlern eine Exception wirft

    $responseVariable = $null
    $actualHttpStatusCode = 0 # Für den tatsächlichen HTTP-Statuscode

    try {
        Write-Host "DEBUG: Vor Invoke-RestMethod für Report-Senden (ohne -StatusCodeVariable)..."
        # -StatusCodeVariable und -ErrorVariable entfernt für PS 5.1 Kompatibilität
        $responseVariable = Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payloadBodyJson -Headers $requestHeaders -TimeoutSec 60

        # Wenn wir hier ankommen, hat Invoke-RestMethod KEINE Exception geworfen.
        # Das bedeutet bei einem POST typischerweise einen 2xx Status (z.B. 200, 201, 204).
        $actualHttpStatusCode = 201 # Annahme für einen erfolgreichen POST, der hier landet (FastAPI gibt 201 zurück)
        Write-Host "DEBUG: Nach Invoke-RestMethod (innerhalb try, keine Exception). Angenommener Status: $actualHttpStatusCode"
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan-Bericht erfolgreich an den Server gesendet. (Status: $actualHttpStatusCode angenommen)"
        if ($responseVariable) {
             Write-Host "Server Antwort (Erfolg): $($responseVariable | ConvertTo-Json -Depth 3 -Compress)"
        }
    }
    catch {
        $CaughtException = $_
        Write-Host "DEBUG CATCH-BLOCK Send-ScanReport: Exception abgefangen!"

        Write-Error "FEHLER DETAILS: Exception beim Senden des Scan-Reports!"
        if ($CaughtException.Exception) {
            Write-Error "Exception Typ: $($CaughtException.Exception.GetType().FullName)"
            Write-Error "Exception Nachricht: $($CaughtException.Exception.Message)"
            if ($CaughtException.Exception -is [System.Net.WebException]) {
                $webEx = $CaughtException.Exception
                Write-Error "Status der WebException: $($webEx.Status)"
                if ($null -ne $webEx.Response) {
                    $httpResponse = $webEx.Response
                    $actualHttpStatusCode = [int]$httpResponse.StatusCode
                    Write-Error "HTTP Status Code der Response: $actualHttpStatusCode"
                    $errorBodyContent = "<Fehler beim Lesen des Body>"
                    try {
                        $responseStream = $httpResponse.GetResponseStream()
                        if ($responseStream.CanRead) { $streamReader = New-Object System.IO.StreamReader($responseStream); $errorBodyContent = $streamReader.ReadToEnd(); $streamReader.Close() }
                        else { $errorBodyContent = "<Antwort-Stream nicht lesbar>" }
                        $responseStream.Close()
                    } catch { $errorBodyContent = "<Exception beim Lesen des Fehler-Bodys: $($_.Exception.Message)>" }
                    Write-Error "Fehlerhafter Antwort-Body vom Server (aus WebEx): $errorBodyContent"
                } else { Write-Warning "Die WebException enthält kein Response-Objekt." }
            }
        } else {
            # Fall für Exceptions, die keine .Exception Eigenschaft haben (z.B. ParameterBindingException direkt)
             Write-Error "Das abgefangene Fehlerobjekt (`$_`) ist: $($CaughtException.ToString())"
             if ($CaughtException.FullyQualifiedErrorId -eq "NamedParameterNotFound,Microsoft.PowerShell.Commands.InvokeRestMethodCommand") {
                Write-Error "HINWEIS: Der Fehler 'NamedParameterNotFound' deutet auf eine Inkompatibilität mit der PowerShell-Version hin (z.B. -StatusCodeVariable/-ErrorVariable in PS < 6.0)."
            }
        }
    }
    finally {
        $ErrorActionPreference = $ErrorActionPreferenceBackup
        Write-Host "DEBUG: Send-ScanReport beendet. HTTP-Statuscode (falls ermittelt): $actualHttpStatusCode"
    }
}

# --- Hilfsfunktion zur Konvertierung von Defender Event Informationen ---
function ConvertFrom-DefenderEvent {
    param( [Parameter(Mandatory=$true)] $Event )
    $result = @{ ScanTime = $Event.TimeCreated.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"); ResultMessage = "Unbehandeltes Event (ID: $($Event.Id))"; ThreatsFound = $false; ThreatDetails = $null }
    switch ($Event.Id) {
        1001 { $result.ResultMessage = "Scan erfolgreich beendet. Keine Bedrohungen gefunden."; $result.ThreatsFound = $false }
        1002 { $result.ResultMessage = "Scan erfolgreich beendet. Bedrohungen gefunden und behandelt."; $result.ThreatsFound = $true }
        1005 { $result.ResultMessage = "Fehler während Scan: $($Event.Message)" }
        1116 { $result.ResultMessage = "Bedrohung erkannt: $($Event.Message)"; $result.ThreatsFound = $true; $result.ThreatDetails = $Event.Message }
        1117 { $result.ResultMessage = "Aktion gegen Bedrohung erfolgreich: $($Event.Message)"; $result.ThreatsFound = $true }
        1118 { $result.ResultMessage = "FEHLER Aktion gegen Bedrohung: $($Event.Message)"; $result.ThreatsFound = $true; $result.ThreatDetails = $Event.Message }
        1119 { $result.ResultMessage = "Scan abgebrochen: $($Event.Message)" }
        default { Write-Warning "Unbekannte Event ID $($Event.Id) in ConvertFrom-DefenderEvent." }
    }
    return $result
}

# --- Haupt-Polling-Schleife ---
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starte Haupt-Polling-Schleife..."
try {
    while ($true) {
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Frage Befehle vom Server ab: $CommandUrl"
        $commandHeaders = @{}
        # if ($ApiKey) { $commandHeaders["X-API-Key"] = $ApiKey }

        $commandResponse = $null
        $commandErrorOccurred = $false
        $commandActualHttpStatusCode = 0 # Für den tatsächlichen HTTP-Statuscode bei der Befehlsabfrage

        try {
            # -StatusCodeVariable und -ErrorVariable entfernt für PS 5.1 Kompatibilität
            $commandResponse = Invoke-RestMethod -Uri $CommandUrl -Method Get -Headers $commandHeaders -TimeoutSec 20 -ErrorAction Stop
            $commandActualHttpStatusCode = 200 # Annahme: Erfolg, wenn keine Exception bei GET
            $commandErrorOccurred = $false
        }
        catch {
            $commandErrorOccurred = $true
            $CaughtCmdException = $_
            $apiErrorMessage = "Fehler bei Invoke-RestMethod (Befehlsabfrage): $($CaughtCmdException.ToString())" # Komplette Exception für mehr Details

            if ($CaughtCmdException.Exception -is [System.Net.WebException] -and $null -ne $CaughtCmdException.Exception.Response) {
                $httpResponse = $CaughtCmdException.Exception.Response
                $commandActualHttpStatusCode = [int]$httpResponse.StatusCode
                $errorBodyDetail = ""; try { $errStream = $httpResponse.GetResponseStream(); if ($errStream.CanRead){ $errReader = New-Object System.IO.StreamReader($errStream); $errorBodyDetail = $errReader.ReadToEnd(); $errReader.Close() } else { $errorBodyDetail = "<Stream nicht lesbar>" }; $errStream.Close() } catch { $errorBodyDetail = "<Ex beim Lesen: $($_.Exception.Message)>" }
                $apiErrorMessage = "HTTP Fehler $commandActualHttpStatusCode (Befehlsabfrage). Body: '$errorBodyDetail'. Urspr. Fehler: $($CaughtCmdException.Exception.Message)"
            }

            if ($commandActualHttpStatusCode -eq 404) {
                Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FEHLER 404: Laptop '$AliasName' nicht registriert. Pause. $apiErrorMessage"
                Start-Sleep -Seconds 3600
            } else {
                Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler Befehlsabruf (Status $commandActualHttpStatusCode): $apiErrorMessage"
                Start-Sleep -Seconds ($PollingIntervalSeconds * 2)
            }
        }

        if (-not $commandErrorOccurred -and $null -ne $commandResponse) {
            if ($commandResponse.command) {
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Befehl: $($commandResponse.command), ScanTyp Server: $($commandResponse.scan_type)"
                $scanTypeFromServer = $commandResponse.scan_type
                switch ($commandResponse.command) {
                    "START_SCAN" {
                        $scanTypeToUse = "FullScan"
                        if ($null -ne $scanTypeFromServer -and (-not [string]::IsNullOrWhiteSpace($scanTypeFromServer))) {
                            if ($scanTypeFromServer -eq "QuickScan" -or $scanTypeFromServer -eq "FullScan") { $scanTypeToUse = $scanTypeFromServer; Write-Host "Verwende Scan-Typ vom Server: $scanTypeToUse" }
                            else { Write-Warning "Ungültiger Scan-Typ '$scanTypeFromServer'. Verwende '$scanTypeToUse'." }
                        } else { Write-Host "Kein Scan-Typ vom Server, verwende '$scanTypeToUse'." }

                        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Aktion: Starte Scan (Typ: $scanTypeToUse)..."
                        $scanCommandInitiationTimeUTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                        $scanJob = $null # Initialisieren für den catch-Block

                        try {
                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Initiiere Scan ($scanTypeToUse) als Hintergrundjob..."
                            $scanJob = Start-Job -ScriptBlock {
                                param($scanType) # Parameter für den ScriptBlock definieren
                                Start-MpScan -ScanType $scanType -ErrorAction Stop
                            } -ArgumentList $scanTypeToUse # Argument an den ScriptBlock übergeben
                            
                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan ($scanTypeToUse) als Job $($scanJob.Id) gestartet."

                            $scanInProgress = $true
                            $maxWaitMinutes = if ($scanTypeToUse -eq "QuickScan") { 30 } else { 360 }
                            $waitIntervalSeconds = 30
                            $elapsedWaitSeconds = 0

                            Write-Host "Warte auf Scan-Abschluss (max. $maxWaitMinutes Min)..."

                            while ($scanInProgress -and ($elapsedWaitSeconds -lt ($maxWaitMinutes * 60))) {
                                Start-Sleep -Seconds $waitIntervalSeconds
                                $elapsedWaitSeconds += $waitIntervalSeconds
                                try {
                                    $mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
                                    if ($null -ne $mpStatus) {
                                        $scanInProgress = $mpStatus.MpScanInProgress
                                        if (-not $scanInProgress) {
                                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan nicht mehr 'in Progress' (nach ca. $($elapsedWaitSeconds/60) Min.). Status von Get-MpComputerStatus."
                                            break # Scan ist beendet, Schleife verlassen
                                        }
                                    } else {
                                        Write-Warning "Get-MpComputerStatus: kein Ergebnis."
                                        # Alternative Prüfung: Job-Status, wenn MpComputerStatus keine Infos liefert
                                        if ($scanJob.State -ne 'Running' -and $scanJob.State -ne 'NotStarted') { # NotStarted ist auch ein aktiver Status am Anfang
                                            Write-Warning "Scan-Job ist nicht mehr 'Running' oder 'NotStarted'. Job-Status: $($scanJob.State). Beende Warte-Schleife."
                                            $scanInProgress = $false # Schleife verlassen
                                            break
                                        }
                                    }
                                }
                                catch { Write-Warning "Get-MpComputerStatus Fehler: $($_.Exception.Message)." }
                                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan läuft (Status laut MpComputerStatus: $scanInProgress, Job-Status: $($scanJob.State))... Wartezeit: ca. $($elapsedWaitSeconds/60) Min."
                            }

                            if ($scanInProgress) {
                                Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan Max-Wartezeit überschritten oder Scan immer noch als 'in Progress' markiert."
                                if ($scanJob.State -eq 'Running') {
                                    Write-Warning "Stoppe laufenden Scan-Job $($scanJob.Id) aufgrund von Timeout."
                                    Stop-Job -Job $scanJob -Force
                                }
                            }

                            # Warte kurz, damit der Job ggf. Fehler schreiben kann, bevor wir Receive-Job aufrufen
                            Wait-Job -Job $scanJob -Timeout 10 | Out-Null

                            # Job-Output/Fehler abrufen
                            $jobMessages = Receive-Job -Job $scanJob -Keep # -Keep, damit der Job für Remove-Job noch da ist
                            if ($jobMessages) {
                                Write-Host "Ausgaben/Fehler vom Scan-Job $($scanJob.Id):"
                                $jobMessages | ForEach-Object { Write-Host "  JOB_MSG: $_" }
                            }

                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Lese Event Log..."
                            Start-Sleep -Seconds 5 # Kurze Pause, um sicherzustellen, dass alle Events geschrieben wurden
                            $eventQueryStartTime = ([datetime]$scanCommandInitiationTimeUTC).AddMinutes(-2)

                            $finalScanEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 100 |
                                Where-Object { ($_.Id -in (1001,1002,1005,1119)) -and ($_.TimeCreated -ge $eventQueryStartTime) } |
                                Sort-Object TimeCreated -Descending | Select-Object -First 1

                            $reportScanTime = $scanCommandInitiationTimeUTC
                            $reportResultMessage = "Scan ($scanTypeToUse) initiiert $scanCommandInitiationTimeUTC, finales Abschluss-Event nicht gefunden (ab $eventQueryStartTime)."
                            $reportThreatsFound = $false
                            $reportThreatDetails = $null

                            if ($finalScanEvent) {
                                $interpretedResult = ConvertFrom-DefenderEvent -Event $finalScanEvent
                                $reportScanTime = $interpretedResult.ScanTime
                                $reportResultMessage = $interpretedResult.ResultMessage
                                $reportThreatsFound = [System.Convert]::ToBoolean($interpretedResult.ThreatsFound)
                                $reportThreatDetails = $interpretedResult.ThreatDetails
                                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Finales Scan-Ergebnis (Event $($finalScanEvent.Id) um $($finalScanEvent.TimeCreated)): $reportResultMessage"
                            } else {
                                Write-Warning $reportResultMessage
                                $threatEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 50 |
                                    Where-Object { ($_.Id -in (1116,1117,1118)) -and ($_.TimeCreated -ge $eventQueryStartTime) } |
                                    Sort-Object TimeCreated -Descending | Select-Object -First 1

                                if ($threatEvent) {
                                    $interpretedThreat = ConvertFrom-DefenderEvent -Event $threatEvent
                                    $reportResultMessage += " | Bedrohungs-Event (ID $($threatEvent.Id) um $($threatEvent.TimeCreated)): $($interpretedThreat.ResultMessage)"
                                    # Bedrohungen können zusätzlich gefunden werden, auch wenn kein Abschluss-Event vorliegt
                                    $reportThreatsFound = [System.Convert]::ToBoolean($interpretedThreat.ThreatsFound) -or $reportThreatsFound
                                    $reportThreatDetails = if ([string]::IsNullOrWhiteSpace($reportThreatDetails)) { $interpretedThreat.ThreatDetails } else { "$reportThreatDetails; $($interpretedThreat.ThreatDetails)" }
                                    Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Zusätzliches Bedrohungs-Event gefunden: $($interpretedThreat.ResultMessage)"
                                } else {
                                    $reportThreatsFound = [System.Convert]::ToBoolean($reportThreatsFound)
                                }
                            }
                            Send-ScanReport -ScanTime $reportScanTime -ScanType $scanTypeToUse -ScanResultMessage $reportResultMessage -ThreatsFound $reportThreatsFound -ThreatDetails $reportThreatDetails
                        }
                        catch {
                            $scanErrorMsg = $_.Exception.Message
                            Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler bei Start-MpScan/Ergebnisermittlung oder Job-Handling: $scanErrorMsg. Kompletter Fehler: $($_.ToString())"
                            Send-ScanReport -ScanTime $scanCommandInitiationTimeUTC -ScanType $scanTypeToUse -ScanResultMessage "Kritischer Fehler im Scan-Prozess: $scanErrorMsg" -ThreatsFound $true -ThreatDetails "PS Exception: $($_.ToString())"
                        }
                        finally {
                            # Job aufräumen, falls er erstellt wurde
                            if ($null -ne $scanJob) {
                                Write-Host "Entferne Scan-Job $($scanJob.Id) (Status: $($scanJob.State))."
                                Remove-Job -Job $scanJob -Force
                            }
                        }
                    }
                    default { Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unbekannter Befehl: $($commandResponse.command)" }
                }
            } else { Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Kein spezifischer Befehl empfangen." }
        }
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Warte $PollingIntervalSeconds Sekunden bis zum nächsten Poll..."
        Start-Sleep -Seconds $PollingIntervalSeconds
    }
}
catch { Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unerwarteter Fehler in Hauptschleife: $($_.Exception.ToString()). Skript beendet."; exit 1 }