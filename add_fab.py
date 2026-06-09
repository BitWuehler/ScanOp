import os

TEMPLATES_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\templates"
STATIC_DIR = r"c:\Dateien\Programmentwicklung\ScanOp\ScanOp\static"

CSS_INJECTION = """
/* FAB and Mobile Action Slider */
.mobile-action-fab {
    display: none;
    position: fixed;
    bottom: 30px;
    right: 30px;
    width: 60px;
    height: 60px;
    border-radius: 50%;
    background: #0d6efd;
    color: white;
    border: none;
    box-shadow: 0 4px 15px rgba(13, 110, 253, 0.4);
    z-index: 1000;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: transform 0.2s, background 0.3s;
}
.mobile-action-fab:active {
    transform: scale(0.9);
}

@media (max-width: 1000px) {
    .mobile-action-fab {
        display: flex;
    }
    
    /* Hide top menu and bulk actions by default on mobile, toggle via body class */
    .header-left, .actions-bar {
        display: none !important;
    }
    body.show-mobile-actions .header-left,
    body.show-mobile-actions .actions-bar {
        display: flex !important;
    }

    /* Actions slider in rows */
    .actions-cell {
        position: absolute;
        right: 0;
        top: 0;
        height: 100%;
        background: rgba(20, 20, 40, 0.95);
        backdrop-filter: blur(5px);
        transform: translateX(100%);
        transition: transform 0.3s ease-in-out;
        display: flex;
        align-items: center;
        border-left: 1px solid rgba(255,255,255,0.1);
        padding: 0 15px;
        z-index: 10;
    }
    
    body.show-mobile-actions .actions-cell {
        transform: translateX(0);
    }
    
    tbody tr {
        position: relative;
        overflow: hidden; /* Prevent action cell overflow from showing */
    }
}
"""

def inject_css():
    with open(os.path.join(STATIC_DIR, 'style.css'), 'a', encoding='utf-8') as f:
        f.write(CSS_INJECTION)

def inject_html(filename):
    filepath = os.path.join(TEMPLATES_DIR, filename)
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    fab_html = '<button id="mobile-action-fab" class="mobile-action-fab" title="Aktionen"><i data-lucide="zap" style="width: 24px; height: 24px; margin: 0;"></i></button>\n</body>'
    
    if 'mobile-action-fab' not in content:
        content = content.replace('</body>', fab_html)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)

def inject_js():
    appjs_path = os.path.join(STATIC_DIR, 'app.js')
    with open(appjs_path, 'a', encoding='utf-8') as f:
        js = """
// FAB Logic
document.addEventListener('DOMContentLoaded', () => {
    const fab = document.getElementById('mobile-action-fab');
    if (fab) {
        fab.addEventListener('click', () => {
            document.body.classList.toggle('show-mobile-actions');
            if(typeof lucide !== 'undefined') {
                const icon = fab.querySelector('i');
                if (document.body.classList.contains('show-mobile-actions')) {
                    icon.setAttribute('data-lucide', 'x');
                } else {
                    icon.setAttribute('data-lucide', 'zap');
                }
                lucide.createIcons();
            }
        });
    }
});
"""
        f.write(js)

inject_css()
inject_html('laptops_overview.html')
inject_html('client_updates.html')
inject_js()
print("FAB injected successfully.")
