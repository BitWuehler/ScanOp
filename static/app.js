// static/app.js

document.addEventListener('DOMContentLoaded', () => {
    const statusMessageDiv = document.getElementById('status-message');

    // --- Hilfsfunktionen ---
    function showStatusMessage(message, type = 'info') {
        if (!statusMessageDiv) {
            console.warn("Status message div nicht gefunden!");
            return;
        }
        statusMessageDiv.textContent = message;
        statusMessageDiv.style.display = 'block';
        statusMessageDiv.className = ''; // Alte Klassen entfernen
        const typeToClass = { success: 'status-success', error: 'status-error', info: 'status-info'};
        statusMessageDiv.classList.add(typeToClass[type] || 'status-info');

        // Nachricht nach einiger Zeit ausblenden, außer es ist ein Fehler
        if (type !== 'error') {
            setTimeout(() => {
                // Nur ausblenden, wenn es noch dieselbe Nachricht ist (um Überschreiben zu vermeiden)
                if (statusMessageDiv.textContent === message) {
                    statusMessageDiv.style.display = 'none';
                }
            }, 7000);
        }
    }

    function updatePendingCommandInUI(laptopAlias, command, scanType) {
        const row = document.getElementById(`laptop-row-${laptopAlias}`);
        if (row) {
            const commandCell = row.querySelector('.pending-command-cell');
            const actionsCell = row.querySelector('.actions-cell'); // Zelle mit den Aktionsbuttons

            if (commandCell) {
                commandCell.textContent = command ? `${command} (${scanType || ''})`.trim() : 'Kein';
            }

            if (actionsCell) {
                let cancelButton = actionsCell.querySelector(`.cancel-command-button[data-laptop-alias="${laptopAlias}"]`);
                if (command && !cancelButton) { // Befehl ist da, Button fehlt -> erstellen
                    cancelButton = document.createElement('button');
                    cancelButton.className = 'cancel-command-button';
                    cancelButton.dataset.laptopAlias = laptopAlias;
                    cancelButton.title = 'Aktuellen Befehl abbrechen';
                    cancelButton.textContent = 'Bef. X';
                    // Füge den Button vor dem Löschen-Button ein, falls vorhanden, sonst am Ende
                    const deleteButton = actionsCell.querySelector('.delete-laptop-button');
                    if (deleteButton) {
                        actionsCell.insertBefore(cancelButton, deleteButton);
                    } else {
                        actionsCell.appendChild(cancelButton);
                    }
                    attachCancelListener(cancelButton); // Neuen Listener anhängen
                } else if (!command && cancelButton) { // Kein Befehl, Button ist da -> entfernen
                    cancelButton.remove();
                }
            }
        }
    }
    
    function disableAllActionButtons(disable = true) {
        document.querySelectorAll('.scan-button, .cancel-command-button, .delete-laptop-button').forEach(btn => {
            btn.disabled = disable;
        });
    }

    function formatUtcToLocalDateTime(utcDateString) {
        if (!utcDateString || utcDateString.trim() === 'N/A' || utcDateString.trim() === '') {
            return 'N/A';
        }
        try {
            const date = new Date(utcDateString); 
            if (isNaN(date.getTime())) { 
                return 'Ungült. Datum';
            }
            const options = {
                year: 'numeric', month: '2-digit', day: '2-digit',
                hour: '2-digit', minute: '2-digit', second: '2-digit',
            };
            return date.toLocaleString(undefined, options); 
        } catch (e) {
            console.error("Error formatting date:", utcDateString, e);
            return utcDateString; 
        }
    }

    function convertTableDateTimes() {
        // Für Laptop-Übersicht und Tagesbericht
        document.querySelectorAll('td.date-cell').forEach(cell => {
            const utcTime = cell.dataset.utcTime;
            if (utcTime) {
                cell.textContent = formatUtcToLocalDateTime(utcTime);
                cell.title = `UTC: ${utcTime}`;
            }
        });

        // Generische Konverter für andere Elemente mit .convert-utc-date
        document.querySelectorAll('.convert-utc-date').forEach(element => {
            const originalUtc = element.dataset.utcTime || element.textContent.trim();
            if (originalUtc && originalUtc !== 'N/A' && originalUtc !== '') {
                 // Einfache Prüfung, ob es wie ein ISO-String mit Zeitzone aussieht
                if (originalUtc.includes('T') && (originalUtc.includes('Z') || originalUtc.includes('+') || originalUtc.includes('-'))) {
                    element.textContent = formatUtcToLocalDateTime(originalUtc);
                    element.title = `UTC: ${originalUtc}`;
                }
            }
        });
    }

    // --- Event Listeners für Buttons ---
    // Scan-Buttons
    document.querySelectorAll('.scan-button').forEach(button => {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.laptopAlias;
            const scanType = this.dataset.scanType;
            const apiUrl = `/api/v1/clientcommands/trigger_scan/${laptopAlias}`;

            disableAllActionButtons(true);
            showStatusMessage(`Sende Befehl: ${scanType} für ${laptopAlias === 'all' ? 'ALLE Laptops' : laptopAlias}...`, 'info');

            try {
                const response = await fetch(apiUrl, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ scan_type: scanType })
                });
                const result = await response.json();
                if (response.ok) {
                    showStatusMessage(`Erfolg: ${result.message}`, 'success');
                    if (laptopAlias !== 'all') {
                        updatePendingCommandInUI(laptopAlias, "START_SCAN", scanType);
                    } else {
                        // Bei "all" die Seite neu laden, um alle Updates zu sehen
                        showStatusMessage(`Erfolg: ${result.message}. Seite wird neu geladen...`, 'success');
                        setTimeout(() => window.location.reload(), 1500); 
                    }
                } else {
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                console.error("Scan-Button Fehler:", error);
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            } finally {
                setTimeout(() => disableAllActionButtons(false), 1500);
            }
        });
    });

    // Funktion zum Anhängen von Cancel-Listenern
    function attachCancelListener(button) {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.laptopAlias;
            const isForAll = laptopAlias === 'all';
            const confirmationMessage = isForAll ? 
                "Wollen Sie wirklich die Befehle für ALLE Laptops abbrechen?" :
                `Wollen Sie wirklich den Befehl für Laptop ${laptopAlias} abbrechen?`;

            if (!confirm(confirmationMessage)) return;

            const apiUrl = `/api/v1/clientcommands/cancel_command/${laptopAlias}`;
            disableAllActionButtons(true);
            showStatusMessage(`Breche Befehl(e) ab für ${isForAll ? 'ALLE Laptops' : laptopAlias}...`, 'info');

            try {
                const response = await fetch(apiUrl, { method: 'POST' }); 
                const result = await response.json();
                if (response.ok) {
                    showStatusMessage(`Erfolg: ${result.message}`, 'success');
                    if (!isForAll) {
                        updatePendingCommandInUI(laptopAlias, null, null);
                    } else {
                        showStatusMessage(`Erfolg: ${result.message}. Seite wird neu geladen...`, 'success');
                        setTimeout(() => window.location.reload(), 1500);
                    }
                } else {
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                console.error("Cancel-Command Fehler:", error);
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            } finally {
                setTimeout(() => disableAllActionButtons(false), 1500);
            }
        });
    }
    // Ursprüngliche Cancel-Buttons (beim Laden der Seite vorhanden)
    document.querySelectorAll('.cancel-command-button').forEach(attachCancelListener);


    // Laptop löschen Buttons
    document.querySelectorAll('.delete-laptop-button').forEach(button => {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.laptopAlias;
            if (!confirm(`Wollen Sie Laptop ${laptopAlias} wirklich unwiderruflich löschen? Alle zugehörigen Berichte werden ebenfalls entfernt.`)) {
                return;
            }

            const apiUrl = `/api/v1/laptops/${laptopAlias}`;
            disableAllActionButtons(true);
            showStatusMessage(`Lösche Laptop ${laptopAlias}...`, 'info');

            try {
                const response = await fetch(apiUrl, { method: 'DELETE' });
                if (response.ok) { // HTTP 204 No Content ist auch response.ok
                    showStatusMessage(`Laptop ${laptopAlias} erfolgreich gelöscht.`, 'success');
                    document.getElementById(`laptop-row-${laptopAlias}`)?.remove();
                    if (document.querySelectorAll('table.sortable-theme-bootstrap tbody tr').length === 0) {
                        const mainContent = document.querySelector('main');
                        const noLaptopsMsg = document.createElement('p');
                        noLaptopsMsg.textContent = 'Keine Laptops registriert.';
                        document.querySelector('table.sortable-theme-bootstrap')?.remove(); 
                        if(mainContent) { // Stelle sicher, dass mainContent existiert
                           const hrElement = mainContent.querySelector('hr');
                           if (hrElement) {
                               mainContent.insertBefore(noLaptopsMsg, hrElement);
                           } else {
                               mainContent.appendChild(noLaptopsMsg); // Fallback
                           }
                        }
                    }
                } else {
                    const result = await response.json().catch(() => ({ detail: `Fehler ${response.status} ${response.statusText || '(Keine weitere Info)'}` }));
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                console.error("Delete-Laptop Fehler:", error);
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            } finally {
                setTimeout(() => disableAllActionButtons(false), 1500);
            }
        });
    });

    // --- Export-Funktionen für Tagesbericht ---
    // Der CSV-Export wird nun serverseitig über einen Link gesteuert.
    // Der entsprechende Javascript-Code wurde entfernt.

    // Der PDF-Export bleibt clientseitig:
    const exportPdfBtn = document.getElementById('export-pdf-btn');
    const reportTable = document.getElementById('daily-report-table');

    if (exportPdfBtn && reportTable && window.jspdf && window.jspdf.jsPDF) {
        exportPdfBtn.addEventListener('click', () => {
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF({ orientation: "landscape" }); // Querformat für breitere Tabellen
            
            const reportTitle = document.querySelector('main h2')?.textContent || "ScanOp Tagesbericht";
            doc.setFontSize(18);
            doc.text(reportTitle, 14, 20);
            doc.setFontSize(11); // Reset für Tabelleninhalt

            const tableData = [];
            const headers = [];
            reportTable.querySelectorAll('thead th').forEach(th => headers.push(th.textContent.trim()));
            tableData.push(headers);

            reportTable.querySelectorAll('tbody tr').forEach(row => {
                const rowData = [];
                row.querySelectorAll('td').forEach(cell => {
                    let cellText = cell.textContent.trim();
                     if (cell.classList.contains('date-cell') && cell.dataset.utcTime) {
                        cellText = formatUtcToLocalDateTime(cell.dataset.utcTime);
                    }
                    rowData.push(cellText);
                });
                tableData.push(rowData);
            });
            
            doc.autoTable({
                head: [tableData[0]], // Nur die Header-Zeile für den Kopf
                body: tableData.slice(1), // Rest für den Body
                startY: 30,
                theme: 'grid',
                headStyles: { fillColor: [41, 128, 185], textColor: 255, fontStyle: 'bold' },
                alternateRowStyles: { fillColor: [245, 245, 245] },
            });

            let reportDateStr = 'bericht';
            const reportDateElement = document.querySelector('main h2');
            if (reportDateElement && reportDateElement.textContent.includes(' am ')) {
                reportDateStr = reportDateElement.textContent.split(' am ')[1] || 'bericht';
            }
            doc.save(`scanop_tagesbericht_${reportDateStr.replace(/\./g, '-')}.pdf`);
        });
    } else if (exportPdfBtn) {
        console.warn("jsPDF oder jsPDF-AutoTable nicht geladen. PDF-Export nicht verfügbar.");
        exportPdfBtn.disabled = true;
        exportPdfBtn.title = "PDF-Bibliothek nicht geladen";
    }
    
    // Initial Datumsformatierung aufrufen (wenn relevante Tabellen da sind)
    if (document.querySelector('table.sortable-theme-bootstrap') || document.getElementById('daily-report-table')) {
        convertTableDateTimes();
    }

    // Auto-Refresh Polling
    let lastKnownUpdateTime = null; 
    const POLLING_INTERVAL = 30000; 
    let pollingTimeoutId = null; 

    async function checkForUpdates() {
        try {
            const response = await fetch('/api/v1/reports/last_update_timestamp');
            if (!response.ok) { 
                console.warn(`Polling: Fehler beim Abrufen des Update-Status (${response.status})`);
                scheduleNextCheck(); 
                return; 
            }
            const data = await response.json();

            if (data.last_update) {
                if (lastKnownUpdateTime === null) {
                    lastKnownUpdateTime = data.last_update;
                } else if (data.last_update !== lastKnownUpdateTime) {
                    showStatusMessage('Neue Scan-Berichte verfügbar. Seite wird aktualisiert...', 'info');
                    if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
                    setTimeout(() => window.location.reload(), 2000);
                    return; 
                }
            } else if (lastKnownUpdateTime !== null && data.last_update === null) {
                showStatusMessage('Änderungen bei Reports erkannt (möglicherweise gelöscht). Seite wird aktualisiert...', 'info');
                if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
                setTimeout(() => window.location.reload(), 2000);
                return;
            }
        } catch (error) { 
            console.error('Polling-Fehler:', error);
        }
        scheduleNextCheck();
    }

    function scheduleNextCheck() {
        if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
        pollingTimeoutId = setTimeout(checkForUpdates, POLLING_INTERVAL);
    }

    // Polling nur starten, wenn wir auf der Laptop-Übersicht sind
    if (document.querySelector('table.sortable-theme-bootstrap')) {
       setTimeout(checkForUpdates, 5000); // Erster Check etwas verzögert
    }
});