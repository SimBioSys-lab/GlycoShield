#!/usr/bin/env python3
import os
import sys
from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv

# Load from .env file in the same directory
script_dir = os.path.dirname(os.path.abspath(__file__))
env_path = os.path.join(script_dir, '.env')
load_dotenv(env_path)

conn_str = os.getenv("AZURE_CONNECTION_STRING")
if not conn_str:
    print("ERROR: AZURE_CONNECTION_STRING not found")
    sys.exit(1)

client = BlobServiceClient.from_connection_string(conn_str)
cont = client.get_container_client("glacier")

uid = sys.argv[1] if len(sys.argv) > 1 else "1a249275-dd70-4c40-9003-3f5fb7fe0849"

# Step 1: Delete unwanted files from Azure
print("=== Deleting unwanted files from Azure ===")
blobs = list(cont.list_blobs(name_starts_with=f"{uid}/"))
for b in blobs:
    # Delete GEF_CHA*.dat files
    if 'GEF_CHA' in b.name and b.name.endswith('.dat'):
        print(f"  Deleting: {b.name}")
        cont.delete_blob(b.name)
    # Delete multimodel files
    elif 'multimodel' in b.name:
        print(f"  Deleting: {b.name}")
        cont.delete_blob(b.name)

# Step 2: Upload inputs folder
print("\n=== Uploading inputs folder ===")
inputs_base = f"{script_dir}/inputs/{uid}"
if os.path.isdir(inputs_base):
    for root, dirs, files in os.walk(inputs_base):
        for filename in files:
            if filename.startswith('.'):
                continue
            local_path = os.path.join(root, filename)
            relative_path = os.path.relpath(local_path, inputs_base)
            blob_path = f"{uid}/inputs/{relative_path}".replace('\\', '/')
            
            try:
                with open(local_path, 'rb') as data:
                    blob_client = cont.get_blob_client(blob_path)
                    blob_client.upload_blob(data, overwrite=True)
                print(f"  Uploaded: inputs/{relative_path}")
            except Exception as e:
                print(f"  Error: {e}")

# Step 3: Upload logs folder
print("\n=== Uploading logs folder ===")
logs_base = f"{script_dir}/logs/{uid}"
if os.path.isdir(logs_base):
    for root, dirs, files in os.walk(logs_base):
        for filename in files:
            if filename.startswith('.'):
                continue
            local_path = os.path.join(root, filename)
            relative_path = os.path.relpath(local_path, logs_base)
            blob_path = f"{uid}/logs/{relative_path}".replace('\\', '/')
            
            try:
                with open(local_path, 'rb') as data:
                    blob_client = cont.get_blob_client(blob_path)
                    blob_client.upload_blob(data, overwrite=True)
                print(f"  Uploaded: logs/{relative_path}")
            except Exception as e:
                print(f"  Error: {e}")

print("\nDone!")
