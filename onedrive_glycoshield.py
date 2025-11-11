"""
onedrive_glycoshield.py
End-to-end OneDrive operations using Microsoft Graph (App-only access).

Receives all parameters as named, optional command-line flags.

This script is designed for automation:
- All progress logs are printed to STDERR.
- The *only* output to STDOUT is a single JSON object with the results.

On Success, STDOUT will be:
{
  "status": "success",
  "base_folder": "GlycoShield",
  "sub_folder": "public",
  "sub_folder_id": "...",
  "files_uploaded": ["test_upload.txt"],
  "shared_with": ["simbiosyslab.neu@gmail.com"],
  "invite_link": "https://..."
}

On Failure, STDOUT will be:
{
  "status": "failure",
  "error": "File not found: non_existent_file.zip"
}
"""

import os
import json
import sys
import argparse
import requests
from dotenv import load_dotenv

load_dotenv()

# ======== CONFIGURE HERE ========
CLIENT_ID = os.getenv("CLIENT_ID")          # Azure Application (client) ID
CLIENT_SECRET = os.getenv("CLIENT_SECRET")  # Azure client secret
TENANT_ID = os.getenv("TENANT_ID")          # Azure Directory (tenant) ID

# --- Base folder is still set here ---
BASE_FOLDER_NAME = "GlycoShield"

# --- Default email list ---
DEFAULT_RECIPIENT_EMAILS = ['simbiosyslab.neu@gmail.com']
# =================================

TOKEN_URL = f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token"
GRAPH_BASE = "https://graph.microsoft.com/v1.0"

# Step 1: Obtain access token
def get_access_token():
    print("Fetching access token...", file=sys.stderr)
    data = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": "https://graph.microsoft.com/.default",
        "grant_type": "client_credentials"
    }
    resp = requests.post(TOKEN_URL, data=data)
    if not resp.ok:
        raise SystemExit(f"Token request failed: {resp.status_code}\n{resp.text}")
    token = resp.json()["access_token"]
    return token

# Step 2: Find or create a folder
def get_or_create_folder(headers, parent_id, folder_name):
    """
    Attempts to find a folder by name within a parent.
    If not found, creates it. Returns the folder's ID.
    'parent_id' can be 'root' for the drive's root.
    """
    print(f"Checking for folder '{folder_name}' in parent '{parent_id}'...", file=sys.stderr)
    
    find_url = f"{GRAPH_BASE}/sites/root/drive/items/{parent_id}/children"
    params = {"$filter": f"name eq '{folder_name}'"}
    
    r_find = requests.get(find_url, headers=headers, params=params)
    r_find.raise_for_status()
    
    items = r_find.json().get("value", [])
    
    for item in items:
        if item["name"].lower() == folder_name.lower() and "folder" in item:
            print(f"Folder '{folder_name}' found. ID: {item['id']}", file=sys.stderr)
            return item["id"]

    print(f"Folder '{folder_name}' not found. Creating...", file=sys.stderr)
    create_url = f"{GRAPH_BASE}/sites/root/drive/items/{parent_id}/children"
    payload = {
        "name": folder_name,
        "folder": {},
        "@microsoft.graph.conflictBehavior": "rename"
    }
    r_create = requests.post(create_url, headers={**headers, "Content-Type": "application/json"}, json=payload)
    
    if not r_create.ok:
         raise SystemExit(f"Failed to create folder: {r_create.status_code}\n{r_create.text}")

    new_folder_id = r_create.json()["id"]
    print(f"Folder '{folder_name}' created. ID: {new_folder_id}", file=sys.stderr)
    return new_folder_id

# Step 3: Grant direct, scoped folder access
def grant_folder_access(headers, item_id, email_list, sub_folder_name):
    """
    Grants direct, scoped permission to a list of users via the /invite endpoint.
    This prevents users from navigating to the parent folder.
    """
    print(f"Granting direct access for: {', '.join(email_list)}...", file=sys.stderr)
    
    url = f"{GRAPH_BASE}/sites/root/drive/items/{item_id}/invite"
    recipients_payload = [{"email": email} for email in email_list]

    payload = {
        "recipients": recipients_payload,
        "message": f"You have been granted access to the '{sub_folder_name}' data folder. This is an automated notification.",
        "requireSignIn": True,
        "sendInvitation": True,
        "roles": ["read"]
    }
    
    r = requests.post(url, headers={**headers, "Content-Type": "application/json"}, json=payload)
    
    if not r.ok:
        raise Exception(f"Failed to grant access: {r.status_code}\n{r.text}")

    permissions = r.json().get("value", [])
    if not permissions:
        raise Exception("Invite sent, but no permission data was returned.")
    
    link = permissions[0].get("link", {}).get("webUrl")
    
    if not link:
        print("Warning: Invite sent, but no webUrl was found in the API response.", file=sys.stderr)
        return f"Access granted to item {item_id} (no direct link returned)"

    return link

