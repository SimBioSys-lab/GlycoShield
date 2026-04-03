#!/usr/bin/env python3
"""
generate_azure_index.py
Generate professional HTML index for GLACIER results with organized folder structure
Supports both old structure (files at root) and new structure (organized subfolders)
"""

import os
import sys
import argparse
import re
from datetime import datetime
from collections import defaultdict
from azure.storage.blob import BlobServiceClient, PublicAccess, ContentSettings
from dotenv import load_dotenv

load_dotenv()

AZURE_CONNECTION_STRING = os.getenv("AZURE_CONNECTION_STRING")
CONTAINER_NAME = "glacier"
PDB_PREVIEW_SIZE_MB = 50

# Define folder display info - supports both old and new folder names
FOLDER_INFO = {
    # New structure
    'ensemble': {
        'icon': '🔬',
        'title': 'Ensemble Modelling',
        'description': 'PDB processing and structural alignment outputs',
        'order': 2
    },
    'gef': {
        'icon': '📊',
        'title': 'GEF Surface Analysis',
        'description': 'Geometric Exposure Factor calculations',
        'order': 3
    },
    'burgly': {
        'icon': '📈',
        'title': 'Burgly Depth Analysis',
        'description': 'Glycan surface depth and burial patterns',
        'order': 4
    },
    'interglycan_interactions': {
        'icon': '🔗',
        'title': 'Interglycan Interactions',
        'description': 'Glycan adjacency matrix analysis',
        'order': 5
    },
    # Old structure folder names (map to same display)
    'burgly_analysis': {
        'icon': '📈',
        'title': 'Burgly Depth Analysis',
        'description': 'Glycan surface depth and burial patterns',
        'order': 4
    },
    'madison_analysis': {
        'icon': '🔗',
        'title': 'Interglycan Interactions',
        'description': 'Glycan adjacency matrix analysis',
        'order': 5
    },
    # Special folders
    'inputs': {
        'icon': '📥',
        'title': 'Input Files',
        'description': 'Original input files for the analysis',
        'order': 1
    },
    'allosmod': {
        'icon': '⚙️',
        'title': 'AllosMod Ensemble',
        'description': 'AllosMod ensemble generation outputs',
        'order': 1.5
    },
    'logs': {
        'icon': '📋',
        'title': 'Pipeline Logs',
        'description': 'Execution logs and diagnostic information',
        'order': 10
    }
}

# File patterns to auto-categorize root-level files
FILE_CATEGORIES = {
    'ensemble': [
        r'^output\.pdb$',
        r'^output_aligned\.pdb$',
        r'^output_aligned_multimodel\.pdb$',
        r'^alignment\.log$',
    ],
    'gef': [
        r'^GEF_CHA.*\.dat$',
        r'^processed_GEF_output\.csv$',
        r'^gef_data_range.*\.png$',
    ],
}

def get_blob_service_client():
    if not AZURE_CONNECTION_STRING:
        raise ValueError("AZURE_CONNECTION_STRING not found")
    return BlobServiceClient.from_connection_string(AZURE_CONNECTION_STRING)

def ensure_public_container():
    client = get_blob_service_client()
    cont = client.get_container_client(CONTAINER_NAME)
    try:
        cont.set_container_access_policy(signed_identifiers={}, public_access=PublicAccess.Blob)
    except:
        pass
    return cont

def format_size(b):
    for u in ['B', 'KB', 'MB', 'GB']:
        if b < 1024:
            return f"{b:.2f} {u}"
        b /= 1024
    return f"{b:.2f} TB"

def get_file_icon(filename):
    """Get appropriate icon for file type"""
    if filename.endswith('.pdb'):
        return '🧬'
    elif filename.endswith('.csv'):
        return '📊'
    elif filename.endswith('.dat'):
        return '📈'
    elif filename.endswith(('.png', '.jpg', '.jpeg', '.gif')):
        return '🖼️'
    elif filename.endswith(('.py', '.sh')):
        return '💻'
    elif filename.endswith('.log'):
        return '📋'
    elif filename.endswith('.out') or filename.endswith('.err'):
        return '📝'
    elif filename.endswith('.ali'):
        return '🧬'
    else:
        return '📄'

def categorize_file(filename):
    """Categorize a root-level file into a virtual subfolder based on patterns"""
    for category, patterns in FILE_CATEGORIES.items():
        for pattern in patterns:
            if re.match(pattern, filename):
                return category
    return None

