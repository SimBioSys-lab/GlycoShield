#!/usr/bin/env python3
"""
azure_glycoshield.py
Azure Blob Storage management for GlycoShield pipeline
"""

import os
import sys
import argparse
from datetime import datetime
from azure.storage.blob import BlobServiceClient, PublicAccess, ContentSettings
from dotenv import load_dotenv

load_dotenv()

AZURE_CONNECTION_STRING = os.getenv("AZURE_CONNECTION_STRING")
CONTAINER_NAME = "glacier"
PDB_PREVIEW_SIZE_MB = 50  # Create preview for PDB files larger than 50 MB

def get_blob_service_client():
    """Initialize and return Azure Blob Service Client"""
    if not AZURE_CONNECTION_STRING:
        raise ValueError("AZURE_CONNECTION_STRING not found in environment variables")
    return BlobServiceClient.from_connection_string(AZURE_CONNECTION_STRING)

def ensure_public_container():
    """Ensure container has public blob access"""
    try:
        blob_service_client = get_blob_service_client()
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        
        try:
            container_client.create_container(public_access=PublicAccess.Blob)
            print(f"✓ Container '{CONTAINER_NAME}' created with public access", file=sys.stderr)
        except Exception:
            try:
                container_client.set_container_access_policy(
                    signed_identifiers={},
                    public_access=PublicAccess.Blob
                )
                print(f"✓ Container '{CONTAINER_NAME}' access policy set to public", file=sys.stderr)
            except:
                pass
        
        props = container_client.get_container_properties()
        if props.public_access == PublicAccess.Blob or str(props.public_access) == 'blob':
            print(f"✓ Verified: Container is publicly accessible", file=sys.stderr)
        
        return container_client
    except Exception as e:
        print(f"✗ Error ensuring public container: {str(e)}", file=sys.stderr)
        raise

