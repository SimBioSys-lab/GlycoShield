#!/usr/bin/env python3
"""
Create preview versions for existing large PDB files in Azure
"""

import os
import sys
import argparse
import tempfile
from azure.storage.blob import BlobServiceClient, PublicAccess, ContentSettings
from dotenv import load_dotenv

load_dotenv()

AZURE_CONNECTION_STRING = os.getenv("AZURE_CONNECTION_STRING")
CONTAINER_NAME = "glacier"
PDB_PREVIEW_SIZE_MB = 50

def get_blob_service_client():
    if not AZURE_CONNECTION_STRING:
        raise ValueError("AZURE_CONNECTION_STRING not found in environment variables")
    return BlobServiceClient.from_connection_string(AZURE_CONNECTION_STRING)

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
        print(f"Error extracting frame: {e}", file=sys.stderr)
        return False

def create_previews_for_user(user_id):
    """Create preview versions for all large PDB files of a user"""
    try:
        blob_service_client = get_blob_service_client()
        container_client = blob_service_client.get_container_client(CONTAINER_NAME)
        
        # List all blobs for user
        blobs = list(container_client.list_blobs(name_starts_with=f"{user_id}/"))
        
        # Find large PDB files
        large_pdbs = []
        existing_previews = set()
        
        for blob in blobs:
            if blob.name.endswith('_preview.pdb'):
                original_name = blob.name.replace('_preview.pdb', '.pdb')
                existing_previews.add(original_name)
            elif blob.name.endswith('.pdb') and not blob.name.endswith('_preview.pdb'):
                size_mb = blob.size / (1024 * 1024)
                if size_mb > PDB_PREVIEW_SIZE_MB:
                    large_pdbs.append((blob.name, size_mb))
        
        if not large_pdbs:
            print("✓ No large PDB files found (>50 MB)", file=sys.stderr)
            return 0
        
        print(f"Found {len(large_pdbs)} large PDB files", file=sys.stderr)
        print("", file=sys.stderr)
        
        created_count = 0
        
        for blob_name, size_mb in large_pdbs:
            if blob_name in existing_previews:
                print(f"  ⏭️  {os.path.basename(blob_name)} - Preview already exists", file=sys.stderr)
                continue
            
            print(f"  📄 Creating preview for {os.path.basename(blob_name)} ({size_mb:.2f} MB)...", file=sys.stderr, end='')
            
            try:
                # Download original file to temp
                blob_client = container_client.get_blob_client(blob_name)
                
                with tempfile.NamedTemporaryFile(mode='wb', suffix='.pdb', delete=False) as tmp_original:
                    download_stream = blob_client.download_blob()
                    download_stream.readinto(tmp_original)
                    tmp_original_path = tmp_original.name
                
                # Extract first frame
                with tempfile.NamedTemporaryFile(mode='w', suffix='_preview.pdb', delete=False) as tmp_preview:
                    tmp_preview_path = tmp_preview.name
                
                if extract_first_pdb_frame(tmp_original_path, tmp_preview_path):
                    # Upload preview
                    preview_blob_name = blob_name.replace('.pdb', '_preview.pdb')
                    preview_blob_client = container_client.get_blob_client(preview_blob_name)
                    
                    with open(tmp_preview_path, 'rb') as preview_file:
                        preview_blob_client.upload_blob(
                            preview_file,
                            overwrite=True,
                            content_settings=ContentSettings(content_type='chemical/x-pdb'),
                            metadata={
                                "type": "preview",
                                "original_file": blob_name,
                                "created_at": "generated_from_existing"
                            }
                        )
                    
                    preview_size = os.path.getsize(tmp_preview_path) / (1024 * 1024)
                    print(f" ✓ ({size_mb:.2f} MB → {preview_size:.2f} MB)", file=sys.stderr)
                    created_count += 1
                else:
                    print(f" ✗ Failed", file=sys.stderr)
                
                # Cleanup temp files
                os.remove(tmp_original_path)
                os.remove(tmp_preview_path)
                
            except Exception as e:
                print(f" ✗ Error: {str(e)}", file=sys.stderr)
        
        print("", file=sys.stderr)
        print(f"✓ Created {created_count} preview files", file=sys.stderr)
        
        return created_count
        
    except Exception as e:
        print(f"✗ Error: {str(e)}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Create preview versions for existing large PDB files')
    parser.add_argument('user_id', help='User ID to process')
    args = parser.parse_args()
    
    created = create_previews_for_user(args.user_id)
    
    if created > 0:
        print("", file=sys.stderr)
        print("📝 Regenerating index to include preview buttons...", file=sys.stderr)
        import subprocess
        result = subprocess.run([sys.executable, 'generate_azure_index.py', args.user_id],
                              capture_output=True, text=True)
        if result.returncode == 0:
            print("✓ Index updated", file=sys.stderr)
            print(result.stdout)
        else:
            print(f"⚠ Warning: {result.stderr}", file=sys.stderr)
    else:
        print("ℹ️  No previews created, index not updated", file=sys.stderr)

if __name__ == '__main__':
    main()
