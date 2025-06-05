// static/app.js

document.addEventListener('DOMContentLoaded', () => {
    const statusMessageDiv = document.getElementById('status-message');

    function showStatusMessage(message, type = 'info') {
        if (!statusMessageDiv) return;
        statusMessageDiv.textContent = message;
        statusMessageDiv.style.display = 'block';
        statusMessageDiv.className = ''; 
        const typeToClass = { success: 'status-success', error: 'status-error', info: 'status-info'};
        statusMessageDiv.classList.add(typeToClass[type] || 'status-info');
        if (type !== 'error') {
            setTimeout(() => {
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
            const actionsCell = row.querySelector('.actions-cell');
            if (commandCell) {
                commandCell.textContent = command ? `${command} (${scanType || ''})`.trim() : 'Kein';
            }
            // Ggf. "Befehl abbrechen"-Button ein-/ausblenden
            if (actionsCell) {
                let cancelButton = actionsCell.querySelector(`.cancel-command-button[data-laptop-alias="${laptopAlias}"]`);
                if (command && !cancelButton) { // Befehl ist da, Button fehlt -> erstellen
                    cancelButton = document.createElement('button');
                    cancelButton.className = 'cancel-command-button';
                    cancelButton.dataset.laptopAlias = laptopAlias;
                    cancelButton.title = 'Aktuellen Befehl abbrechen';
                    cancelButton.textContent = 'Bef. X';
                    actionsCell.insertBefore(cancelButton, actionsCell.querySelector('.delete-laptop-button')); // Vor Löschen-Button einfügen
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
                        setTimeout(() => window.location.reload(), 1500); // Bei "all" die Seite neu laden
                    }
                } else {
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            } finally {
                setTimeout(() => disableAllActionButtons(false), 1500);
            }
        });
    });

    // Funktion zum Anhängen von Cancel-Listenern (wird für dynamisch erstellte Buttons benötigt)
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
                const response = await fetch(apiUrl, { method: 'POST' }); // Kein Body nötig
                const result = await response.json();
                if (response.ok) {
                    showStatusMessage(`Erfolg: ${result.message}`, 'success');
                    if (!isForAll) {
                        updatePendingCommandInUI(laptopAlias, null, null);
                    } else {
                        setTimeout(() => window.location.reload(), 1500);
                    }
                } else {
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            } finally {
                setTimeout(() => disableAllActionButtons(false), 1500);
            }
        });
    }
    // Ursprüngliche Cancel-Buttons
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
                // DELETE gibt oft 204 No Content zurück, daher nicht unbedingt .json()
                if (response.ok) { // 200-299
                    showStatusMessage(`Laptop ${laptopAlias} erfolgreich gelöscht.`, 'success');
                    document.getElementById(`laptop-row-${laptopAlias}`)?.remove();
                     // Wenn keine Laptops mehr da sind, Meldung anzeigen (optional)
                    if (document.querySelectorAll('table tbody tr').length === 0) {
                        const mainContent = document.querySelector('main');
                        const noLaptopsMsg = document.createElement('p');
                        noLaptopsMsg.textContent = 'Keine Laptops registriert.';
                        document.querySelector('table')?.remove(); // Tabelle entfernen
                        mainContent.insertBefore(noLaptopsMsg, mainContent.querySelector('hr')); // Vor den globalen Aktionen
                    }
                } else {
                    const result = await response.json().catch(() => ({ detail: `Fehler ${response.status} ${response.statusText}` }));
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            } finally {
                setTimeout(() => disableAllActionButtons(false), 1500);
            }
        });
    });


    // Auto-Refresh Polling (bleibt wie zuvor)
    let lastKnownUpdateTime = null; 
    const POLLING_INTERVAL = 30000; 
    let pollingTimeoutId = null; 

    async function checkForUpdates() {
        try {
            const response = await fetch('/api/v1/reports/last_update_timestamp');
            if (!response.ok) { scheduleNextCheck(); return; }
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
                showStatusMessage('Änderungen bei Reports erkannt. Seite wird aktualisiert...', 'info');
                if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
                setTimeout(() => window.location.reload(), 2000);
                return;
            }
        } catch (error) { /* Fehler still behandeln, um Polling nicht zu unterbrechen */ }
        scheduleNextCheck();
    }

    function scheduleNextCheck() {
        if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
        pollingTimeoutId = setTimeout(checkForUpdates, POLLING_INTERVAL);
    }

    if (document.querySelector('table[data-sortable]')) {
       setTimeout(checkForUpdates, 5000); // Erster Check etwas verzögert
    }
});