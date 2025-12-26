#!/usr/bin/env python3
"""
ActivTrak MSI Update Automation
Uploads new MSI to GitHub with consistent filename

Usage:
    python3 update_activtrak_msi.py

Environment Variables:
    GITHUB_TOKEN - GitHub Personal Access Token with 'repo' permissions

Author: TG IT Team
Repository: https://github.com/TG-orlando/activtrak-deployment
"""

import os
import sys
import hashlib
import json
import urllib.request
from pathlib import Path

# Configuration
REPO = "TG-orlando/activtrak-deployment"
RELEASE_TAG = "v2.0.0"
CONSISTENT_FILENAME = "ActivTrak-Account-680398.msi"

def find_latest_msi():
    """Find the most recent ActivTrak MSI in Downloads"""
    downloads = Path.home() / "Downloads"
    msi_files = list(downloads.glob("ATAcct680398*.msi"))

    if not msi_files:
        return None

    # Sort by modification time, newest first
    msi_files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return msi_files[0]

def calculate_sha256(file_path):
    """Calculate SHA256 hash of file"""
    sha256 = hashlib.sha256()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            sha256.update(chunk)
    return sha256.hexdigest()

def get_github_token():
    """Get GitHub token from environment variable"""
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        print("❌ ERROR: GITHUB_TOKEN environment variable not set")
        print()
        print("Please set your GitHub Personal Access Token:")
        print()
        print("Option 1 - Add to shell profile (recommended):")
        print('  echo \'export GITHUB_TOKEN="ghp_YourTokenHere"\' >> ~/.zshrc')
        print("  source ~/.zshrc")
        print()
        print("Option 2 - Set for this session only:")
        print('  export GITHUB_TOKEN="ghp_YourTokenHere"')
        print()
        print("Option 3 - Pass inline:")
        print('  GITHUB_TOKEN="ghp_YourTokenHere" python3 update_activtrak_msi.py')
        print()
        print("Get a token at: https://github.com/settings/tokens")
        print("Required permissions: repo (Full control of private repositories)")
        sys.exit(1)
    return token

def main():
    print("=" * 50)
    print("ActivTrak MSI Update Automation")
    print("=" * 50)
    print()

    # Get GitHub token
    github_token = get_github_token()

    # Find MSI
    print("Looking for ActivTrak MSI in Downloads...")
    msi_file = find_latest_msi()

    if not msi_file:
        print("❌ ERROR: No ActivTrak MSI found in Downloads")
        print()
        print("Please download the MSI from ActivTrak portal first:")
        print("1. Go to: https://app.activtrak.com")
        print("2. Navigate to: Settings > Agents > Download Agent")
        print("3. Select: 'MSI for mass deployment'")
        print("4. Download the MSI")
        print("5. Run this script again")
        sys.exit(1)

    print(f"✅ Found MSI: {msi_file.name}")
    print(f"   Size: {msi_file.stat().st_size / (1024*1024):.2f} MB")
    print()

    # Calculate hash
    print("Calculating SHA256 hash...")
    sha256 = calculate_sha256(msi_file)
    print(f"✅ SHA256: {sha256}")
    print()

    # Get release info
    print("Fetching release information...")
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases/tags/{RELEASE_TAG}",
        headers={
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json"
        }
    )

    try:
        with urllib.request.urlopen(req) as response:
            release_data = json.loads(response.read().decode())
            release_id = release_data['id']
    except urllib.error.HTTPError as e:
        print(f"❌ ERROR: Could not find release {RELEASE_TAG}")
        print(f"HTTP Error {e.code}: {e.reason}")
        if e.code == 401:
            print()
            print("Authentication failed. Please check your GITHUB_TOKEN.")
        elif e.code == 404:
            print()
            print("Release not found. Verify the repository and release tag.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ ERROR: Could not find release {RELEASE_TAG}")
        print(f"Error: {e}")
        sys.exit(1)

    print(f"✅ Found release ID: {release_id}")
    print()

    # Check for existing asset
    print("Checking for existing asset...")
    existing_asset = None
    for asset in release_data.get('assets', []):
        if asset['name'] == CONSISTENT_FILENAME:
            existing_asset = asset
            break

    if existing_asset:
        print(f"⚠️  Found existing asset (ID: {existing_asset['id']})")
        print("   Deleting old version...")

        delete_req = urllib.request.Request(
            f"https://api.github.com/repos/{REPO}/releases/assets/{existing_asset['id']}",
            headers={
                "Authorization": f"token {github_token}",
                "Accept": "application/vnd.github.v3+json"
            },
            method='DELETE'
        )

        try:
            with urllib.request.urlopen(delete_req) as response:
                print("✅ Old asset deleted")
        except Exception as e:
            print(f"⚠️  Warning: Could not delete old asset: {e}")
    else:
        print("ℹ️  No existing asset found (this is the first upload)")

    print()
    print("Uploading new MSI to GitHub...")
    print(f"Upload filename: {CONSISTENT_FILENAME}")
    print("(This may take 30-60 seconds...)")
    print()

    # Upload new asset
    with open(msi_file, 'rb') as f:
        file_data = f.read()

    upload_req = urllib.request.Request(
        f"https://uploads.github.com/repos/{REPO}/releases/{release_id}/assets?name={CONSISTENT_FILENAME}",
        data=file_data,
        headers={
            "Authorization": f"token {github_token}",
            "Content-Type": "application/octet-stream"
        },
        method='POST'
    )

    try:
        with urllib.request.urlopen(upload_req) as response:
            upload_data = json.loads(response.read().decode())
            download_url = upload_data['browser_download_url']

            print()
            print("=" * 50)
            print("✅ SUCCESS! MSI Updated")
            print("=" * 50)
            print()
            print("Download URL (never changes):")
            print(download_url)
            print()
            print(f"Original filename: {msi_file.name}")
            print(f"GitHub filename: {CONSISTENT_FILENAME}")
            print(f"SHA256: {sha256}")
            print()
            print("The installation script will now use this new MSI.")
            print("No script changes needed!")
            print("=" * 50)
    except urllib.error.HTTPError as e:
        print()
        print(f"❌ ERROR: Upload failed (HTTP {e.code})")
        print(f"Reason: {e.reason}")
        error_body = e.read().decode('utf-8', errors='ignore')
        if error_body:
            try:
                error_json = json.loads(error_body)
                print(f"Message: {error_json.get('message', 'Unknown error')}")
            except:
                print(f"Response: {error_body[:200]}")
        sys.exit(1)
    except Exception as e:
        print()
        print(f"❌ ERROR: Upload failed")
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
