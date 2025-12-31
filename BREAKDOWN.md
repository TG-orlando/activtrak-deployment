# Code Breakdown - ActivTrak Deployment

## 📋 Overview

This repository provides automated deployment of ActivTrak employee monitoring software via Rippling MDM and other enterprise deployment tools. ActivTrak tracks employee productivity and application usage.

---

## 📁 File Structure

```
.
├── Install-ActivTrak.ps1      # Main installation script
├── update_activtrak_msi.py    # GitHub release updater
├── README.md                  # User documentation
├── UPDATING-MSI.md           # MSI update guide
├── SESSION-HISTORY.md        # Development session log
└── BREAKDOWN.md              # This file
```

---

## 🔧 Main Script: `Install-ActivTrak.ps1`

### Purpose
Automates ActivTrak agent installation on Windows endpoints with proper authentication, logging, and error handling.

### Critical Design Decisions

#### 1. **Filename-Based Authentication**
**Choice**: Use original MSI filename format from ActivTrak portal
**Reason**:
- ActivTrak embeds credentials IN the filename, not as parameters
- Format: `ATAcct######(version)_AgentKey_Timestamp.msi`
- Renaming breaks authentication
- Account number + agent key must match exactly

**Why This Matters**:
```powershell
# CORRECT - Original filename preserved
ATAcct680398(8.6.6.0)_1szujUFkra0G_14519925690.msi

# WRONG - Renamed, will fail authentication
ActivTrak-Installer.msi  # Missing credentials!
```

#### 2. **GitHub Releases for Distribution**
**Choice**: Host MSI in GitHub releases, not repository
**Reason**:
- MSI files are 20-30MB (too large for git)
- Releases provide versioning
- Easy download URLs
- No repository bloat
- Can update without new commits

#### 3. **Dual Download Strategy**
```powershell
# Option 1: Download from GitHub release (recommended)
$downloadUrl = "https://github.com/.../releases/download/v2.0.0/ActivTrak.msi"

# Option 2: Use local file
$localMsiPath = "C:\Temp\ActivTrak.msi"
```

**Why Both Options**:
- GitHub for automated MDM deployment
- Local for manual/offline installation
- Flexibility for different scenarios
- Testing without network dependency

---

### Code Structure Breakdown

#### Section 1: Pre-Installation Checks (Lines 82-140)

```powershell
# Check Windows Installer service
$msiService = Get-Service -Name "msiserver"
if ($msiService.Status -ne 'Running') {
    Start-Service -Name "msiserver"
}

# Add Windows Defender exclusions
Add-MpPreference -ExclusionPath "C:\Program Files\ActivTrak"
Add-MpPreference -ExclusionProcess "ATAgentService.exe"

# Check for existing installation
$existingInstall = Get-WmiObject -Class Win32_Product |
    Where-Object { $_.Name -like "*ActivTrak*" }
```

**Why Each Check**:
- **MSI Service**: Must be running for installations
- **Defender Exclusions**: Prevents quarantine of monitoring agent
- **Existing Install**: Determines upgrade vs. fresh install

**Choice**: Add Defender exclusions proactively
**Reason**:
- ActivTrak monitors processes (looks like malware to AV)
- Prevents installation failures
- Standard for endpoint monitoring tools

#### Section 2: Download Handling (Lines 150-200)

```powershell
Write-Log "Downloading ActivTrak installer from GitHub..."
Write-Log "Download URL: $downloadUrl"

$webClient = New-Object System.Net.WebClient
$webClient.DownloadFile($downloadUrl, $installerPath)

if (-not (Test-Path $installerPath)) {
    throw "Download failed - file not found at $installerPath"
}

$fileSize = (Get-Item $installerPath).Length / 1MB
Write-Log "Downloaded successfully. Size: $([math]::Round($fileSize, 2)) MB"
```

**Why WebClient over Invoke-WebRequest**:
- Faster for large files
- Simpler API for single download
- Works in PowerShell 5.1+
- Better timeout handling

**Choice**: Verify file after download
**Reason**:
- Network errors may create empty file
- Corrupted downloads fail silently
- Size check validates successful download

#### Section 3: Silent Installation (Lines 220-260)

