import os
import re

TEMPLATES_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\templates"
STATIC_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\static"
APP_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\app"

# 1. Update web_routes.py
def fix_web_routes():
    path = os.path.join(APP_DIR, 'web_routes.py')
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    target = """                  else:
                      status_text = f"Offline ({mins//1440}d)"
                      short_status_text = f"{mins//1440}d"
                  
          laptops_with_status.append({
              "db_data": laptop,
              "is_online": is_online,
              "status_text": status_text,
              "short_status_text": short_status_text,
              "color_class": color_class
          })"""
    
    replacement = """                  else:
                      status_text = f"Offline ({mins//1440}d)"
                      short_status_text = f"{mins//1440}d"
          
          hours_rounded = 999999
          if laptop.last_scan_time:
              scan_aware = laptop.last_scan_time.replace(tzinfo=timezone.utc)
              scan_delta = now_utc - scan_aware
              hours_rounded = round(scan_delta.total_seconds() / 3600)
                  
          laptops_with_status.append({
              "db_data": laptop,
              "is_online": is_online,
              "status_text": status_text,
              "short_status_text": short_status_text,
              "color_class": color_class,
              "scan_hours": hours_rounded
          })"""
    if 'scan_hours": hours_rounded' not in content:
        content = content.replace(target, replacement)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)

# 2. Update style.css
def update_css():
    path = os.path.join(STATIC_DIR, 'style.css')
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove old fab and action slider rules at the end of the file
    if '/* FAB and Mobile Action Slider */' in content:
        content = content[:content.find('/* FAB and Mobile Action Slider */')]

    new_css = """
/* Settings Off-Canvas */
.settings-dropdown {
    position: fixed !important;
    top: 0;
    right: -350px;
    width: 300px;
    height: 100vh;
    background: rgba(10, 10, 20, 0.98);
    backdrop-filter: blur(10px);
    border-left: 1px solid var(--glass-border);
    z-index: 2000;
    padding: 20px;
    padding-top: 50px;
    transition: right 0.3s ease;
    overflow-y: auto;
    display: block !important;
}
.settings-dropdown.settings-open {
    right: 0;
}

/* Row Actions Handle (Mobile) */
.row-actions-handle {
    display: none;
    position: fixed;
    right: 0;
    top: 50%;
    transform: translateY(-50%);
    width: 30px;
    height: 60px;
    background: #0d6efd;
    color: white;
    border-radius: 8px 0 0 8px;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    z-index: 1001;
    box-shadow: -2px 0 10px rgba(0,0,0,0.5);
    transition: transform 0.3s ease-in-out;
}

/* Bulk Actions FAB (Mobile) */
.mobile-bulk-fab {
    display: none;
    position: fixed;
    bottom: 30px;
    right: 30px;
    width: 60px;
    height: 60px;
    border-radius: 50%;
    background: #6c757d;
    color: white;
    border: none;
    box-shadow: 0 4px 15px rgba(0,0,0,0.4);
    z-index: 1000;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: transform 0.2s;
}
.mobile-bulk-fab:active { transform: scale(0.9); }

@media (max-width: 1000px) {
    .row-actions-handle { display: flex; }
    .mobile-bulk-fab { display: flex; }
    
    /* Ensure rows don't overflow the absolute slider */
    tbody tr {
        position: relative;
        overflow: hidden;
    }
    
    /* Slider mechanics */
    .actions-cell {
        position: absolute;
        right: 0;
        top: 0;
        height: 100%;
        background: rgba(30, 30, 50, 0.95);
        backdrop-filter: blur(5px);
        transform: translateX(100%);
        transition: transform 0.3s ease-in-out;
        display: flex;
        align-items: center;
        border-left: 1px solid rgba(255,255,255,0.1);
        padding: 0 10px;
        z-index: 10;
        width: 150px;
        justify-content: center;
    }
    
    body.show-mobile-actions .actions-cell {
        transform: translateX(0);
    }
    body.show-mobile-actions .row-actions-handle {
        transform: translate(-170px, -50%);
    }

    /* Floating Bulk Actions Panel */
    .actions-bar {
        position: fixed;
        bottom: -150%;
        left: 0;
        width: 100%;
        background: rgba(20, 20, 40, 0.95);
        backdrop-filter: blur(10px);
        z-index: 1002;
        transition: bottom 0.3s ease;
        flex-direction: column !important;
        padding: 20px !important;
        border-top: 1px solid rgba(255,255,255,0.1);
        margin: 0 !important;
        box-sizing: border-box;
        display: flex !important;
        align-items: center;
    }
    body.show-bulk-actions .actions-bar {
        bottom: 0;
    }
}
"""
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content + new_css)

