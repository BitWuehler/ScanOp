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

# --- Hilfsfunktion zum Senden von Scan-Berichten ---
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

    Write-Host "Sende Scan-Bericht an: $ReportUrl"
    
    if ([string]::IsNullOrWhiteSpace($ScanTime)) { Write-Warning "ScanTime ist leer oder null!"; $ScanTime = (Get-Date -Date "1970-01-01").ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    if ([string]::IsNullOrWhiteSpace($ScanType)) { Write-Warning "ScanType ist leer oder null!"; $ScanType = "Unbekannt" }
    if ([string]::IsNullOrWhiteSpace($ScanResultMessage)) { Write-Warning "ScanResultMessage ist leer oder null!"; $ScanResultMessage = "Keine Meldung verfügbar" }

    $reportData = @{
        client_scan_time = $ScanTime
        scan_type = $ScanType
        scan_result_message = $ScanResultMessage
        threats_found = $ThreatsFound 
    }

    if ($null -ne $ThreatDetails -and (-not [string]::IsNullOrWhiteSpace($ThreatDetails))) {
        $reportData.threat_details = $ThreatDetails
    } else {
        $reportData.threat_details = $null 
    }

    $payloadBody = @{
        laptop_identifier = $AliasName
        scan_data = $reportData
    } | ConvertTo-Json -Depth 5 -Compress

    Write-Host "DEBUG: Zu sendender Payload für Report: $payloadBody" 

    $ErrorActionPreferenceBackup = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue" # Fehler manuell abfangen
    $responseVariable = $null

    try {
        # Verwende -StatusCodeVariable und -ErrorVariable für mehr Details
        Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payloadBody -ContentType "application/json" -StatusCodeVariable statusCode -ErrorVariable requestError -OutVariable responseVariable
        
        if ($statusCode -ge 200 -and $statusCode -lt 300) {
            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan-Bericht erfolgreich an den Server gesendet. Status: $statusCode"
            if ($responseVariable) {
                # Write-Host "Server Antwort (Erfolg): $($responseVariable | ConvertTo-Json -Depth 3 -Compress)"
            }
        } else {
            # Dies wird erreicht, wenn der Server einen Fehlerstatuscode zurückgibt, aber Invoke-RestMethod nicht abbricht
            $errorMessage = "Fehler beim Senden des Scan-Berichts. Server antwortete mit Status: $statusCode."
            if ($responseVariable) { # $responseVariable enthält den Body bei Fehlern, wenn -ErrorAction nicht 'Stop' ist
                $errorMessage += " Server-Antwort-Body: '$($responseVariable | Out-String)'"
            } elseif ($requestError) {
                 $errorMessage += " RequestError: $($requestError[0].ToString())"
                 if ($requestError[0].Exception.Response) {
                    $stream = $requestError[0].Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $errorBody = $reader.ReadToEnd()
                    $reader.Close()
                    $stream.Close()
                    $errorMessage += " Detaillierter Fehlerbody: '$errorBody'"
                 }
            }
            Write-Error $errorMessage
        }
    }
    catch {
        # Dieser Catch-Block wird jetzt seltener erreicht, da wir Fehler manuell prüfen
        $errorMessage = "Kritischer Fehler bei Invoke-RestMethod: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $sendStatusCode = $_.Exception.Response.StatusCode.Value__
            $sendStatusDescription = $_.Exception.Response.StatusDescription
            $errorBodyContent = ""
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $errorBodyContent = $reader.ReadToEnd()
                $reader.Close()
                $stream.Close()
            } catch {}
            $errorMessage = "HTTP Fehler $sendStatusCode ($sendStatusDescription). Server-Antwort-Body: '$errorBodyContent'. Ursprünglicher Fehler: $($_.Exception.Message)"
        }
        Write-Error $errorMessage
    }
    finally {
        $ErrorActionPreference = $ErrorActionPreferenceBackup
    }
}

# --- Hilfsfunktion zur Konvertierung von Defender Event Informationen ---
function ConvertFrom-DefenderEvent {
    param(
        [Parameter(Mandatory=$true)]
        $Event 
    )

    $result = @{
        ScanTime = $Event.TimeCreated.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        ResultMessage = "Unbehandeltes Scan-Event (ID: $($Event.Id)) - Nachricht: $($Event.Message)"
        ThreatsFound = $false 
        ThreatDetails = $null
    }

    switch ($Event.Id) {
        1001 { 
            $result.ResultMessage = "Scan erfolgreich beendet. Keine Bedrohungen gefunden."
            $result.ThreatsFound = $false
        }
        1002 {
            $result.ResultMessage = "Scan erfolgreich beendet. Bedrohungen gefunden und Aktion(en) durchgeführt."
            $result.ThreatsFound = $true
        }
        1005 { 
            $result.ResultMessage = "Fehler während des Scans. Der Scan wurde möglicherweise nicht vollständig durchgeführt. Details: $($Event.Message)"
        }
        1116 { 
            $result.ResultMessage = "Bedrohung während des Scans erkannt. Details: $($Event.Message)" 
            $result.ThreatsFound = $true
            $result.ThreatDetails = $Event.Message
        }
        1117 { 
            $result.ResultMessage = "Aktion gegen Bedrohung erfolgreich durchgeführt. Details: $($Event.Message)"
            $result.ThreatsFound = $true 
        }
        1118 { 
            $result.ResultMessage = "FEHLER: Aktion gegen Bedrohung fehlgeschlagen. Details: $($Event.Message)"
            $result.ThreatsFound = $true 
            $result.ThreatDetails = $Event.Message
        }
        1119 { 
            $result.ResultMessage = "Scan abgebrochen. Details: $($Event.Message)"
        }
    }
    return $result
}