```powershell
# CRITICAL: Use /qn for fully silent installation
# DO NOT use command-line properties - credentials are in filename!

$msiArgs = @(
    "/i", "`"$installerPath`"",
    "/qn",                    # Completely silent
    "/norestart",             # Don't reboot
    "/l*v", "`"$msiLogPath`"" # Verbose logging
)

$process = Start-Process -FilePath "msiexec.exe" `
                         -ArgumentList $msiArgs `
                         -Wait `
                         -PassThru `
                         -NoNewWindow

if ($process.ExitCode -eq 0) {
    Write-Log "ActivTrak installed successfully!" "SUCCESS"
} elseif ($process.ExitCode -eq 3010) {
    Write-Log "Installation successful - reboot required" "WARNING"
} else {
    throw "Installation failed with exit code: $($process.ExitCode)"
}
```

**MSI Exit Codes**:
- **0**: Success
- **3010**: Success, reboot required
- **1603**: Fatal error
- **1618**: Another installation in progress
- **1619**: Installation package could not be opened

**Why No Custom Properties**:
- ActivTrak uses filename for authentication
- Properties like `ACCOUNT_ID` are ignored
- Passing properties causes confusion
- Simpler is better

**Choice**: Verbose logging `/l*v`
**Reason**:
- Captures all MSI operations
- Essential for troubleshooting
- Logs permissions, registry, files
- Windows standard practice

#### Section 4: Post-Installation Verification (Lines 270-320)

```powershell
# Verify service installation
$atService = Get-Service -Name "ATAgentService" -ErrorAction SilentlyContinue
if ($atService) {
    Write-Log "ActivTrak service found: $($atService.Status)"

    if ($atService.Status -ne 'Running') {
        Write-Log "Starting ActivTrak service..."
        Start-Service -Name "ATAgentService"
        Start-Sleep -Seconds 5
    }
} else {
    Write-Log "WARNING: ActivTrak service not found" "WARNING"
}

# Verify installation directory
if (Test-Path "C:\Program Files\ActivTrak") {
    Write-Log "ActivTrak installed at: C:\Program Files\ActivTrak"
    $agentExe = "C:\Program Files\ActivTrak\ATAgent.exe"
    if (Test-Path $agentExe) {
        $version = (Get-Item $agentExe).VersionInfo.FileVersion
        Write-Log "Agent version: $version" "SUCCESS"
    }
}
```

**Why Verify Service**:
- MSI exit code 0 doesn't guarantee service running
- Service may install but fail to start
- Silent failures possible
- Essential for monitoring tool

**Choice**: Start service if not running
**Reason**:
- Installation doesn't always start service
- Agent needs to be active immediately
- MDM expects immediate functionality

---

## 🐍 Update Script: `update_activtrak_msi.py`

### Purpose
Automates uploading new ActivTrak MSI files to GitHub releases.

### Key Design Decisions

#### 1. **Python over PowerShell**
**Choice**: Python for GitHub API interaction
**Reason**:
- Easier GitHub API handling
- Better JSON parsing
- Cross-platform (can run on Mac/Linux)
- PyGithub library simplifies releases

#### 2. **Semantic Versioning**
```python
# Auto-increment version
latest_release = repo.get_latest_release()
current_version = latest_release.tag_name  # e.g., "v2.0.0"
major, minor, patch = parse_version(current_version)
new_version = f"v{major}.{minor}.{patch + 1}"  # v2.0.1
```

**Why Auto-Increment**:
- Consistent versioning
- No manual tracking
- Release history clear
- Matches MSI version changes

#### 3. **Filename Preservation**
```python
# Extract original filename
original_filename = input_filename  # Keep exact format
# Upload with preserved name
release.upload_asset(msi_file, name=original_filename)
```

**Critical**: Filename must match ActivTrak format
**Reason**: Embedded credentials require exact format

---

## 🎯 Design Patterns Used

### 1. **Defensive Programming**
- Check every assumption
- Verify downloads succeeded
- Validate services installed
- Test paths exist before using

### 2. **Comprehensive Logging**
- Every operation logged
- Timestamp all events
- Color-coded console output
- MSI verbose logs preserved