# 3. Update HTML files
def update_html():
    for filename in ['laptops_overview.html', 'client_updates.html']:
        path = os.path.join(TEMPLATES_DIR, filename)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Remove old FAB
        content = re.sub(r'<button id="mobile-action-fab".*?</button>\n', '', content, flags=re.DOTALL)
        
        # Add new FABs and close button
        if 'settings-close-btn' not in content:
            content = content.replace('<div id="settings-dropdown" class="settings-dropdown glass-container hidden" style="width: 300px;">',
                                      '<div id="settings-dropdown" class="settings-dropdown glass-container hidden">\n<button id="settings-close-btn" style="position:absolute; top: 15px; right: 15px; background: none; border: none; color: var(--text-muted); cursor: pointer;"><i data-lucide="x"></i></button>')
        
        # Add Veraltet filter in updates if missing
        if filename == 'client_updates.html' and 'data-filter="veraltet"' not in content:
            content = content.replace('data-filter="fehler"><i data-lucide="alert-triangle"></i> Fehler</button>',
                                      'data-filter="fehler"><i data-lucide="alert-triangle"></i> Fehler</button>\n<button class="filter-btn" data-state="0" data-filter="veraltet"><i data-lucide="clock"></i> Veraltet</button>')
            
            # Update td for online status
            content = content.replace('<td class="{{ item.color_class }}">', '<td class="{{ item.color_class }}" data-value="{{ item.is_online }}">')
            # Update tr for scan_hours
            content = content.replace('<tr id="laptop-row-{{ laptop.alias_name }}">', '<tr id="laptop-row-{{ laptop.alias_name }}" data-scan-hours="{{ item.scan_hours }}">')
            
        new_fabs = """<div id="row-actions-toggle" class="row-actions-handle" title="Zeilen-Aktionen"><i data-lucide="chevron-left"></i></div>
<button id="bulk-actions-fab" class="mobile-bulk-fab" title="Stapelverarbeitung & Filter"><i data-lucide="layers" style="width: 24px; height: 24px; margin: 0;"></i></button>
</body>"""
        if 'row-actions-toggle' not in content:
            content = content.replace('</body>', new_fabs)

        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)

# 4. Update JS
def update_js():
    path = os.path.join(STATIC_DIR, 'app.js')
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Remove old fab logic
    if '// FAB Logic' in content:
        content = content[:content.find('// FAB Logic')]

    new_js = """
// UX Overhaul Logic
document.addEventListener('DOMContentLoaded', () => {
    // 1. Settings Off-Canvas
    const settingsToggleBtn = document.getElementById('settings-toggle-btn');
    const settingsDropdown = document.getElementById('settings-dropdown');
    const settingsCloseBtn = document.getElementById('settings-close-btn');

    if (settingsToggleBtn && settingsDropdown) {
        // Remove old click listener by cloning (simplest way if it was inline or bound elsewhere)
        const newToggle = settingsToggleBtn.cloneNode(true);
        settingsToggleBtn.parentNode.replaceChild(newToggle, settingsToggleBtn);
        
        newToggle.addEventListener('click', (e) => {
            e.stopPropagation();
            settingsDropdown.classList.add('settings-open');
        });
    }
    
    if (settingsCloseBtn) {
        settingsCloseBtn.addEventListener('click', () => {
            settingsDropdown.classList.remove('settings-open');
        });
    }

    // 2. Row Actions Handle
    const rowActionsToggle = document.getElementById('row-actions-toggle');
    if (rowActionsToggle) {
        rowActionsToggle.addEventListener('click', () => {
            document.body.classList.toggle('show-mobile-actions');
            if(typeof lucide !== 'undefined') {
                const icon = rowActionsToggle.querySelector('i');
                if (document.body.classList.contains('show-mobile-actions')) {
                    icon.setAttribute('data-lucide', 'chevron-right');
                } else {
                    icon.setAttribute('data-lucide', 'chevron-left');
                }
                lucide.createIcons();
            }
        });
    }

    // 3. Bulk Actions FAB
    const bulkActionsFab = document.getElementById('bulk-actions-fab');
    if (bulkActionsFab) {
        bulkActionsFab.addEventListener('click', () => {
            document.body.classList.toggle('show-bulk-actions');
        });
    }
});
"""
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content + new_js)

fix_web_routes()
update_css()
update_html()
update_js()
print("UX Overhaul applied.")
