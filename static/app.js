// static/app.js

document.addEventListener('DOMContentLoaded', () => {
    const scanButtons = document.querySelectorAll('.scan-button');
    const statusMessageDiv = document.getElementById('status-message');

    scanButtons.forEach(button => {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.laptopAlias; // 'all' oder spezifischer Alias
            const scanType = this.dataset.scanType;
            const apiUrl = `/api/v1/clientcommands/trigger_scan/${laptopAlias}`;

            // Deaktiviere alle Buttons, um doppelte Klicks zu verhindern
            scanButtons.forEach(btn => btn.disabled = true);
            showStatusMessage(`Sende Befehl: ${scanType} für ${laptopAlias === 'all' ? 'ALLE Laptops' : laptopAlias}...`, 'info');

            try {
                const response = await fetch(apiUrl, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        // Hier könnte später ein API-Key oder Auth-Token hinzukommen
                    },
                    body: JSON.stringify({ scan_type: scanType })
                });

                const result = await response.json(); // Versuche immer, JSON zu parsen

                if (response.ok) {
                    showStatusMessage(`Erfolg: ${result.message}`, 'success');
                    // UI aktualisieren, um den neuen pending_command anzuzeigen
                    if (laptopAlias !== 'all') {
                        updatePendingCommandInUI(laptopAlias, "START_SCAN", scanType);
                    } else {
                        // Bei "all" müssen wir die Seite neu laden oder alle einzeln aktualisieren (komplexer)
                        // Fürs Erste eine allgemeine Meldung und späterer Reload durch Polling
                        showStatusMessage(`Erfolg: ${result.message}. Die Übersicht wird bei Bedarf automatisch aktualisiert.`, 'success');
                        // Ein direkter Reload hier ist vielleicht nicht ideal, da das Polling das übernehmen kann.
                    }
                } else {
                    // response.json() könnte hier einen Fehler werfen, wenn Body kein JSON ist
                    // Besser: result.detail oder generische Nachricht
                    const errorMessage = result.detail || `Serverantwort: ${response.statusText || 'Unbekannter Fehler'}`;
                    showStatusMessage(`Fehler (${response.status}): ${errorMessage}`, 'error');
                }

            } catch (error) {
                console.error('Fehler beim Senden des Scan-Befehls:', error);
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar beim Senden des Befehls.', 'error');
            } finally {
                // Aktiviere Buttons wieder nach einer kurzen Verzögerung,
                // um dem Benutzer Zeit zu geben, die Nachricht zu lesen
                setTimeout(() => {
                    scanButtons.forEach(btn => btn.disabled = false);
                }, 2000);
            }
        });
    });

    function showStatusMessage(message, type = 'info') { // type kann 'info', 'success', 'error' sein
        if (!statusMessageDiv) {
            console.warn("Status message div not found!");
            return;
        }
        statusMessageDiv.textContent = message;
        statusMessageDiv.style.display = 'block';
        statusMessageDiv.className = ''; // Alte Klassen entfernen

        if (type === 'success') {
            statusMessageDiv.classList.add('status-success');
        } else if (type === 'error') {
            statusMessageDiv.classList.add('status-error');
        } else { // 'info' oder default
            statusMessageDiv.classList.add('status-info');
        }
        // Nachricht nach einiger Zeit ausblenden, außer es ist ein Fehler, der vielleicht länger sichtbar sein soll
        if (type !== 'error') {
            setTimeout(() => {
                if (statusMessageDiv.textContent === message) { // Nur ausblenden, wenn es noch dieselbe Nachricht ist
                    statusMessageDiv.style.display = 'none';
                }
            }, 7000);
        }
    }

    function updatePendingCommandInUI(laptopAlias, command, scanType) {
        const row = document.getElementById(`laptop-row-${laptopAlias}`);
        if (row) {
            const commandCell = row.querySelector('.pending-command-cell');
            if (commandCell) {
                commandCell.textContent = `${command} (${scanType})`;
            }
        }
    }


    // --- Auto-Refresh Polling ---
    let lastKnownUpdateTime = null; // Speichert den Zeitstempel des letzten bekannten Updates als ISO-String
    const POLLING_INTERVAL = 30000; // 30 Sekunden
    let pollingTimeoutId = null; // Um den Timeout zu steuern

    async function checkForUpdates() {
        console.log("Checking for updates...");
        try {
            const response = await fetch('/api/v1/reports/last_update_timestamp'); // Sicherstellen, dass der Endpunkt existiert
            if (!response.ok) {
                console.error('Fehler beim Abrufen des Update-Status:', response.status, response.statusText);
                // Bei Fehlern nicht sofort neu pollen, sondern normalen Intervall abwarten
                scheduleNextCheck();
                return;
            }
            const data = await response.json();

            if (data.last_update) { // data.last_update ist ein ISO-String oder null
                if (lastKnownUpdateTime === null) {
                    // Erster Check, Zeitstempel speichern
                    lastKnownUpdateTime = data.last_update;
                    console.log("Initial last_update time set to:", lastKnownUpdateTime);
                } else if (data.last_update !== lastKnownUpdateTime) {
                    // Es gab ein Update! Seite neu laden.
                    console.log("Neuer Report erkannt! Server-Update:", data.last_update, "Bekannt war:", lastKnownUpdateTime, "Lade Seite neu.");
                    showStatusMessage('Neue Scan-Berichte verfügbar. Seite wird aktualisiert...', 'info');
                    // Polling stoppen, bevor die Seite neu geladen wird
                    if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
                    setTimeout(() => {
                        window.location.reload();
                    }, 2000); // Kurze Verzögerung, damit Benutzer die Nachricht sieht
                    return; // Wichtig: Kein scheduleNextCheck() hier, da die Seite neu geladen wird
                } else {
                    console.log("Keine neuen Updates seit:", lastKnownUpdateTime);
                }
            } else if (lastKnownUpdateTime !== null && data.last_update === null) {
                // Alle Reports wurden gelöscht, oder es gab nie welche und jetzt auch nicht
                // Dies könnte auch ein valider Zustand sein, der ein Neuladen rechtfertigt,
                // falls die UI auf 'keine Reports' umspringen soll.
                console.log("Reports scheinen gelöscht/nicht vorhanden zu sein. Server-Update: null. Bekannt war:", lastKnownUpdateTime, "Lade Seite neu.");
                showStatusMessage('Änderungen bei Reports erkannt (möglicherweise gelöscht). Seite wird aktualisiert...', 'info');
                if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
                setTimeout(() => {
                    window.location.reload();
                }, 2000);
                return;
            } else {
                // lastKnownUpdateTime ist null und data.last_update ist auch null -> keine Reports, keine Änderung
                console.log("Keine Reports vorhanden, keine Änderung.");
            }

        } catch (error) {
            console.error('Fehler beim Polling für Updates:', error);
            // Bei Netzwerkfehlern etc. nicht sofort neu pollen
        }
        // Nächsten Check planen, egal was passiert ist (außer bei Reload)
        scheduleNextCheck();
    }

    function scheduleNextCheck() {
        // Sicherstellen, dass nicht mehrere Timeouts parallel laufen
        if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
        pollingTimeoutId = setTimeout(checkForUpdates, POLLING_INTERVAL);
        console.log(`Nächster Update-Check geplant in ${POLLING_INTERVAL / 1000} Sekunden.`);
    }

    // Polling nur starten, wenn wir auf der richtigen Seite sind
    if (document.querySelector('table[data-sortable]')) { // Prüft, ob die sortierbare Tabelle existiert (Indikator für Laptop-Übersicht)
       console.log("Laptop Übersicht erkannt, starte Auto-Update Polling.");
       scheduleNextCheck(); // Startet den ersten Check nach POLLING_INTERVAL (oder sofort, wenn man es so will)
       // Für einen sofortigen ersten Check (nach kurzer Initialisierung):
       // setTimeout(checkForUpdates, 2000); // Erster Check nach 2 Sekunden
    }
});