import os
import re

APP_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\app"
TEMPLATES_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\templates"
STATIC_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\static"

# 1. Update web_routes.py
def fix_web_routes():
    path = os.path.join(APP_DIR, 'web_routes.py')
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Overview route
    target_overview = """        laptops_with_status.append({
            "db_data": laptop_instance, 
            "scan_status": status_info,
            "is_online": is_online,
            "scan_hours": hours_rounded,
            "simplified_result_message": simplified_result_message
        })"""
    replacement_overview = """        
        has_error = False
        has_threat = False
        msg_lower = (laptop_instance.last_scan_result_message or "").lower()
        if "fehler" in msg_lower:
            has_error = True
        if "fund!" in msg_lower or "siehe bericht" in msg_lower or "bedrohung" in msg_lower:
            has_threat = True
            
        laptops_with_status.append({
            "db_data": laptop_instance, 
            "scan_status": status_info,
            "is_online": is_online,
            "scan_hours": hours_rounded,
            "simplified_result_message": simplified_result_message,
            "has_error": has_error,
            "has_threat": has_threat
        })"""
    
    if '"has_error": has_error' not in content:
        content = content.replace(target_overview, replacement_overview)

    # Updates route
    target_updates = """                else:
                    status_text = f"Offline ({mins//1440}d)"
                    short_status_text = f"{mins//1440}d"
                
        laptops_with_status.append({
            "db_data": laptop,
            "is_online": is_online,
            "status_text": status_text,
            "short_status_text": short_status_text,
            "color_class": color_class
        })"""
    replacement_updates = """                else:
                    status_text = f"Offline ({mins//1440}d)"
                    short_status_text = f"{mins//1440}d"
                    
        hours_rounded = 999999
        has_error = False
        has_threat = False
        if laptop.last_scan_time:
            scan_aware = laptop.last_scan_time.replace(tzinfo=timezone.utc)
            scan_delta = now_utc - scan_aware
            hours_rounded = round(scan_delta.total_seconds() / 3600)
            
        msg_lower = (laptop.last_scan_result_message or "").lower()
        if "fehler" in msg_lower:
            has_error = True
        if "fund!" in msg_lower or "siehe bericht" in msg_lower or "bedrohung" in msg_lower:
            has_threat = True
            
        laptops_with_status.append({
            "db_data": laptop,
            "is_online": is_online,
            "status_text": status_text,
            "short_status_text": short_status_text,
            "color_class": color_class,
            "scan_hours": hours_rounded,
            "has_error": has_error,
            "has_threat": has_threat
        })"""
    
    if 'hours_rounded = 999999' not in content:
        content = content.replace(target_updates, replacement_updates)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

# 2. Update HTML
def fix_html():
    for filename in ['laptops_overview.html', 'client_updates.html']:
        path = os.path.join(TEMPLATES_DIR, filename)
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Add data attributes to TR
        if 'data-threat=' not in content:
            if filename == 'laptops_overview.html':
                content = content.replace('<tr id="laptop-row-{{ laptop.alias_name }}" data-scan-hours="{{ item.scan_hours }}">', 
                                          '<tr id="laptop-row-{{ laptop.alias_name }}" data-scan-hours="{{ item.scan_hours }}" data-threat="{{ item.has_threat|lower }}" data-error="{{ item.has_error|lower }}">')
            elif filename == 'client_updates.html':
                content = content.replace('<tr id="laptop-row-{{ laptop.alias_name }}" data-scan-hours="{{ item.scan_hours }}">', 
                                          '<tr id="laptop-row-{{ laptop.alias_name }}" data-scan-hours="{{ item.scan_hours }}" data-threat="{{ item.has_threat|lower }}" data-error="{{ item.has_error|lower }}">')
                # If the previous script didn't add data-scan-hours properly:
                content = content.replace('<tr id="laptop-row-{{ laptop.alias_name }}">', 
                                          '<tr id="laptop-row-{{ laptop.alias_name }}" data-scan-hours="{{ item.scan_hours }}" data-threat="{{ item.has_threat|lower }}" data-error="{{ item.has_error|lower }}">')

        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)

# 3. Update app.js
def fix_js():
    path = os.path.join(STATIC_DIR, 'app.js')
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Bedrohung logic
    if "const hasThreat = row.dataset.threat === 'true';" not in content:
        old_threat = "const hasThreat = text.includes('fund!') || text.includes('siehe bericht') || text.includes('bedrohung');"
        new_threat = "const hasThreat = row.dataset.threat === 'true';"
        content = content.replace(old_threat, new_threat)

    # Fehler logic
    if "const hasError = row.dataset.error === 'true';" not in content:
        old_error = "const hasError = text.includes('fehler');"
        new_error = "const hasError = row.dataset.error === 'true';"
        content = content.replace(old_error, new_error)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

fix_web_routes()
fix_html()
fix_js()
print("Filters fixed successfully.")
