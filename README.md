# ActivTrak Deployment

This repository hosts the ActivTrak MSI installer for enterprise deployment via Rippling MDM and other deployment tools.

## Installation

Use the PowerShell installation script to deploy ActivTrak to Windows endpoints.

### Quick Deploy

Download and run the installation script:

```powershell
# Download the installation script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/TG-orlando/activtrak-deployment/main/Install-ActivTrak.ps1" -OutFile "Install-ActivTrak.ps1"

# Run with Administrator privileges
.\Install-ActivTrak.ps1
```

## Files

- **ActivTrak.msi** - ActivTrak Agent installer (version 8.6.6.0)
- **Install-ActivTrak.ps1** - Automated installation script with error handling and logging

## Features

The installation script includes:
- Automatic administrator privilege elevation
- Download timeout protection
- MSI file validation
- Existing installation cleanup
- Comprehensive error handling and logging
- Installation verification

## Releases

Download the latest ActivTrak installer from the [Releases](https://github.com/TG-orlando/activtrak-deployment/releases) page.

## Support

For issues with the deployment script, open an issue in this repository.
For ActivTrak product support, contact ActivTrak directly.
