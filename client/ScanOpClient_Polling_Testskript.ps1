<#
.SYNOPSIS
    Minimales Testskript zum Senden eines Scan-Report-Payloads an den ScanOp-Server.
.DESCRIPTION
    Dieses Skript sendet einen fest kodierten JSON-Payload an den
    /api/v1/scanreports/ Endpunkt, um die grundlegende Sendefunktionalität
    und Fehlerbehandlung von Invoke-RestMethod zu testen.
#>

# --- Konfiguration (Anpassen, falls nötig) ---
$AliasName = "TestClientAlias" # Ein Alias, der auf dem Server bekannt sein sollte, oder zum Testen neu anlegen
$ReportUrl = "http://192.168.2.134:8000/api/v1/scanreports/" # Ihre Server-URL
# $ApiKey = "DEIN_GEHEIMER_API_SCHLUESSEL_HIER" # Optional, falls benötigt

# --- Fest kodierter Test-Payload (korrekte flache Struktur) ---
$testPayloadObject = @{
    laptop_identifier = $AliasName
    client_scan_time = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") # Aktuelle UTC-Zeit
    scan_type = "TestPayloadScript"
    scan_result_message = "Dies ist ein Testbericht vom minimalen PowerShell-Skript."
    threats_found = $false # Muss ein [bool] sein, nicht der String "false"
    threat_details = $null
}

$payloadBodyJson = $testPayloadObject | ConvertTo-Json -Depth 5 -Compress
Write-Host "DEBUG: Zu sendender JSON-Payload:"
Write-Host $payloadBodyJson
Write-Host "---"

# --- Sendevorgang ---
$requestHeaders = @{
    "Content-Type" = "application/json"
}
# if ($ApiKey) { $requestHeaders.Add("X-API-Key", $ApiKey) }

Write-Host "INFO: Sende Test-Payload an: $ReportUrl"

$statusCode = 0
$responseVariable = $null
$requestError = $null

# Wichtig: $ErrorActionPreference auf 'Stop' setzen, damit der Catch-Block bei Fehlern greift.
# Alternativ direkt -ErrorAction Stop bei Invoke-RestMethod verwenden.
$ErrorActionPreference = "Stop" 

try {
    Write-Host "DEBUG: Vor Invoke-RestMethod..."
    Invoke-RestMethod -Uri $ReportUrl -Method Post -Body $payloadBodyJson -Headers $requestHeaders -StatusCodeVariable statusCode -ErrorVariable requestError -OutVariable responseVariable -TimeoutSec 30 
    Write-Host "DEBUG: Nach Invoke-RestMethod (innerhalb try)."
    Write-Host "DEBUG: Status Code vom Server: $statusCode"

    if ($statusCode -ge 200 -and $statusCode -lt 300) {
        Write-Host "ERFOLG: Payload erfolgreich gesendet! Status: $statusCode"
        if ($responseVariable) {
            Write-Host "Server-Antwort:"
            Write-Host ($responseVariable | ConvertTo-Json -Depth 3 -Compress)
        }
    } else {
        # Dieser Block wird seltener erreicht, wenn ErrorActionPreference = "Stop" ist,
        # da die meisten Fehler eine Exception auslösen.
        Write-Warning "WARNUNG: Server antwortete mit Status $statusCode (nicht 2xx), aber keine Exception wurde ausgelöst."
        if ($responseVariable) {
            Write-Warning "Antwort-Body (Fehler): $($responseVariable | Out-String)"
        }
        if ($requestError) {
             Write-Warning "RequestError: $($requestError[0].ToString())"
        }
    }
}
catch {
    Write-Error "FEHLER: Exception beim Senden des Payloads!"
    Write-Error "Exception Typ: $($_.Exception.GetType().FullName)"
    Write-Error "Exception Nachricht: $($_.Exception.Message)"
    
    if ($_.Exception -is [System.Net.WebException]) {
        $webEx = $_.Exception
        Write-Error "Status der WebException: $($webEx.Status)"
        if ($null -ne $webEx.Response) {
            $httpResponse = $webEx.Response
            $responseStatusCode = [int]$httpResponse.StatusCode
            Write-Error "HTTP Status Code: $responseStatusCode"
            
            try {
                $responseStream = $httpResponse.GetResponseStream()
                if ($responseStream.CanRead) {
                    $streamReader = New-Object System.IO.StreamReader($responseStream)
                    $errorBody = $streamReader.ReadToEnd()
                    $streamReader.Close()
                    Write-Error "Fehlerhafter Antwort-Body vom Server:"
                    Write-Error $errorBody
                } else {
                    Write-Warning "Antwort-Stream des Fehlers nicht lesbar."
                }
                $responseStream.Close()
            } catch {
                Write-Warning "Konnte Fehler-Body nicht auslesen: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Die WebException enthält kein Response-Objekt."
        }
    }
    # Ausgabe des vollständigen Fehlerobjekts für detaillierte Analyse
    Write-Error "Vollständiges Fehlerobjekt (`$_`):"
    Write-Output ($_ | Format-List * -Force | Out-String)
}
finally {
    Write-Host "INFO: Test-Skript beendet. Letzter bekannter Statuscode: $statusCode"
    # Setze ErrorActionPreference zurück, falls es global geändert wurde
    # (In diesem kleinen Skript nicht unbedingt nötig, aber gute Praxis für größere Skripte)
    # Restore-ErrorActionPreference # (Wenn man eine Funktion dafür hätte)
}