# --- Haupt-Polling-Schleife ---
Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Starte Haupt-Polling-Schleife..."
try {
    while ($true) {
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Frage Befehle vom Server ab: $CommandUrl"

        $headers = @{}
        # if ($ApiKey) { $headers["X-API-Key"] = $ApiKey }

        try {
            $response = Invoke-RestMethod -Uri $CommandUrl -Method Get -Headers $headers -ErrorAction Stop 
            
            if ($null -ne $response -and $response.command) {
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Befehl empfangen: $($response.command), Scan-Typ: $($response.scan_type)"
                
                $scanTypeFromServer = $response.scan_type 

                switch ($response.command) {
                    "START_SCAN" {
                        $scanTypeToUse = "FullScan" 
                        if ($null -ne $scanTypeFromServer -and (-not [string]::IsNullOrWhiteSpace($scanTypeFromServer))) {
                            if ($scanTypeFromServer -in ("QuickScan", "FullScan")) {
                                $scanTypeToUse = $scanTypeFromServer
                            } else {
                                Write-Warning "Ungültiger Scan-Typ '$scanTypeFromServer' vom Server empfangen. Verwende Standard '$scanTypeToUse'."
                            }
                        } else {
                            Write-Warning "Kein spezifischer Scan-Typ vom Server empfangen, verwende Standard '$scanTypeToUse'."
                        }
                        
                        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Aktion: Starte Windows Defender Scan (Typ: $scanTypeToUse)..."
                        $scanCommandStartTimeUTC = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

                        try {
                            Start-MpScan -ScanType $scanTypeToUse -ErrorAction Stop 
                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Windows Defender Scan ($scanTypeToUse) wurde initiiert."
                            
                            $scanInProgress = $true
                            $maxWaitMinutes = if ($scanTypeToUse -eq "QuickScan") { 30 } else { 360 } 
                            $waitIntervalSeconds = 30 
                            $elapsedWaitSeconds = 0
                            
                            Write-Host "Warte auf Abschluss des Scans (max. $maxWaitMinutes Minuten, Prüfung alle $waitIntervalSeconds Sek.)..."

                            while ($scanInProgress -and ($elapsedWaitSeconds -lt ($maxWaitMinutes * 60))) {
                                Start-Sleep -Seconds $waitIntervalSeconds
                                $elapsedWaitSeconds += $waitIntervalSeconds
                                try {
                                    $mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
                                    if ($null -ne $mpStatus) {
                                        $scanInProgress = $mpStatus.MpScanInProgress
                                        if (-not $scanInProgress) {
                                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan nicht mehr 'in Progress' laut Get-MpComputerStatus (nach ca. $($elapsedWaitSeconds/60) Min.)."
                                            break 
                                        }
                                    } else {
                                        Write-Warning "Get-MpComputerStatus hat kein Ergebnis geliefert. Warte weiter."
                                    }
                                } catch {
                                    Write-Warning "Fehler beim Abrufen von Get-MpComputerStatus: $($_.Exception.Message). Warte weiter."
                                }
                                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan läuft noch (Status: $scanInProgress)... Wartezeit bisher: ca. $($elapsedWaitSeconds/60) Minuten."
                            }

                            if ($scanInProgress) {
                                Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan hat die maximale Wartezeit von $maxWaitMinutes Minuten überschritten. Versuche trotzdem, das Ergebnis aus dem Event Log zu lesen."
                            }

                            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Scan-Prozess ($scanTypeToUse) beendet oder Zeitlimit erreicht. Lese jetzt das Ergebnis aus dem Event Log..."
                            Start-Sleep -Seconds 5 
                            
                            $eventStartTime = ([datetime]$scanCommandStartTimeUTC).AddMinutes(-5) 

                            $finalScanEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 100 | Where-Object {
                                ($_.Id -in (1001, 1002, 1005, 1119)) -and ($_.TimeCreated -ge $eventStartTime)
                            } | Sort-Object TimeCreated -Descending | Select-Object -First 1

                            $reportScanTime = $scanCommandStartTimeUTC 
                            $reportResultMessage = "Scan ($scanTypeToUse) initiiert, aber kein eindeutiges finales Scan-Event im Log gefunden (Zeitraum: ab $eventStartTime)."
                            $reportThreatsFound = $false # Muss [bool] sein
                            $reportThreatDetails = $null

                            if ($finalScanEvent) {
                                $interpretedResult = ConvertFrom-DefenderEvent -Event $finalScanEvent
                                $reportScanTime = $interpretedResult.ScanTime
                                $reportResultMessage = $interpretedResult.ResultMessage
                                $reportThreatsFound = [System.Convert]::ToBoolean($interpretedResult.ThreatsFound) 
                                $reportThreatDetails = $interpretedResult.ThreatDetails
                                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Interpretiertes finales Scan-Ergebnis (Event ID $($finalScanEvent.Id)): $reportResultMessage"
                            } else {
                                Write-Warning $reportResultMessage
                                $threatEvent = Get-WinEvent -ProviderName "Microsoft-Windows-Windows Defender" -MaxEvents 50 | Where-Object {
                                    ($_.Id -in (1116, 1117, 1118)) -and ($_.TimeCreated -ge $eventStartTime) 
                                } | Sort-Object TimeCreated -Descending | Select-Object -First 1
                                if ($threatEvent) {
                                    $interpretedThreat = ConvertFrom-DefenderEvent -Event $threatEvent
                                    $reportResultMessage += " Es gab jedoch ein Bedrohungs-relevantes Event: $($interpretedThreat.ResultMessage)"
                                    $reportThreatsFound = [System.Convert]::ToBoolean($interpretedThreat.ThreatsFound) 
                                    $reportThreatDetails = $interpretedThreat.ThreatDetails
                                     Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Zusätzliches Bedrohungs-Event gefunden (ID $($threatEvent.Id)): $($interpretedThreat.ResultMessage)"
                                } else {
                                    # Sicherstellen, dass $reportThreatsFound auch hier ein bool ist, falls kein Event gefunden wurde
                                    $reportThreatsFound = [System.Convert]::ToBoolean($reportThreatsFound) 
                                }
                            }
                            
                            $reportParamsFinal = @{
                                ScanTime = $reportScanTime
                                ScanType = $scanTypeToUse
                                ScanResultMessage = $reportResultMessage
                                ThreatsFound = $reportThreatsFound # Ist jetzt sicher ein [bool]
                                ThreatDetails = $reportThreatDetails
                            }
                            Send-ScanReport @reportParamsFinal
                        }
                        catch {
                            $scanErrorMsg = $_.Exception.Message
                            Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler während des Start-MpScan oder der Ergebnisermittlung: $scanErrorMsg"
                            $errorReportParams = @{
                                ScanTime = $scanCommandStartTimeUTC
                                ScanType = $scanTypeToUse
                                ScanResultMessage = "Kritischer Fehler beim Ausführen des Scans oder Ergebnisermittlung: $scanErrorMsg"
                                ThreatsFound = $true 
                                ThreatDetails = "PowerShell Exception: $($_.Exception.ToString())"
                            }
                            Send-ScanReport @errorReportParams
                        }
                    }
                    default {
                        Write-Warning "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Unbekannter Befehl empfangen: $($response.command)"
                    }
                }
            }
            else {
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Kein spezifischer Befehl empfangen."
            }
        }
        catch {
            $apiErrorMessage = $_.Exception.Message
            if ($_.Exception.Response) {
                $apiStatusCode = $_.Exception.Response.StatusCode.Value__
                $apiStatusDescription = $_.Exception.Response.StatusDescription
                $apiErrorMessage = "HTTP Fehler $apiStatusCode ($apiStatusDescription): $apiErrorMessage"
                if ($apiStatusCode -eq 404) { 
                    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FEHLER: Laptop '$AliasName' ist beim Server nicht registriert oder die Kennung ist unbekannt. ($CommandUrl). Skript wird für längere Zeit pausieren."
                    Start-Sleep -Seconds 3600 
                } else {
                    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler beim Abrufen von Befehlen: $apiErrorMessage"
                }
            } else {
                Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Fehler beim Abrufen von Befehlen (keine HTTP-Antwort oder anderer Fehler): $apiErrorMessage"
            }
            if (($null -eq $_.Exception.Response) -or ($_.Exception.Response.StatusCode.Value__ -ne 404)) {
                Start-Sleep -Seconds ($PollingIntervalSeconds * 2) 
            }
        }
        
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Warte $PollingIntervalSeconds Sekunden bis zum nächsten Poll..."
        Start-Sleep -Seconds $PollingIntervalSeconds
    }
}
catch {
    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Ein unerwarteter Fehler ist in der Hauptschleife aufgetreten: $($_.Exception.Message). Skript wird beendet."
    exit 1 
}