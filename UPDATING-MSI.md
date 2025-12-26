# ActivTrak MSI Update Guide

This guide explains how to update the ActivTrak MSI file when it expires (every 72 hours).

## Overview

The ActivTrak MSI installer expires after 72 hours for security reasons. When this happens, you need to:
1. Download a fresh MSI from the ActivTrak portal
2. Upload it to GitHub with a consistent filename
3. The deployment script URL never changes - it always points to the latest version

## Prerequisites

- Access to ActivTrak portal (https://app.activtrak.com)
- GitHub repository access (TG-orlando/activtrak-deployment)
- GitHub Personal Access Token with `repo` permissions
- Python 3 installed on your Mac

## Setup (One-Time)

### 1. Get Your GitHub Personal Access Token

If you don't already have a token:

1. Go to https://github.com/settings/tokens
2. Click **"Generate new token"** > **"Generate new token (classic)"**
3. Give it a name: `ActivTrak MSI Upload`
4. Select scopes: Check **`repo`** (Full control of private repositories)
5. Click **"Generate token"**
6. **Copy the token immediately** (you won't see it again)

### 2. Set Up Environment Variable

Add your GitHub token to your shell profile:

```bash
# Open your shell profile
nano ~/.zshrc

# Add this line at the end (replace with your actual token)
export GITHUB_TOKEN="ghp_YourTokenHere"

# Save and exit (Ctrl+X, then Y, then Enter)

# Reload your profile
source ~/.zshrc
```

**Alternative:** You can also pass the token when running the script:
```bash
GITHUB_TOKEN="ghp_YourTokenHere" python3 update_activtrak_msi.py
```

## Update Process (Every 72 Hours)

### Step 1: Download New MSI from ActivTrak

1. Go to https://app.activtrak.com
2. Navigate to: **Settings** > **Agents** > **Download Agent**
3. Select: **"MSI for mass deployment"**
4. Click **Download**

The file will be saved to your Downloads folder with a name like:
```
ATAcct680398(8.6.6.0)_1szujUFkra0G_14519925690.msi
```

### Step 2: Run the Update Script

```bash
# Navigate to the repo
cd ~/activtrak-repo

# Run the update script
python3 update_activtrak_msi.py
```

### Step 3: Verify Success

You should see output like this:

```
==================================================
ActivTrak MSI Update Automation
==================================================

Looking for ActivTrak MSI in Downloads...
✅ Found MSI: ATAcct680398(8.6.6.0)_1szujUFkra0G_14519925690.msi
   Size: 26.76 MB

Calculating SHA256 hash...
✅ SHA256: 50410cb132173032ceec69cc029e390bddb63568683eae9fbc7d94906d48630e

Fetching release information...
✅ Found release ID: 272921386

Checking for existing asset...
⚠️  Found existing asset (ID: 333195379)
   Deleting old version...
✅ Old asset deleted

Uploading new MSI to GitHub...
Upload filename: ActivTrak-Account-680398.msi

==================================================
✅ SUCCESS! MSI Updated
==================================================

Download URL (never changes):
https://github.com/TG-orlando/activtrak-deployment/releases/download/v2.0.0/ActivTrak-Account-680398.msi

Original filename: ATAcct680398(8.6.6.0)_1szujUFkra0G_14519925690.msi
GitHub filename: ActivTrak-Account-680398.msi
SHA256: 50410cb132173032ceec69cc029e390bddb63568683eae9fbc7d94906d48630e

The installation script will now use this new MSI.
No script changes needed!
==================================================
```

## Important Notes

### Download URL Never Changes
The deployment script always uses this URL:
```
https://github.com/TG-orlando/activtrak-deployment/releases/download/v2.0.0/ActivTrak-Account-680398.msi
```

This means:
- ✅ No need to update the deployment script
- ✅ No need to update Rippling MDM configuration
- ✅ No need to modify any documentation
- ✅ Deployments continue working seamlessly

### Filename Consistency
The script automatically:
- Finds the newest ActivTrak MSI in your Downloads folder
- Uploads it with the consistent filename: `ActivTrak-Account-680398.msi`
- Deletes the old version from GitHub first
- Keeps the download URL the same

### Security
- The MSI file contains embedded account credentials in its original filename
- These credentials are valid for 72 hours from download
- The GitHub-hosted version inherits the expiration from when you downloaded it
- Always keep the MSI updated to avoid deployment failures

## Troubleshooting

### Error: "No ActivTrak MSI found in Downloads"
**Solution:** Download a fresh MSI from the ActivTrak portal first.

### Error: "Could not find release v2.0.0"
**Solution:** Verify you have access to the GitHub repository and your token has `repo` permissions.

### Error: "Upload failed"
**Solution:**
1. Check your GitHub token is valid
2. Ensure you have write access to the repository
3. Verify your internet connection

### Error: "ModuleNotFoundError: No module named 'X'"
**Solution:** The script uses only Python standard library modules. Make sure you're using Python 3.6+.

## Maintenance Schedule

Set a reminder to update the MSI:
- **Frequency:** Every 72 hours (3 days)
- **Recommended:** Monday morning and Thursday morning weekly
- **Or:** Wait for deployment failures and update reactively

## Files in This Repository

- **`update_activtrak_msi.py`** - Automation script to upload new MSI
- **`Install-ActivTrak.ps1`** - Windows deployment script
- **`README.md`** - Main repository documentation
- **`UPDATING-MSI.md`** - This guide

## Support

For issues with:
- **This update process** - Contact the IT/DevOps team or check this repository's issues
- **ActivTrak product** - Contact ActivTrak support at https://support.activtrak.com
- **GitHub access** - Contact your GitHub organization admin

## Quick Reference

```bash
# Full update process (copy/paste)
cd ~/activtrak-repo
git pull origin main
python3 update_activtrak_msi.py
```

---

**Last Updated:** 2025-12-26
**Repository:** https://github.com/TG-orlando/activtrak-deployment