### 3. **Fail-Fast with Details**
```powershell
if ($process.ExitCode -ne 0) {
    Write-Log "Installation failed with exit code: $($process.ExitCode)" "ERROR"
    Write-Log "Check MSI log at: $msiLogPath" "ERROR"
    throw "Installation failed"
}
```

**Why**:
- Errors detected immediately
- Context provided for troubleshooting
- Logs referenced for details

---

## 🔒 Security Considerations

### 1. **Credential Handling**
**Method**: Embedded in MSI filename
**Why Safe**:
- Agent key, not password
- Scoped to specific account
- Rotatable from ActivTrak portal
- No plaintext passwords

### 2. **Windows Defender Exclusions**
**Concern**: Disabling AV protection
**Mitigation**:
- Specific path exclusions only
- Process-level exclusions
- Standard for monitoring tools
- ActivTrak is legitimate software

### 3. **Download Security**
**Method**: HTTPS from GitHub
**Benefits**:
- TLS encryption
- GitHub's CDN
- Verified source
- No MitM possible

---

## 📊 MDM Deployment Pattern

### Rippling MDM Configuration

```powershell
# Script content for Rippling:
powershell.exe -ExecutionPolicy Bypass -Command "& {
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/TG-orlando/activtrak-deployment/main/Install-ActivTrak.ps1' -OutFile '$env:TEMP\Install-ActivTrak.ps1';
    & '$env:TEMP\Install-ActivTrak.ps1'
}"
```

**Why This Pattern**:
- One-line deployment
- No file pre-staging
- Always gets latest script
- Standard PowerShell remoting

---

## 💡 Best Practices Implemented

1. ✅ Preserves original MSI filename (critical)
2. ✅ Comprehensive logging
3. ✅ Pre-installation environment checks
4. ✅ Post-installation verification
5. ✅ Graceful error handling
6. ✅ Clear user feedback
7. ✅ MSI standard practices (silent install, logging)
8. ✅ Service management
9. ✅ Windows Defender integration
10. ✅ Version tracking via GitHub releases

---

## 🔄 Update Workflow

### When New ActivTrak Version Released

1. **Download new MSI** from ActivTrak portal
2. **Run update script**:
   ```bash
   python3 update_activtrak_msi.py ATAcct680398_new_token.msi
   ```
3. **Script automatically**:
   - Creates new GitHub release
   - Increments version number
   - Uploads MSI file
   - Updates download URL

4. **MDM gets new version** on next deployment
   - Script pulls from latest release
   - Installs new version
   - Upgrades existing installations

---

## 🐛 Common Issues & Solutions

### Issue: Installation Fails with Error 1603
**Cause**: MSI filename doesn't match ActivTrak format
**Solution**: Use exact filename from portal, don't rename

### Issue: Service Not Running
**Cause**: Windows Defender quarantined agent
**Solution**: Script adds exclusions proactively

### Issue: "Another installation is in progress" (1618)
**Cause**: Windows Installer busy
**Solution**: Script checks and waits for msiserver

### Issue: Download Fails
**Cause**: GitHub URL incorrect or network issue
**Solution**: Verify release exists, check network

---

## 📚 References

- **ActivTrak Documentation**: https://support.activtrak.com
- **MSI Installation**: https://docs.microsoft.com/windows-installer
- **Windows Defender Exclusions**: https://docs.microsoft.com/defender
- **GitHub Releases API**: https://docs.github.com/en/rest/releases

---

## 🆚 Why This Approach

### Alternative: Group Policy Deployment
**❌ Why Not**:
- Requires Active Directory
- Complex GPO setup
- Harder to update
- Not cloud-friendly

### Alternative: SCCM/Intune
**❌ Why Not**:
- Overkill for single application
- Additional infrastructure needed
- License costs
- Complexity

### ✅ Our Approach: GitHub + MDM
**Benefits**:
- Simple, lightweight
- Works with any MDM (Rippling, Jamf, etc.)
- Easy updates via GitHub releases
- Version control included
- No additional infrastructure

---

**Last Updated**: December 30, 2024
**Maintained By**: TG-orlando
**Repository**: https://github.com/TG-orlando/activtrak-deployment