def get_folder_order(folder_name):
    """Get sort order for a folder"""
    info = FOLDER_INFO.get(folder_name, {})
    return info.get('order', 100)

def generate_html_index(uid):
    try:
        client = get_blob_service_client()
        cont = ensure_public_container()
        base = f"https://{client.account_name}.blob.core.windows.net/{CONTAINER_NAME}"
        
        # List all blobs for this user
        blobs = list(cont.list_blobs(name_starts_with=f"{uid}/"))
        
        # Organize blobs, track previews
        all_blobs = {}
        preview_map = {}
        
        for b in blobs:
            if b.name.endswith('.placeholder') or b.name == f'{uid}/index.html':
                continue
            all_blobs[b.name] = b
            if '_preview.pdb' in b.name:
                preview_map[b.name.replace('_preview.pdb', '.pdb')] = b.name
                print(f"  Found preview: {os.path.basename(b.name)}", file=sys.stderr)
        
        # Organize files by model and subfolder
        # Structure: {model_name: {subfolder: [files]}}
        models = defaultdict(lambda: defaultdict(list))
        root_files = []
        
        for bn, b in all_blobs.items():
            if '_preview.pdb' in bn:
                continue
            
            # Parse path: user_id/model_name/subfolder/file or user_id/model_name/file
            parts = bn.split('/')
            
            file_info = {
                'name': parts[-1],
                'full_path': bn,
                'size': b.size,
                'size_mb': b.size / (1024 * 1024),
                'modified': b.last_modified,
                'url': f"{base}/{bn}",
                'has_preview': bn in preview_map,
                'preview_url': f"{base}/{preview_map[bn]}" if bn in preview_map else None,
                'is_large_pdb': bn.endswith('.pdb') and b.size / (1024 * 1024) > PDB_PREVIEW_SIZE_MB
            }
            
            if len(parts) == 2:
                # Root level file (user_id/file)
                root_files.append(file_info)
            elif len(parts) == 3:
                # Model level file (user_id/model/file)
                model_name = parts[1]
                filename = parts[2]
                
                # Try to auto-categorize into virtual subfolder
                category = categorize_file(filename)
                if category:
                    models[model_name][category].append(file_info)
                else:
                    models[model_name]['other'].append(file_info)
            elif len(parts) >= 4:
                # Subfolder file (user_id/model/subfolder/file or deeper)
                model_name = parts[1]
                subfolder = parts[2]
                file_info['name'] = '/'.join(parts[3:])  # Handle nested paths
                models[model_name][subfolder].append(file_info)
        
        # Count totals
        total_files = sum(len(files) for model in models.values() for files in model.values()) + len(root_files)
        total_size = sum(f['size'] for model in models.values() for files in model.values() for f in files)
        total_size += sum(f['size'] for f in root_files)
        
        print(f"Organized {len(models)} models, {total_files} files, {len(preview_map)} previews", file=sys.stderr)
        
        # Generate HTML
        html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GLACIER Results - {uid}</title>
    <script src="https://cdn.jsdelivr.net/npm/ngl@2.0.0-dev.37/dist/ngl.js"></script>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f0f4f8; color: #2d3748; }}
        .container {{ max-width: 1400px; margin: 0 auto; padding: 20px; }}
        
        header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            padding: 50px 40px;
            border-radius: 16px;
            margin-bottom: 30px;
            box-shadow: 0 10px 40px rgba(102, 126, 234, 0.3);
        }}
        h1 {{ font-size: 2.2em; font-weight: 700; margin-bottom: 10px; display: flex; align-items: center; gap: 15px; }}
        .subtitle {{ font-size: 1em; opacity: 0.9; margin-bottom: 15px; }}
        .job-id {{ display: inline-block; background: rgba(255,255,255,0.2); padding: 8px 16px; border-radius: 8px; font-family: monospace; font-size: 0.9em; }}
        
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .stat-card {{
            background: #fff;
            padding: 24px;
            border-radius: 12px;
            text-align: center;
            box-shadow: 0 2px 10px rgba(0,0,0,0.08);
        }}
        .stat-value {{ font-size: 2em; font-weight: 700; color: #667eea; margin-bottom: 5px; }}
        .stat-label {{ font-size: 0.85em; color: #718096; text-transform: uppercase; letter-spacing: 0.5px; }}
        
        .model-card {{
            background: #fff;
            border-radius: 16px;
            margin-bottom: 30px;
            box-shadow: 0 2px 15px rgba(0,0,0,0.08);
            overflow: hidden;
        }}
        .model-header {{
            background: linear-gradient(135deg, #4a5568 0%, #2d3748 100%);
            color: #fff;
            padding: 25px 30px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .model-header:hover {{ background: linear-gradient(135deg, #5a6678 0%, #3d4758 100%); }}
        .model-title {{ font-size: 1.4em; font-weight: 600; display: flex; align-items: center; gap: 12px; }}
        .model-toggle {{ font-size: 1.5em; transition: transform 0.3s; }}
        .model-toggle.collapsed {{ transform: rotate(-90deg); }}
        .model-content {{ padding: 0; }}
        .model-content.collapsed {{ display: none; }}
        
        .subfolder {{
            border-bottom: 1px solid #e2e8f0;
        }}
        .subfolder:last-child {{ border-bottom: none; }}
        .subfolder-header {{
            padding: 20px 30px;
            background: #f7fafc;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.2s;
        }}
        .subfolder-header:hover {{ background: #edf2f7; }}
        .subfolder-title {{
            font-size: 1.1em;
            font-weight: 600;
            color: #4a5568;
            display: flex;
            align-items: center;
            gap: 10px;
        }}
        .subfolder-desc {{ font-size: 0.85em; color: #718096; margin-left: 30px; }}
        .subfolder-meta {{ font-size: 0.85em; color: #a0aec0; }}
        .subfolder-toggle {{ color: #a0aec0; transition: transform 0.3s; }}
        .subfolder-toggle.collapsed {{ transform: rotate(-90deg); }}
        
        .file-list {{ list-style: none; padding: 0 30px 20px 30px; }}
        .file-list.collapsed {{ display: none; }}
        .file-item {{
            background: #fafbfc;
            margin-top: 10px;
            padding: 16px 20px;
            border-radius: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            border: 1px solid #e2e8f0;
            transition: all 0.2s;
        }}
        .file-item:hover {{ background: #fff; border-color: #cbd5e0; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }}
        .file-info {{ flex: 1; }}
        .file-name {{ font-weight: 500; color: #2d3748; margin-bottom: 4px; font-size: 0.95em; display: flex; align-items: center; gap: 8px; }}
        .file-meta {{ color: #718096; font-size: 0.8em; }}
        .file-actions {{ display: flex; gap: 8px; flex-wrap: wrap; }}
        
        .btn {{
            padding: 8px 14px;
            border-radius: 6px;
            font-weight: 500;
            transition: all 0.2s;
            border: none;
            cursor: pointer;
            font-size: 0.8em;
            text-decoration: none;
            display: inline-flex;
            align-items: center;
            gap: 5px;
        }}
        .btn-view {{ background: #10b981; color: #fff; }}
        .btn-view:hover {{ background: #059669; }}
        .btn-visualize {{ background: #f59e0b; color: #fff; }}
        .btn-visualize:hover {{ background: #d97706; }}
        .btn-download {{ background: #667eea; color: #fff; }}
        .btn-download:hover {{ background: #5a67d8; }}
        
        .modal {{ display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background-color: rgba(0,0,0,0.75); }}
        .modal-content {{ background: #fff; margin: 3% auto; width: 92%; max-width: 1200px; border-radius: 16px; box-shadow: 0 20px 60px rgba(0,0,0,0.3); max-height: 92vh; display: flex; flex-direction: column; }}
        .modal-header {{ padding: 20px 28px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: #fff; border-radius: 16px 16px 0 0; display: flex; justify-content: space-between; align-items: center; }}
        .modal-title {{ font-size: 1.1em; font-weight: 600; }}
        .close {{ color: #fff; font-size: 28px; font-weight: bold; cursor: pointer; background: none; border: none; opacity: 0.8; line-height: 1; }}
        .close:hover {{ opacity: 1; }}
        .modal-body {{ padding: 25px; overflow: auto; flex: 1; }}
        
        #textContent {{ background: #f7fafc; padding: 20px; border-radius: 8px; font-family: 'Courier New', monospace; font-size: 0.85em; white-space: pre-wrap; max-height: 70vh; overflow-y: auto; border: 1px solid #e2e8f0; }}
        #imageContent {{ text-align: center; max-height: 70vh; overflow: auto; }}
        #imageContent img {{ max-width: 100%; height: auto; border-radius: 8px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }}
        #tableContent {{ overflow: auto; max-height: 70vh; border-radius: 8px; border: 1px solid #e2e8f0; }}
        #tableContent table {{ width: 100%; border-collapse: collapse; font-size: 0.85em; }}
        #tableContent th {{ background: #667eea; color: #fff; padding: 12px 14px; text-align: left; position: sticky; top: 0; font-weight: 600; }}
        #tableContent td {{ padding: 10px 14px; border-bottom: 1px solid #e2e8f0; }}
        #tableContent tr:nth-child(even) {{ background: #f7fafc; }}
        #tableContent tr:hover {{ background: #edf2f7; }}
        #pdbContent {{ width: 100%; height: 550px; position: relative; border-radius: 8px; border: 1px solid #e2e8f0; }}
        
        .loading {{ text-align: center; padding: 40px; color: #667eea; }}
        .controls-hint {{ position: absolute; top: 12px; left: 12px; background: rgba(255,255,255,0.95); padding: 10px 14px; border-radius: 6px; font-size: 0.75em; box-shadow: 0 2px 8px rgba(0,0,0,0.15); }}
        
        footer {{ text-align: center; padding: 40px 20px; color: #718096; font-size: 0.9em; }}
        footer a {{ color: #667eea; text-decoration: none; }}
        footer a:hover {{ text-decoration: underline; }}
        
        .empty-state {{ padding: 40px; text-align: center; color: #a0aec0; }}
    </style>
</head>
<body>
<div class="container">
    <header>
        <h1><span style="font-size: 1.1em">🧬</span> GLACIER Results</h1>
        <p class="subtitle">Glycan Accessibility Computational Infrastructure for Ensemble Research</p>
        <div class="job-id">Job ID: {uid}</div>
    </header>
    
    <div class="stats">
        <div class="stat-card">
            <div class="stat-value">{len(models)}</div>
            <div class="stat-label">Models</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">{total_files}</div>
            <div class="stat-label">Total Files</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">{format_size(total_size)}</div>
            <div class="stat-label">Total Size</div>
        </div>
    </div>
"""
        
        # Generate content for each model
        for model_name in sorted(models.keys()):
            model_data = models[model_name]
            model_file_count = sum(len(files) for files in model_data.values())
            
            html += f"""
    <div class="model-card">
        <div class="model-header" onclick="toggleModel(this)">
            <div class="model-title">
                <span>📁</span> {model_name}
            </div>
            <div style="display: flex; align-items: center; gap: 20px;">
                <span style="font-size: 0.85em; opacity: 0.8;">{model_file_count} files</span>
                <span class="model-toggle">▼</span>
            </div>
        </div>
        <div class="model-content">
"""
            
            # Sort subfolders by their defined order
            sorted_subfolders = sorted(model_data.keys(), key=lambda x: get_folder_order(x))
            
            for subfolder in sorted_subfolders:
                files = model_data[subfolder]
                if not files:
                    continue
                
                # Get folder info
                folder_info = FOLDER_INFO.get(subfolder, {
                    'icon': '📂',
                    'title': subfolder.replace('_', ' ').title(),
                    'description': '',
                    'order': 100
                })
                
                # Handle 'other' specially (uncategorized files at model level)
                if subfolder == 'other':
                    folder_info = {
                        'icon': '📄',
                        'title': 'Other Files',
                        'description': 'Additional output files',
                        'order': 99
                    }
                
                html += f"""
            <div class="subfolder">
                <div class="subfolder-header" onclick="toggleSubfolder(this)">
                    <div>
                        <div class="subfolder-title">
                            <span>{folder_info['icon']}</span> {folder_info['title']}
                        </div>
                        <div class="subfolder-desc">{folder_info['description']}</div>
                    </div>
                    <div style="display: flex; align-items: center; gap: 15px;">
                        <span class="subfolder-meta">{len(files)} files</span>
                        <span class="subfolder-toggle">▼</span>
                    </div>
                </div>
                <ul class="file-list">
"""
                
                for f in sorted(files, key=lambda x: x['name']):
                    icon = get_file_icon(f['name'])
                    actions = []
                    
                    # View button for text files
                    if f['name'].endswith(('.dat', '.log', '.txt', '.py', '.sh', '.ali', '.sch', '.csv', '.out', '.err')):
                        actions.append(f"<button class='btn btn-view' onclick=\"viewText('{f['url']}', '{f['name']}')\">👁️ View</button>")
                    
                    # View button for images
                    elif f['name'].endswith(('.png', '.jpg', '.jpeg', '.gif')):
                        actions.append(f"<button class='btn btn-view' onclick=\"viewImage('{f['url']}', '{f['name']}')\">👁️ View</button>")
                    
                    # PDB handling
                    elif f['name'].endswith('.pdb'):
                        if f['is_large_pdb'] and f['has_preview']:
                            actions.append(f"<button class='btn btn-view' onclick=\"viewText('{f['preview_url']}', '{f['name']} (Preview)')\">👁️ Preview</button>")
                            actions.append(f"<button class='btn btn-visualize' onclick=\"visualizePDB('{f['preview_url']}', '{f['name']}', true)\">🧬 3D Preview</button>")
                        elif f['is_large_pdb']:
                            actions.append(f"<button class='btn btn-view' onclick=\"alert('File too large for browser preview ({f['size_mb']:.1f} MB)')\">👁️ View</button>")
                        else:
                            actions.append(f"<button class='btn btn-view' onclick=\"viewText('{f['url']}', '{f['name']}')\">👁️ View</button>")
                            actions.append(f"<button class='btn btn-visualize' onclick=\"visualizePDB('{f['url']}', '{f['name']}', false)\">🧬 3D View</button>")
                    
                    # Table view for CSV
                    if f['name'].endswith('.csv'):
                        actions.append(f"<button class='btn btn-visualize' onclick=\"visualizeCSV('{f['url']}', '{f['name']}')\">📊 Table</button>")
                    
                    # Download button for all
                    actions.append(f"<a href='{f['url']}' class='btn btn-download' download>⬇️ Download</a>")
                    
                    html += f"""
                    <li class="file-item">
                        <div class="file-info">
                            <div class="file-name"><span>{icon}</span> {f['name']}</div>
                            <div class="file-meta">{format_size(f['size'])} • {f['modified'].strftime('%Y-%m-%d %H:%M')} UTC</div>
                        </div>
                        <div class="file-actions">{' '.join(actions)}</div>
                    </li>
"""
                
                html += """
                </ul>
            </div>
"""
            
            html += """
        </div>
    </div>
"""
        
        # Add root files if any
        if root_files:
            html += f"""
    <div class="model-card">
        <div class="model-header" onclick="toggleModel(this)">
            <div class="model-title">
                <span>📋</span> Root Files
            </div>
            <div style="display: flex; align-items: center; gap: 20px;">
                <span style="font-size: 0.85em; opacity: 0.8;">{len(root_files)} files</span>
                <span class="model-toggle">▼</span>
            </div>
        </div>
        <div class="model-content">
            <ul class="file-list" style="padding-top: 20px;">
"""
            for f in sorted(root_files, key=lambda x: x['name']):
                icon = get_file_icon(f['name'])
                actions = [f"<a href='{f['url']}' class='btn btn-download' download>⬇️ Download</a>"]
                
                html += f"""
                <li class="file-item">
                    <div class="file-info">
                        <div class="file-name"><span>{icon}</span> {f['name']}</div>
                        <div class="file-meta">{format_size(f['size'])}</div>
                    </div>
                    <div class="file-actions">{' '.join(actions)}</div>
                </li>
"""
            html += """
            </ul>
        </div>
    </div>
"""
        
        # Footer and modals
        html += f"""
    <footer>
        <p><strong>GLACIER Pipeline</strong> • SimBioSys Lab • Northeastern University</p>
        <p style="margin-top: 8px; font-size: 0.85em;">Generated on {datetime.utcnow().strftime('%B %d, %Y at %H:%M')} UTC</p>
    </footer>
</div>

<div id="previewModal" class="modal">
    <div class="modal-content">
        <div class="modal-header">
            <span class="modal-title" id="modalTitle">Preview</span>
            <button class="close" onclick="closeModal()">&times;</button>
        </div>
        <div class="modal-body">
            <div id="textContent" style="display:none"></div>
            <div id="imageContent" style="display:none"></div>
            <div id="tableContent" style="display:none"></div>
            <div id="pdbContent" style="display:none"></div>
        </div>
    </div>
</div>

<script>
// Toggle functions
function toggleModel(header) {{
    const content = header.nextElementSibling;
    const toggle = header.querySelector('.model-toggle');
    content.classList.toggle('collapsed');
    toggle.classList.toggle('collapsed');
}}

function toggleSubfolder(header) {{
    const fileList = header.nextElementSibling;
    const toggle = header.querySelector('.subfolder-toggle');
    fileList.classList.toggle('collapsed');
    toggle.classList.toggle('collapsed');
}}

// Modal functions
const modal = document.getElementById('previewModal');
const modalTitle = document.getElementById('modalTitle');
const textContent = document.getElementById('textContent');
const imageContent = document.getElementById('imageContent');
const tableContent = document.getElementById('tableContent');
const pdbContent = document.getElementById('pdbContent');

function closeModal() {{
    modal.style.display = 'none';
    textContent.style.display = 'none';
    imageContent.style.display = 'none';
    tableContent.style.display = 'none';
    pdbContent.style.display = 'none';
    textContent.innerHTML = '';
    imageContent.innerHTML = '';
    tableContent.innerHTML = '';
    pdbContent.innerHTML = '';
}}

window.onclick = function(e) {{ if (e.target == modal) closeModal(); }};
document.addEventListener('keydown', function(e) {{ if (e.key === 'Escape') closeModal(); }});

async function viewText(url, filename) {{
    modalTitle.textContent = filename;
    textContent.style.display = 'block';
    textContent.innerHTML = '<div class="loading">Loading...</div>';
    modal.style.display = 'block';
    try {{
        const r = await fetch(url);
        const t = await r.text();
        textContent.textContent = t;
    }} catch (e) {{
        textContent.innerHTML = '<div style="color:#e53e3e;padding:20px">Error: ' + e.message + '</div>';
    }}
}}

function viewImage(url, filename) {{
    modalTitle.textContent = filename;
    imageContent.style.display = 'block';
    imageContent.innerHTML = '<img src="' + url + '" alt="' + filename + '">';
    modal.style.display = 'block';
}}

async function visualizeCSV(url, filename) {{
    modalTitle.textContent = filename + ' - Table View';
    tableContent.style.display = 'block';
    tableContent.innerHTML = '<div class="loading">Loading...</div>';
    modal.style.display = 'block';
    try {{
        const r = await fetch(url);
        const t = await r.text();
        const lines = t.trim().split('\\n');
        if (!lines.length) {{
            tableContent.innerHTML = '<p style="padding:20px">Empty file</p>';
            return;
        }}
        let html = '<table>';
        lines.forEach((line, i) => {{
            const cells = line.split(',').map(c => c.trim());
            const tag = i === 0 ? 'th' : 'td';
            html += '<tr>' + cells.map(cell => `<${{tag}}>${{cell}}</${{tag}}>`).join('') + '</tr>';
        }});
        html += '</table>';
        tableContent.innerHTML = html;
    }} catch (e) {{
        tableContent.innerHTML = '<div style="color:#e53e3e;padding:20px">Error: ' + e.message + '</div>';
    }}
}}

async function visualizePDB(url, filename, isPreview) {{
    const title = isPreview ? filename + ' - 3D Preview (First Frame)' : filename + ' - 3D Visualization';
    modalTitle.textContent = title;
    pdbContent.style.display = 'block';
    pdbContent.innerHTML = '<div class="loading">Loading 3D structure...</div>';
    modal.style.display = 'block';
    try {{
        pdbContent.innerHTML = '';
        const stage = new NGL.Stage(pdbContent, {{ backgroundColor: '#f7fafc' }});
        await stage.loadFile(url, {{ ext: 'pdb' }}).then(component => {{
            component.addRepresentation('cartoon', {{ color: 'chainindex' }});
            component.addRepresentation('ball+stick', {{ sele: 'hetero', color: 'element' }});
            component.autoView();
        }});
        const controls = document.createElement('div');
        controls.className = 'controls-hint';
        controls.innerHTML = '<strong>Controls:</strong> Drag to rotate • Scroll to zoom • Right-click to pan';
        pdbContent.appendChild(controls);
    }} catch (e) {{
        console.error('PDB error:', e);
        pdbContent.innerHTML = '<div style="color:#e53e3e;padding:20px;text-align:center">Error loading PDB: ' + e.message + '</div>';
    }}
}}
</script>
</body>
</html>
"""
        
        # Upload the index
        blob = cont.get_blob_client(f"{uid}/index.html")
        blob.upload_blob(html.encode('utf-8'), overwrite=True, content_settings=ContentSettings(content_type='text/html'))
        
        url = f"{base}/{uid}/index.html"
        print(f"✓ Index generated with organized folder structure", file=sys.stderr)
        print(url)
        return url
        
    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Generate professional HTML index for GLACIER results')
    parser.add_argument('user_id', help='User ID')
    args = parser.parse_args()
    generate_html_index(args.user_id)

if __name__ == '__main__':
    main()