# Step 4: Create an upload session and upload a single file
def upload_file(headers, parent_id, local_file_path):
    
    if not os.path.exists(local_file_path):
        raise FileNotFoundError(f"The specified file does not exist: {local_file_path}")

    print(f"Creating upload session for {local_file_path}...", file=sys.stderr)
    file_name_only = os.path.basename(local_file_path)
    url = f"{GRAPH_BASE}/sites/root/drive/items/{parent_id}:/{file_name_only}:/createUploadSession"
    
    r = requests.post(url, headers=headers, json={"item": {"@microsoft.graph.conflictBehavior": "replace"}})
    r.raise_for_status()
    upload_url = r.json()["uploadUrl"]

    filesize = os.path.getsize(local_file_path)
    chunk_size = 5 * 1024 * 1024 # 5 MB

    with open(local_file_path, "rb") as f:
        start = 0
        while start < filesize:
            chunk = f.read(chunk_size)
            end = start + len(chunk) - 1
            headers_chunk = {
                "Content-Length": str(len(chunk)),
                "Content-Range": f"bytes {start}-{end}/{filesize}"
            }
            
            print(f"  Uploading chunk: bytes {start}-{end}/{filesize}", file=sys.stderr)
            rr = requests.put(upload_url, headers=headers_chunk, data=chunk)
            
            if rr.status_code not in (200, 201, 202):
                raise Exception(f"Chunk upload failed: {rr.status_code}\n{rr.text}")
            
            start = end + 1
            
    print(f"File '{local_file_path}' uploaded successfully.", file=sys.stderr)


# Main execution logic
def main():
    """
    Main execution logic of the script.
    Returns a dictionary for JSON output.
    """
    # --- Setup argument parser with named flags ---
    parser = argparse.ArgumentParser(
        description=f"Find/Create a folder in '{BASE_FOLDER_NAME}' and upload files to it.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    
    parser.add_argument(
        "-f", "--folder",
        dest="subfolder",
        default="public",
        help="Name of the subfolder to create/use inside 'GlycoShield'.\n(default: 'public')"
    )
    
    parser.add_argument(
        "-fl", "--files",
        dest="files_to_upload",
        nargs="+",
        default=["test_upload.txt"],
        help="One or more paths to local files you want to upload (space-separated).\n(default: 'test_upload.txt')"
    )

    parser.add_argument(
        "-e", "--email",
        dest="new_emails",
        nargs="+",
        default=[],
        help="One or more recipient emails (space-separated) to *add* to the sharing link.\n"
             f"(will be added to the default: {DEFAULT_RECIPIENT_EMAILS[0]})"
    )
    
    args = parser.parse_args()
    
    # --- Use the arguments ---
    sub_folder_name = args.subfolder
    files_to_upload = args.files_to_upload
    
    recipient_emails = DEFAULT_RECIPIENT_EMAILS.copy()
    if args.new_emails:
        recipient_emails.extend(args.new_emails)
    
    print(f"Target subfolder: '{sub_folder_name}'", file=sys.stderr)
    print(f"Files to upload: {', '.join(files_to_upload)}", file=sys.stderr)
    print(f"Recipient emails: {', '.join(recipient_emails)}", file=sys.stderr)
    print("-" * 30, file=sys.stderr)

    token = get_access_token()
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Get or create the base folder in the 'root'
    glycoshield_id = get_or_create_folder(headers, "root", BASE_FOLDER_NAME)

    # 2. Get or create the subfolder using the command-line argument
    subfolder_id = get_or_create_folder(headers, glycoshield_id, sub_folder_name)
    print(f"Using subfolder '{sub_folder_name}' (ID: {subfolder_id})", file=sys.stderr)

    # --- MODIFIED: Step 3 is now uploading files ---
    # 3. Handle file uploads
    # Handle the special default case: create dummy file if it doesn't exist
    if files_to_upload == ["test_upload.txt"] and not os.path.exists("test_upload.txt"):
        print("\nDefault file 'test_upload.txt' not found. Creating dummy file for upload...", file=sys.stderr)
        with open("test_upload.txt", "w") as f:
            f.write("This is a test upload file.")

    successfully_uploaded_files = []
    
    for file_path in files_to_upload:
        # (Fix: Use len(successfully_uploaded_files) for correct count)
        print(f"\n--- Uploading file {len(successfully_uploaded_files) + 1} of {len(files_to_upload)}: {file_path} ---", file=sys.stderr)
        upload_file(headers, subfolder_id, file_path)
        successfully_uploaded_files.append(file_path)

    # --- MODIFIED: Step 4 is now granting access (after upload) ---
    # 4. Grant access and create the sharing link for the subfolder
    share_link = grant_folder_access(headers, subfolder_id, recipient_emails, sub_folder_name)
    print(f"Direct access granted. Invite link: {share_link}", file=sys.stderr)
    
    # 5. Create the success output dictionary
    output_data = {
        "status": "success",
        "base_folder": BASE_FOLDER_NAME,
        "sub_folder": sub_folder_name,
        "sub_folder_id": subfolder_id,
        "files_uploaded": successfully_uploaded_files,
        "shared_with": recipient_emails,
        "invite_link": share_link
    }
    
    return output_data


# ========== MAIN EXECUTION ==========
if __name__ == "__main__":
    try:
        # Call main function and get output data
        success_data = main()
        # Print final JSON to STDOUT
        print(json.dumps(success_data, indent=2))
        sys.exit(0) # Exit with success code

    except Exception as e:
        # Catch all exceptions and print failure JSON
        
        # Optionally, print the full traceback to stderr for debugging
        import traceback
        print(f"--- SCRIPT FAILED ---", file=sys.stderr)
        print(traceback.format_exc(), file=sys.stderr)
        print(f"-----------------------", file=sys.stderr)

        failure_data = {
            "status": "failure",
            "error": str(e)
        }
        # Print failure JSON to STDOUT
        print(json.dumps(failure_data, indent=2))
        sys.exit(1) # Exit with failure code