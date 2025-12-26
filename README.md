# ActivTrak Deployment

This repository hosts the ActivTrak MSI installer for enterprise deployment via Rippling MDM and other deployment tools.

## ⚠️ IMPORTANT: MSI Filename Requirements

ActivTrak MSI files **must** maintain their original filename format from the ActivTrak portal:
- **Correct format:** `ATAcct680398_{RandomSecurityToken}.msi`
- **DO NOT rename** the MSI file or deployment will fail
- Account credentials are **embedded in the filename**, not passed as command-line parameters

## Prerequisites

1. Download the pre-configured MSI from your ActivTrak portal:
   - Login to: https://app.activtrak.com
   - Navigate to: **Settings > Agents > Download Agent**
   - Select: **"MSI for mass deployment"**
   - Download and upload to this repository's [Releases](https://github.com/TG-orlando/activtrak-deployment/releases) page

2. Update the `$downloadUrl` variable in the installation script with your GitHub release URL

## Installation

Use the PowerShell installation script to deploy ActivTrak to Windows endpoints.

### Quick Deploy

```powershell
# Download the installation script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TG-orlando/activtrak-deployment/main/Install-ActivTrak.ps1" -OutFile "Install-ActivTrak.ps1"

# Run with Administrator privileges
.\Install-ActivTrak.ps1
```

### Manual Installation

```powershell
# Silent installation (no properties needed - credentials in filename)
MSIEXEC /i ATAcct680398_{token}.msi /qn /norestart /l*v %TEMP%\atinstall.log
```

Optional Chrome extension:
```powershell
MSIEXEC /i ATAcct680398_{token}.msi USE_CHROME_EXT=1 /qn
```

## Files

- **ATAcct######_{token}.msi** - Pre-configured ActivTrak Agent installer (download from portal)
- **Install-ActivTrak.ps1** - Automated installation script with error handling and logging

## Features

The installation script includes:
- **MSI filename validation** - Ensures correct format before installation
- Automatic administrator privilege elevation
- Download timeout protection
- Existing installation cleanup
- Comprehensive error handling and logging
- Installation verification
- Windows Defender exclusions
- Service status verification

## Common Issues

### Exit Code 1603 - Fatal Error
**Cause:** Incorrect MSI filename format
**Solution:** Download pre-configured MSI from ActivTrak portal with proper filename format

### Account Not Associating
**Cause:** MSI file was renamed
**Solution:** Re-download MSI from portal and keep original filename

## Supported Deployment Methods

- Command Line / PowerShell
- Active Directory Group Policy
- Microsoft Intune / Endpoint Manager
- Rippling MDM
- Other MDM/RMM tools

## Releases

1. Download the pre-configured MSI from [ActivTrak Portal](https://app.activtrak.com)
2. Upload to [Releases](https://github.com/TG-orlando/activtrak-deployment/releases) page
3. Update installation script with release URL

## Support

- **ActivTrak Portal:** https://app.activtrak.com
- **Help Center:** https://support.activtrak.com
- **Deployment Guide:** https://support.activtrak.com/hc/en-us/articles/360039249211
- **Command Line Install:** https://support.activtrak.com/hc/en-us/articles/360037451572

For issues with the deployment script, open an issue in this repository.
For ActivTrak product support, contact ActivTrak directly.
