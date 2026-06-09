import os
import re

TEMPLATES_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\templates"
STATIC_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\static"

LUCIDE_SCRIPT = '<script src="https://unpkg.com/lucide@latest"></script>\n</head>'

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add Lucide script
    if 'unpkg.com/lucide' not in content:
        content = content.replace('</head>', LUCIDE_SCRIPT)

    # Replace Nav items (only exact text nodes so we don't break tags)
    content = content.replace('>Übersicht</a>', '><i data-lucide="layout-dashboard"></i> Übersicht</a>')
    content = content.replace('>Updates</a>', '><i data-lucide="refresh-cw"></i> Updates</a>')
    
    # Menü Dropdown Emoji replacers
    content = content.replace('Menü ▼', '<i data-lucide="menu"></i> Menü')
    content = content.replace('📄 Tagesbericht öffnen', '<i data-lucide="file-text"></i> Tagesbericht öffnen')
    content = content.replace('🚪 Logout', '<i data-lucide="log-out"></i> Logout')
    content = content.replace('⚙️ Einstellungen', '<i data-lucide="settings"></i> Einstellungen')
    
    # Emojis in dropdown overview/updates
    content = content.replace('📊 Übersicht', '<i data-lucide="layout-dashboard"></i> Übersicht')
    content = content.replace('🔄 Updates', '<i data-lucide="refresh-cw"></i> Updates')

    # Filter buttons (if present)
    content = content.replace('>Online</button>', '><i data-lucide="wifi"></i> Online</button>')
    content = content.replace('>Bedrohung</button>', '><i data-lucide="shield-alert"></i> Bedrohung</button>')
    content = content.replace('>Fehler</button>', '><i data-lucide="alert-triangle"></i> Fehler</button>')
    content = content.replace('>Veraltet</button>', '><i data-lucide="clock"></i> Veraltet</button>')

    # Write back
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

for filename in ['laptops_overview.html', 'client_updates.html', 'daily_report.html']:
    replace_in_file(os.path.join(TEMPLATES_DIR, filename))

# For daily report specific icons
report_path = os.path.join(TEMPLATES_DIR, 'daily_report.html')
with open(report_path, 'r', encoding='utf-8') as f:
    rcontent = f.read()
rcontent = rcontent.replace('>◀</a>', '><i data-lucide="chevron-left" style="margin:0;"></i></a>')
rcontent = rcontent.replace('>▶</a>', '><i data-lucide="chevron-right" style="margin:0;"></i></a>')
with open(report_path, 'w', encoding='utf-8') as f:
    f.write(rcontent)

# Add createIcons to app.js
appjs_path = os.path.join(STATIC_DIR, 'app.js')
with open(appjs_path, 'r', encoding='utf-8') as f:
    appjs = f.read()

if 'lucide.createIcons()' not in appjs:
    appjs = appjs.replace('document.addEventListener(\'DOMContentLoaded\', () => {', 'document.addEventListener(\'DOMContentLoaded\', () => {\n    if (typeof lucide !== \'undefined\') { lucide.createIcons(); }\n')
    with open(appjs_path, 'w', encoding='utf-8') as f:
        f.write(appjs)

print("Icons added successfully.")
