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
            if (actionsCell) {
                let cancelButton = actionsCell.querySelector(`.cancel-command-button[data-laptop-alias="${laptopAlias}"]`);
                if (command && !cancelButton) {
                    cancelButton = document.createElement('button');
                    cancelButton.className = 'cancel-command-button';
                    cancelButton.dataset.laptopAlias = laptopAlias;
                    cancelButton.title = 'Aktuellen Befehl abbrechen';
                    cancelButton.textContent = 'Bef. X';
                    const deleteButton = actionsCell.querySelector('.delete-laptop-button');
                    if (deleteButton) {
                        actionsCell.insertBefore(cancelButton, deleteButton);
                    } else {
                        actionsCell.appendChild(cancelButton);
                    }
                    attachCancelListener(cancelButton);
                } else if (!command && cancelButton) {
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
        if (!utcDateString || utcDateString.trim() === '') {
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
                hour12: false, timeZone: 'Europe/Berlin'
            };
            return date.toLocaleString('de-DE', options);
        } catch (e) {
            console.error("Error formatting date:", utcDateString, e);
            return utcDateString;
        }
    }

    function convertTableDateTimes() {
        document.querySelectorAll('td.date-cell').forEach(cell => {
            const utcTime = cell.dataset.utcTime;
            cell.textContent = formatUtcToLocalDateTime(utcTime);
        });
    }

    // --- Event Listeners für Buttons ---
    document.querySelectorAll('.scan-button').forEach(button => {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.laptopAlias;
            const scanType = this.dataset.scanType;
            const apiUrl = `/api/v1/clientcommands/trigger_scan/${encodeURIComponent(laptopAlias)}`;
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
    document.querySelectorAll('.cancel-command-button').forEach(attachCancelListener);

    function attachDeleteListener(button) {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.laptopAlias;
            if (!confirm(`Wollen Sie Laptop ${laptopAlias} wirklich unwiderruflich löschen? Alle zugehörigen Berichte werden ebenfalls entfernt.`)) {
                return;
            }
            const apiUrl = `/api/v1/laptops/${encodeURIComponent(laptopAlias)}`;
            disableAllActionButtons(true);
            showStatusMessage(`Lösche Laptop ${laptopAlias}...`, 'info');
            try {
                const response = await fetch(apiUrl, { method: 'DELETE' });
                if (response.ok) {
                    showStatusMessage(`Laptop ${laptopAlias} erfolgreich gelöscht.`, 'success');
                    document.getElementById(`laptop-row-${laptopAlias}`)?.remove();
                    if (document.querySelectorAll('table.sortable-theme-bootstrap tbody tr').length === 0) {
                        const mainContent = document.querySelector('main');
                        const noLaptopsMsg = document.createElement('p');
                        noLaptopsMsg.textContent = 'Keine Laptops registriert.';
                        document.querySelector('table.sortable-theme-bootstrap')?.remove();
                        if(mainContent) {
                           const hrElement = mainContent.querySelector('hr');
                           if (hrElement) {
                               mainContent.insertBefore(noLaptopsMsg, hrElement);
                           } else {
                               mainContent.appendChild(noLaptopsMsg);
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
    }
    document.querySelectorAll('.delete-laptop-button').forEach(attachDeleteListener);

    function attachUpdateClientListener(button) {
        button.addEventListener('click', async function() {
            const laptopAlias = this.dataset.alias;
            const apiUrl = `/api/v1/clientcommands/trigger_update/${encodeURIComponent(laptopAlias)}`;
            const targetVersion = document.getElementById('settings_github_version')?.value || 'main';
            const repoUrl = document.getElementById('settings_github_repo')?.value || 'https://github.com/BitWuehler/ScanOp';
            this.disabled = true;
            try {
                const response = await fetch(apiUrl, { 
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ repo_url: repoUrl, version: targetVersion })
                });
                const result = await response.json();
                if (response.ok) {
                    // Add shimmer immediately
                    const row = document.getElementById(`laptop-row-${laptopAlias}`);
                    if (row) {
                        const vText = row.querySelector('.version-text');
                        if (vText) vText.classList.add('shimmer-text');
                        this.style.display = 'none';
                    }
                } else {
                    showStatusMessage(`Fehler (${response.status}): ${result.detail || 'Unbekannter Fehler'}`, 'error');
                }
            } catch (error) {
                console.error("Update-Client Fehler:", error);
                showStatusMessage('Netzwerkfehler oder Server nicht erreichbar.', 'error');
            }
        });
    }
    document.querySelectorAll('.update-client-btn').forEach(attachUpdateClientListener);

    const exportPdfBtn = document.getElementById('export-pdf-btn');
    const reportTable = document.getElementById('daily-report-table');

    if (exportPdfBtn && reportTable && window.jspdf && window.jspdf.jsPDF) {
        exportPdfBtn.addEventListener('click', () => {
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF({ orientation: "landscape" });
            const reportTitle = document.querySelector('main h2')?.textContent || "ScanOp Tagesbericht";
            doc.setFontSize(18);
            doc.text(reportTitle, 14, 20);
            doc.setFontSize(11);
            doc.autoTable({
                html: '#daily-report-table',
                startY: 30,
                theme: 'grid',
                headStyles: { fillColor: [41, 128, 185], textColor: 255, fontStyle: 'bold' },
                alternateRowStyles: { fillColor: [245, 245, 245] },
            });
            let reportDateStr = 'bericht';
            const reportDateElement = document.querySelector('main h2');
            if (reportDateElement.textContent.includes(' am ')) {
                reportDateStr = reportDateElement.textContent.split(' am ')[1] || 'bericht';
            }
            doc.save(`scanop_tagesbericht_${reportDateStr.replace(/\./g, '-')}.pdf`);
        });
    } else if (exportPdfBtn) {
        console.warn("jsPDF oder jsPDF-AutoTable nicht geladen. PDF-Export nicht verfügbar.");
        exportPdfBtn.disabled = true;
        exportPdfBtn.title = "PDF-Bibliothek nicht geladen";
    }
    
    // ==========================================
    // UI AND LOGIC OVERHAUL START
    // ==========================================

    // Scroll Position Persistence
    const scrollPos = sessionStorage.getItem('scanop_scroll_pos');
    if (scrollPos !== null) {
        window.scrollTo(0, parseInt(scrollPos, 10));
    }
    window.addEventListener('beforeunload', () => {
        sessionStorage.setItem('scanop_scroll_pos', window.scrollY);
    });

    // Settings Dropdown Logic
    const settingsToggleBtn = document.getElementById('settings-toggle-btn');
    const settingsDropdown = document.getElementById('settings-dropdown');
    if (settingsToggleBtn && settingsDropdown) {
        settingsToggleBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            settingsDropdown.classList.toggle('hidden');
        });
        document.addEventListener('click', (e) => {
            if (!settingsDropdown.contains(e.target) && e.target !== settingsToggleBtn) {
                settingsDropdown.classList.add('hidden');
            }
        });
    }

    // Global Settings (Repo URL & Version)
    const repoInput = document.getElementById('settings_github_repo_url');
    const versionInput = document.getElementById('settings_github_version');

    if (repoInput && versionInput) {
        const savedRepo = localStorage.getItem('scanop_repo_url');
        const savedVersion = localStorage.getItem('scanop_version');
        if (savedRepo) repoInput.value = savedRepo;
        if (savedVersion) versionInput.value = savedVersion;

        repoInput.addEventListener('input', (e) => localStorage.setItem('scanop_repo_url', e.target.value));
        versionInput.addEventListener('input', (e) => localStorage.setItem('scanop_version', e.target.value));
    }

    // Advanced Filtering Logic
    const globalFilterToggle = document.getElementById('global-filter-toggle');
    const filterInput = document.getElementById('table-filter-input');
    const filterBtns = document.querySelectorAll('.filter-btn');

    function applyFilters() {
        const searchTerm = filterInput ? filterInput.value.toLowerCase() : '';
        const rows = document.querySelectorAll('tbody tr');
        
        // Get active button states
        const filters = {};
        filterBtns.forEach(btn => {
            filters[btn.dataset.filter] = btn.dataset.state; // '0', '1', '2'
        });

        const targetVersion = versionInput ? versionInput.value.trim() : '';

        rows.forEach(row => {
            let visible = true;
            const text = row.textContent.toLowerCase();
            
            // 1. Text Search
            if (searchTerm && !text.includes(searchTerm)) {
                visible = false;
            }

            // 2. Button Filters
            if (visible) {
                // 'online' filter
                if (filters['online']) {
                    const isOnline = text.includes('online'); // simple heuristic
                    if (filters['online'] === '1' && !isOnline) visible = false;
                    if (filters['online'] === '2' && isOnline) visible = false;
                }

                // 'bedrohung' filter
                if (filters['bedrohung']) {
                    const hasThreat = text.includes('bedrohung');
                    if (filters['bedrohung'] === '1' && !hasThreat) visible = false;
                    if (filters['bedrohung'] === '2' && hasThreat) visible = false;
                }

                // 'aktuell' filter (Client Updates Page)
                if (filters['aktuell']) {
                    const versionCell = row.querySelector('.version-cell');
                    if (versionCell) {
                        const isCurrent = versionCell.textContent.trim() === targetVersion;
                        if (filters['aktuell'] === '1' && !isCurrent) visible = false;
                        if (filters['aktuell'] === '2' && isCurrent) visible = false;
                    }
                }

                // 'ok' filter
                if (filters['ok']) {
                    const hasOk = text.includes('ok'); // matches 'OK' status
                    if (filters['ok'] === '1' && !hasOk) visible = false;
                    if (filters['ok'] === '2' && hasOk) visible = false;
                }

                // 'warnung' filter
                if (filters['warnung']) {
                    const hasWarning = text.includes('warnung');
                    if (filters['warnung'] === '1' && !hasWarning) visible = false;
                    if (filters['warnung'] === '2' && hasWarning) visible = false;
                }

                // 'fehler' filter
                if (filters['fehler']) {
                    const hasError = text.includes('fehler');
                    if (filters['fehler'] === '1' && !hasError) visible = false;
                    if (filters['fehler'] === '2' && hasError) visible = false;
                }
            }

            if (visible) {
                row.classList.remove('hidden-row');
            } else {
                row.classList.add('hidden-row');
            }
        });
    }

    // Handle Button Clicks (3-State Toggle)
    filterBtns.forEach(btn => {
        btn.addEventListener('click', () => {
            let state = parseInt(btn.dataset.state);
            state = (state + 1) % 3;
            btn.dataset.state = state;
            
            applyFilters();
            
            if (globalFilterToggle && globalFilterToggle.checked) {
                saveGlobalFilterState();
            }
        });
    });

    function saveGlobalFilterState() {
        if (filterInput) localStorage.setItem('scanop_filter_text', filterInput.value);
        const btnStates = {};
        filterBtns.forEach(btn => { btnStates[btn.dataset.filter] = btn.dataset.state; });
        localStorage.setItem('scanop_filter_btns', JSON.stringify(btnStates));
    }

    if (globalFilterToggle) {
        const isGlobalEnabled = localStorage.getItem('scanop_global_filter_enabled') === 'true';
        globalFilterToggle.checked = isGlobalEnabled;

        globalFilterToggle.addEventListener('change', (e) => {
            localStorage.setItem('scanop_global_filter_enabled', e.target.checked);
            if (!e.target.checked) {
                localStorage.removeItem('scanop_filter_text');
                localStorage.removeItem('scanop_filter_btns');
            } else {
                saveGlobalFilterState();
            }
        });
    }

    if (filterInput || filterBtns.length > 0) {
        const isGlobalEnabled = localStorage.getItem('scanop_global_filter_enabled') === 'true';
        if (isGlobalEnabled) {
            if (filterInput) {
                filterInput.value = localStorage.getItem('scanop_filter_text') || '';
            }
            try {
                const savedBtns = JSON.parse(localStorage.getItem('scanop_filter_btns') || '{}');
                filterBtns.forEach(btn => {
                    if (savedBtns[btn.dataset.filter]) {
                        btn.dataset.state = savedBtns[btn.dataset.filter];
                    }
                });
            } catch(e) {}
        }
        
        if (filterInput) {
            filterInput.addEventListener('input', () => {
                applyFilters();
                if (globalFilterToggle && globalFilterToggle.checked) saveGlobalFilterState();
            });
        }
        
        applyFilters(); // Initial filter apply
    }

    // Updates Page Checkbox Logic
    const masterCheckbox = document.getElementById('master-checkbox');
    const laptopCheckboxes = document.querySelectorAll('.laptop-checkbox');
    const selectAllBtn = document.getElementById('select-all-btn');
    const selectOutdatedBtn = document.getElementById('select-outdated-btn');

    if (masterCheckbox) {
        masterCheckbox.addEventListener('change', (e) => {
            laptopCheckboxes.forEach(cb => {
                const row = cb.closest('tr');
                if (!row.classList.contains('hidden-row')) {
                    cb.checked = e.target.checked;
                }
            });
        });
    }

    if (selectAllBtn) {
        selectAllBtn.addEventListener('click', () => {
            laptopCheckboxes.forEach(cb => {
                const row = cb.closest('tr');
                if (!row.classList.contains('hidden-row')) {
                    cb.checked = true;
                }
            });
            if (masterCheckbox) masterCheckbox.checked = true;
        });
    }

    if (selectOutdatedBtn && versionInput) {
        selectOutdatedBtn.addEventListener('click', () => {
            const targetVersion = versionInput.value.trim();
            laptopCheckboxes.forEach(cb => {
                const row = cb.closest('tr');
                if (!row.classList.contains('hidden-row')) {
                    const clientVersion = cb.dataset.version;
                    if (clientVersion !== targetVersion) {
                        cb.checked = true;
                    } else {
                        cb.checked = false;
                    }
                }
            });
            if (masterCheckbox) masterCheckbox.checked = false;
        });
    }

    const triggerUpdateBtn = document.getElementById('trigger-update-btn');
    if (triggerUpdateBtn) {
        triggerUpdateBtn.addEventListener('click', async function() {
            const repoUrl = repoInput ? repoInput.value.trim() : '';
            const version = versionInput ? versionInput.value.trim() : '';
            
            const selectedCheckboxes = document.querySelectorAll('.laptop-checkbox:checked');
            const aliasesToUpdate = Array.from(selectedCheckboxes).map(cb => cb.dataset.alias);

            if (!repoUrl || !version) {
                showStatusMessage('Bitte Repository-URL und Ziel-Version (im Zahnrad-Menü) angeben.', 'error');
                return;
            }

            if (aliasesToUpdate.length === 0) {
                showStatusMessage('Bitte mindestens einen Client auswählen.', 'error');
                return;
            }

            triggerUpdateBtn.disabled = true;

            let successCount = 0;
            let errorCount = 0;

            for (const targetLaptop of aliasesToUpdate) {
                const apiUrl = `/api/v1/clientcommands/trigger_update/${encodeURIComponent(targetLaptop)}`;
                try {
                    const response = await fetch(apiUrl, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ repo_url: repoUrl, version: version })
                    });
                    if (response.ok) {
                        successCount++;
                        const row = document.getElementById(`laptop-row-${targetLaptop}`);
                        if (row) {
                            const vText = row.querySelector('.version-text');
                            if (vText) vText.classList.add('shimmer-text');
                            const updateBtn = row.querySelector('.update-client-btn');
                            if (updateBtn) updateBtn.style.display = 'none';
                        }
                    } else {
                        errorCount++;
                    }
                } catch (error) {
                    errorCount++;
                }
            }

            if (errorCount !== 0) {
                showStatusMessage(`${errorCount} Updates konnten nicht gesendet werden.`, 'warning');
            }
            
            setTimeout(() => { triggerUpdateBtn.disabled = false; }, 2000);
        });
    }

    function setupBulkScanButton(btnId, scanType) {
        const btn = document.getElementById(btnId);
        if (!btn) return;

        btn.addEventListener('click', async function() {
            const selectedCheckboxes = document.querySelectorAll('.laptop-checkbox:checked');
            const aliasesToUpdate = Array.from(selectedCheckboxes).map(cb => cb.dataset.alias);

            if (aliasesToUpdate.length === 0) {
                showStatusMessage('Bitte mindestens einen Client auswählen.', 'error');
                return;
            }

            btn.disabled = true;
            showStatusMessage(`Sende ${scanType}-Befehl für ${aliasesToUpdate.length} Laptop(s)...`, 'info');

            let successCount = 0;
            let errorCount = 0;

            for (const targetLaptop of aliasesToUpdate) {
                const apiUrl = `/api/v1/clientcommands/trigger_scan/${encodeURIComponent(targetLaptop)}`;
                try {
                    const response = await fetch(apiUrl, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ scan_type: scanType })
                    });
                    if (response.ok) {
                        successCount++;
                        updatePendingCommandInUI(targetLaptop, "START_SCAN", scanType);
                    } else {
                        errorCount++;
                    }
                } catch (error) {
                    errorCount++;
                }
            }

            if (errorCount === 0) {
                showStatusMessage(`Erfolg: ${scanType}-Befehl für ${successCount} Laptop(s) gesendet!`, 'success');
            } else {
                showStatusMessage(`${successCount} erfolgreich, ${errorCount} fehlerhaft.`, 'warning');
            }
            
            setTimeout(() => { btn.disabled = false; }, 2000);
        });
    }

    setupBulkScanButton('trigger-quickscan-btn', 'QuickScan');
    setupBulkScanButton('trigger-fullscan-btn', 'FullScan');

    convertTableDateTimes();

    // Auto-Refresh Polling
    let lastKnownUpdateTime = null; 
    const POLLING_INTERVAL = 30000; 
    let pollingTimeoutId = null; 

    async function checkForUpdates() {
        try {
            // KORREKTUR: Dies ist jetzt der endgültige, korrekte Pfad
            const response = await fetch('/api/v1/scanreports/last_update_timestamp');
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
                refreshTableSoft();
                return;
            }
        } catch (error) { 
            console.error('Polling-Fehler:', error);
        }
        scheduleNextCheck();
    }

    async function refreshTableSoft() {
        try {
            const response = await fetch(window.location.href);
            const text = await response.text();
            const parser = new DOMParser();
            const doc = parser.parseFromString(text, 'text/html');
            
            const newRows = doc.querySelectorAll('tbody tr');
            const currentTbody = document.querySelector('tbody');
            if (!currentTbody) return;
            
            newRows.forEach(newRow => {
                const alias = newRow.id;
                if (!alias) return;
                const existingRow = document.getElementById(alias);
                
                if (existingRow) {
                    const existingCells = Array.from(existingRow.querySelectorAll('td'));
                    const newCells = Array.from(newRow.querySelectorAll('td'));
                    
                    for (let i = 0; i < existingCells.length; i++) {
                        // Skip checkbox cell to preserve checked state
                        if (existingCells[i].querySelector('input[type="checkbox"]')) {
                            const existingCb = existingCells[i].querySelector('input[type="checkbox"]');
                            const newCb = newCells[i].querySelector('input[type="checkbox"]');
                            if (existingCb && newCb && existingCb.dataset.version) {
                                existingCb.dataset.version = newCb.dataset.version;
                            }
                            continue;
                        }
                        
                        // Update innerHTML if changed
                        if (existingCells[i].innerHTML !== newCells[i].innerHTML) {
                            const wasShimmering = existingCells[i].querySelector('.shimmer-text') !== null;
                            const isShimmeringNow = newCells[i].querySelector('.shimmer-text') !== null;
                            
                            existingCells[i].innerHTML = newCells[i].innerHTML;
                            
                            // Success animation if shimmer was removed
                            if (wasShimmering && !isShimmeringNow) {
                                const vText = existingCells[i].querySelector('.version-text');
                                if (vText) {
                                    vText.classList.add('update-success');
                                    setTimeout(() => vText.classList.remove('update-success'), 3000);
                                }
                            }
                            
                            // Reattach listeners if needed
                            existingCells[i].querySelectorAll('.cancel-command-button').forEach(attachCancelListener);
                            existingCells[i].querySelectorAll('.delete-laptop-button').forEach(btn => attachDeleteListener(btn));
                            existingCells[i].querySelectorAll('.update-client-btn').forEach(btn => attachUpdateClientListener(btn));
                        }
                        // Update classes
                        if (existingCells[i].className !== newCells[i].className) {
                            existingCells[i].className = newCells[i].className;
                        }
                    }
                } else {
                    currentTbody.appendChild(newRow);
                    // Attach listeners to new row
                    newRow.querySelectorAll('.cancel-command-button').forEach(attachCancelListener);
                    newRow.querySelectorAll('.update-client-btn').forEach(attachUpdateClientListener);
                }
            });
            
            // Remove deleted rows
            const existingRows = document.querySelectorAll('tbody tr');
            existingRows.forEach(row => {
                if (!doc.getElementById(row.id)) {
                    row.remove();
                }
            });
            
            convertTableDateTimes();
            if (typeof applyFilters === 'function') applyFilters();
        } catch(e) {
            console.error("Soft refresh failed", e);
            window.location.reload(); // fallback
        }
        
        lastKnownUpdateTime = null; // reset to fetch new timestamp next time
        scheduleNextCheck();
    }

    function scheduleNextCheck() {
        if (pollingTimeoutId) clearTimeout(pollingTimeoutId);
        pollingTimeoutId = setTimeout(checkForUpdates, POLLING_INTERVAL);
    }

    // Replaced specific setInterval with the global smooth refresh
    if (document.getElementById('updates-table') || document.querySelector('table')) {
        setInterval(refreshTableSoft, 5000);
    }

    if (document.querySelector('[data-sortable]') && !document.getElementById('updates-table')) {
       setTimeout(checkForUpdates, 5000);
    }
});