def create_uploading_index_html(user_id, folder_name):
    """Create an index.html that shows uploading status for a specific folder"""
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GLACIER Results - {user_id}</title>
    <meta http-equiv="refresh" content="10">
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }}
        .container {{
            max-width: 800px;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 60px 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }}
        h1 {{ color: #667eea; font-size: 2.5em; margin-bottom: 20px; }}
        .status {{ font-size: 1.3em; color: #666; margin-bottom: 30px; }}
        .spinner {{
            width: 60px; height: 60px; margin: 30px auto;
            border: 6px solid #f3f3f3; border-top: 6px solid #667eea;
            border-radius: 50%; animation: spin 1s linear infinite;
        }}
        @keyframes spin {{ 0% {{ transform: rotate(0deg); }} 100% {{ transform: rotate(360deg); }} }}
        .upload-info {{
            background: #e8f4fd; padding: 20px; border-radius: 10px;
            margin-top: 30px; text-align: left;
        }}
        .upload-info h3 {{ color: #667eea; margin-bottom: 15px; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🧬 GLACIER Pipeline</h1>
        <div class="status">Uploading results for {folder_name}...</div>
        <div class="spinner"></div>
        <div class="upload-info">
            <h3>📤 Current Upload:</h3>
            <p>Folder: <strong>{folder_name}</strong></p>
            <p>Status: Uploading files to Azure...</p>
            <p style="margin-top: 15px; color: #888; font-size: 0.9em;">
                ⏱️ This page will refresh in 10 seconds
            </p>
        </div>
    </div>
</body>
</html>
"""
    return html

def create_initial_index_html(user_id):
    """Create an initial index.html that shows processing status"""
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GLACIER Results - {user_id}</title>
    <meta http-equiv="refresh" content="60">
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }}
        .container {{
            max-width: 800px;
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 60px 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }}
        h1 {{ color: #667eea; font-size: 2.5em; margin-bottom: 20px; }}
        .status {{ font-size: 1.3em; color: #666; margin-bottom: 30px; }}
        .spinner {{
            width: 60px; height: 60px; margin: 30px auto;
            border: 6px solid #f3f3f3; border-top: 6px solid #667eea;
            border-radius: 50%; animation: spin 1s linear infinite;
        }}
        @keyframes spin {{ 0% {{ transform: rotate(0deg); }} 100% {{ transform: rotate(360deg); }} }}
        .info {{
            background: #e8f4fd; padding: 20px; border-radius: 10px;
            margin-top: 30px; text-align: left;
        }}
        .info h3 {{ color: #667eea; margin-bottom: 15px; }}
        .info ul {{ list-style-position: inside; color: #555; line-height: 1.8; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🧬 GLACIER Pipeline</h1>
        <div class="status">Your analysis is being processed...</div>
        <div class="spinner"></div>
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-top: 20px; font-family: monospace;">
            Job ID: <strong>{user_id}</strong>
        </div>
        <div class="info">
            <h3>📊 Pipeline Stages:</h3>
            <ul>
                <li>Stage 1: AllosMod Ensemble Generation (2-8 hours)</li>
                <li>Stage 2: PDB Processing & Alignment (1-2 hours)</li>
                <li>Stage 3: GEF Surface Analysis (30-45 hours)</li>
                <li>Stage 4: Results Upload & Finalization</li>
            </ul>
        </div>
        <div style="margin-top: 30px; color: #888; font-size: 0.9em;">
            ⏱️ This page will automatically refresh every 60 seconds<br>
            Files will appear here when processing is complete
        </div>
    </div>
</body>
</html>
"""
    return html

def extract_first_pdb_frame(input_path, output_path):
    """Extract first frame from multi-frame PDB file"""
    try:
        with open(input_path, 'r', encoding='utf-8', errors='ignore') as f_in, \
             open(output_path, 'w', encoding='utf-8') as f_out:
            for line in f_in:
                f_out.write(line)
                if line.strip().startswith("ENDMDL") or line.strip() == "END":
                    break
        return True
    except Exception as e:
        print(f"Warning: Could not extract preview from {input_path}: {e}", file=sys.stderr)
        return False

def create_folder_link(user_id):
    """Create folder with initial processing index"""
    try:
        blob_service_client = get_blob_service_client()
        container_client = ensure_public_container()
        account_name = blob_service_client.account_name
        
        folder_path = f"{user_id}/"
        
        # Create placeholder
        placeholder_blob = f"{folder_path}.placeholder"
        blob_client = container_client.get_blob_client(placeholder_blob)
        blob_client.upload_blob(
            b"",
            overwrite=True,
            metadata={"created_at": datetime.utcnow().isoformat(), "user_id": user_id}
        )
        
        # Create initial processing index
        initial_html = create_initial_index_html(user_id)
        index_blob_path = f"{folder_path}index.html"
        index_blob_client = container_client.get_blob_client(index_blob_path)
        index_blob_client.upload_blob(
            initial_html.encode('utf-8'),
            overwrite=True,
            content_settings=ContentSettings(content_type='text/html')
        )
        
        base_url = f"https://{account_name}.blob.core.windows.net/{CONTAINER_NAME}"
        index_url = f"{base_url}/{index_blob_path}"
        
        print(f"✓ Folder created: {folder_path}", file=sys.stderr)
        print(f"✓ Initial index page created", file=sys.stderr)
        print(f"✓ Public URL generated", file=sys.stderr)
        
        return folder_path, index_url
    except Exception as e:
        print(f"✗ Error creating folder: {str(e)}", file=sys.stderr)
        sys.exit(1)

def upload_directory(user_id, local_directory, auto_generate_index=True):
    """Upload directory and optionally regenerate index"""
    try:
        blob_service_client = get_blob_service_client()
        container_client = ensure_public_container()
        account_name = blob_service_client.account_name
        
        if not os.path.isdir(local_directory):
            raise ValueError(f"Directory not found: {local_directory}")
        
        # Get folder name being uploaded
        folder_name = os.path.basename(local_directory.rstrip('/'))
        
        # Update index to show uploading status
        if auto_generate_index:
            print(f"📝 Updating index to show upload progress...", file=sys.stderr)
            uploading_html = create_uploading_index_html(user_id, folder_name)
            index_blob = container_client.get_blob_client(f"{user_id}/index.html")
            index_blob.upload_blob(
                uploading_html.encode('utf-8'),
                overwrite=True,
                content_settings=ContentSettings(content_type='text/html')
            )
        
        uploaded_count = 0
        failed_count = 0
        large_pdbs = []
        
        print(f"📤 Uploading files from: {local_directory}", file=sys.stderr)
        print(f"📦 Destination: {CONTAINER_NAME}/{user_id}/", file=sys.stderr)
        print("", file=sys.stderr)
        
        for root, dirs, files in os.walk(local_directory):
            for filename in files:
                local_path = os.path.join(root, filename)
                
                if filename.startswith('.') or filename.endswith(('.swp', '.tmp')):
                    continue
                
                relative_path = os.path.relpath(local_path, local_directory)
                blob_path = f"{user_id}/{relative_path}".replace('\\', '/')
                
                try:
                    file_size = os.path.getsize(local_path)
                    size_mb = file_size / (1024 * 1024)
                    
                    print(f"  ⏳ Uploading: {relative_path} ({size_mb:.2f} MB)...", file=sys.stderr, end='')
                    
                    # Determine content type
                    content_settings = None
                    if filename.endswith('.pdb'):
                        content_settings = ContentSettings(content_type='chemical/x-pdb')
                        # Track large PDB files for preview generation
                        if size_mb > PDB_PREVIEW_SIZE_MB:
                            large_pdbs.append((local_path, blob_path, size_mb))
                    elif filename.endswith('.csv'):
                        content_settings = ContentSettings(content_type='text/csv')
                    elif filename.endswith('.dat'):
                        content_settings = ContentSettings(content_type='text/plain')
                    elif filename.endswith(('.png', '.jpg', '.jpeg')):
                        content_settings = ContentSettings(content_type=f'image/{filename.split(".")[-1]}')
                    elif filename.endswith('.json'):
                        content_settings = ContentSettings(content_type='application/json')
                    elif filename.endswith('.html'):
                        content_settings = ContentSettings(content_type='text/html')
                    
                    blob_client = container_client.get_blob_client(blob_path)
                    
                    with open(local_path, 'rb') as data:
                        blob_client.upload_blob(
                            data,
                            overwrite=True,
                            content_settings=content_settings,
                            metadata={
                                "user_id": user_id,
                                "uploaded_at": datetime.utcnow().isoformat(),
                                "original_path": relative_path,
                                "file_size_mb": str(size_mb)
                            }
                        )
                    
                    print(f" ✓", file=sys.stderr)
                    uploaded_count += 1
                except Exception as e:
                    print(f" ✗ Failed: {str(e)}", file=sys.stderr)
                    failed_count += 1
        
        # Generate preview versions for large PDB files
        if large_pdbs:
            print("", file=sys.stderr)
            print(f"📄 Creating previews for {len(large_pdbs)} large PDB files...", file=sys.stderr)
            for local_path, blob_path, size_mb in large_pdbs:
                try:
                    preview_path = f"/tmp/{os.path.basename(blob_path)}.preview"
                    if extract_first_pdb_frame(local_path, preview_path):
                        preview_blob_path = blob_path.replace('.pdb', '_preview.pdb')
                        preview_blob_client = container_client.get_blob_client(preview_blob_path)
                        
                        with open(preview_path, 'rb') as data:
                            preview_blob_client.upload_blob(
                                data,
                                overwrite=True,
                                content_settings=ContentSettings(content_type='chemical/x-pdb'),
                                metadata={
                                    "user_id": user_id,
                                    "type": "preview",
                                    "original_file": blob_path
                                }
                            )
                        
                        os.remove(preview_path)
                        print(f"  ✓ Preview created for {os.path.basename(blob_path)} ({size_mb:.2f} MB → preview)", file=sys.stderr)
                except Exception as e:
                    print(f"  ⚠ Could not create preview for {os.path.basename(blob_path)}: {e}", file=sys.stderr)
        
        print("", file=sys.stderr)
        print(f"✓ Upload complete: {uploaded_count} files uploaded", file=sys.stderr)
        if failed_count > 0:
            print(f"⚠ {failed_count} files failed to upload", file=sys.stderr)
        
        # Auto-generate final index if requested
        if auto_generate_index:
            print("", file=sys.stderr)
            print("📝 Generating final index with all files...", file=sys.stderr)
            from subprocess import run, PIPE
            result = run([sys.executable, 'generate_azure_index.py', user_id], 
                        capture_output=True, text=True)
            if result.returncode == 0:
                print("✓ Index updated successfully", file=sys.stderr)
            else:
                print(f"⚠ Warning: Index generation failed", file=sys.stderr)
                print(result.stderr, file=sys.stderr)
        
        base_url = f"https://{account_name}.blob.core.windows.net/{CONTAINER_NAME}"
        index_url = f"{base_url}/{user_id}/index.html"
        print(f"📂 Results page: {index_url}", file=sys.stderr)
        
        return uploaded_count
    except Exception as e:
        print(f"✗ Error uploading directory: {str(e)}", file=sys.stderr)
        sys.exit(1)

def generate_folder_url(user_id):
    """Generate the index.html URL for a folder"""
    try:
        blob_service_client = get_blob_service_client()
        account_name = blob_service_client.account_name
        return f"https://{account_name}.blob.core.windows.net/{CONTAINER_NAME}/{user_id}/index.html"
    except Exception as e:
        print(f"✗ Error generating URL: {str(e)}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Azure Blob Storage management for GlycoShield/GLACIER pipeline')
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    create_parser = subparsers.add_parser('create-folder', help='Create folder and return index.html URL')
    create_parser.add_argument('user_id', help='User ID for folder name')
    
    upload_parser = subparsers.add_parser('upload-files', help='Upload files and auto-generate index')
    upload_parser.add_argument('user_id', help='User ID (folder name in Azure)')
    upload_parser.add_argument('directory', help='Local directory to upload')
    upload_parser.add_argument('--no-index', action='store_true', help='Skip automatic index generation')
    
    url_parser = subparsers.add_parser('generate-url', help='Generate index.html URL')
    url_parser.add_argument('user_id', help='User ID (folder name)')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    if args.command == 'create-folder':
        folder_path, index_url = create_folder_link(args.user_id)
        print(index_url)
    elif args.command == 'upload-files':
        uploaded_count = upload_directory(args.user_id, args.directory, auto_generate_index=not args.no_index)
        index_url = generate_folder_url(args.user_id)
        print(index_url)
    elif args.command == 'generate-url':
        url = generate_folder_url(args.user_id)
        print(url)

if __name__ == '__main__':
    main()
