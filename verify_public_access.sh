#!/bin/bash
# Quick script to verify Azure container has public access

set -euo pipefail

cd /projects/SimBioSys/share/software/GlycoShield
source /shared/centos7/anaconda3/3.7/bin/activate /projects/SimBioSys/share/software/allosmod-env 2>/dev/null

python3 << 'EOFPYTHON'
from azure.storage.blob import BlobServiceClient, PublicAccess

with open('.env', 'r') as f:
    for line in f:
        if line.startswith('AZURE_CONNECTION_STRING='):
            connection_string = line.split('=', 1)[1].strip().strip('"')
            break

blob_service_client = BlobServiceClient.from_connection_string(connection_string)
container_client = blob_service_client.get_container_client("glacier")

print("=" * 50)
print("Azure Container Public Access Verification")
print("=" * 50)
print()

# Check current access
props = container_client.get_container_properties()
print(f"Container: glacier")
print(f"Public Access: {props.public_access}")
print()

if props.public_access == PublicAccess.Blob or str(props.public_access) == 'blob':
    print("✅ Status: PUBLIC - URLs will work in browsers")
else:
    print("❌ Status: NOT PUBLIC - Setting to public now...")
    container_client.set_container_access_policy(
        signed_identifiers={},
        public_access=PublicAccess.Blob
    )
    print("✓ Container set to public blob access")

print()
print("=" * 50)
EOFPYTHON
