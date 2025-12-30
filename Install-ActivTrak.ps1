# ActivTrak Installation Script - CORRECTED VERSION
# Based on official ActivTrak documentation
# Version: 4.0
#
# IMPORTANT: This script requires a properly named MSI from ActivTrak portal
# MSI filename format: ATAcctXXXXXX_{RandomSecurityToken}.msi
#
# Download your pre-configured MSI from:
# https://app.activtrak.com > Settings > Agents > Download Agent

$ErrorActionPreference = "Stop"

# ===== CONFIGURATION =====
# CRITICAL: You must download the MSI from ActivTrak portal
# The MSI filename MUST match this pattern: ATAcct######_{token}.msi
# DO NOT rename the file or installation will fail!

# Option 1: Download from GitHub release (recommended)
$downloadUrl = "https://github.com/TG-orlando/activtrak-deployment/releases/download/v2.0.0/ActivTrak-Account-680398.msi"

# Option 2: Use local file if already downloaded
# $localMsiPath = "C:\Temp\ATAcct680398(8.6.6.0)_1szujUFkra0G_14519925690.msi"
# ========================

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Script is not running as Administrator. Attempting to elevate..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -Wait
        exit
    } else {
        $tempScript = "$env:TEMP\ActivTrak_Elevation_$(Get-Date -Format 'yyyyMMddHHmmss').ps1"
        $MyInvocation.MyCommand.ScriptBlock.ToString() | Out-File -FilePath $tempScript -Force -Encoding UTF8
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs -Wait
        Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
        exit
    }
}

Write-Host "Running with Administrator privileges" -ForegroundColor Green

# Configuration
# CRITICAL: Use the EXACT filename format from the original ActivTrak portal download
# The filename must include: Account number, version in parentheses, agent key, and timestamp
# Format: ATAcct######(version)_AgentKey_Timestamp.msi
$installerPath = "$env:TEMP\ATAcct680398(8.6.6.0)_1szujUFkra0G_14519925690.msi"
$logPath = "$env:TEMP\ActivTrak_Install.log"
$msiLogPath = "$env:TEMP\ActivTrak_MSI_Install.log"
$downloadTimeoutSeconds = 600

# Function to write log
function Write-Log {
    param($Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"
    $logMessage | Out-File -FilePath $logPath -Append

    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "INFO" { Write-Host $Message -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

try {
    Write-Log "=========================================" "INFO"
    Write-Log "ActivTrak Installation Script v4.0 (CORRECTED)" "INFO"
    Write-Log "Based on Official ActivTrak Documentation" "INFO"
    Write-Log "=========================================" "INFO"
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "User: $env:USERNAME"
    Write-Log "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "=========================================" "INFO"
    Write-Log ""

    # PRE-INSTALLATION CHECKS
    Write-Log "Running pre-installation checks..." "INFO"

    # Check Windows Installer service
    Write-Log "Checking Windows Installer service..."
    $msiService = Get-Service -Name "msiserver" -ErrorAction SilentlyContinue
    if ($msiService) {
        Write-Log "Windows Installer service status: $($msiService.Status)"
        if ($msiService.Status -ne 'Running') {
            Write-Log "Starting Windows Installer service..." "WARNING"
            Start-Service -Name "msiserver" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    }

    # Add Windows Defender exclusions
    Write-Log "Adding Windows Defender exclusions..."
    try {
        Add-MpPreference -ExclusionPath "C:\Program Files\ActivTrak" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath "C:\Program Files (x86)\ActivTrak" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "ActivTrakAgent.exe" -ErrorAction SilentlyContinue
        Write-Log "Windows Defender exclusions added" "SUCCESS"
    } catch {
        Write-Log "Could not add Defender exclusions: $($_.Exception.Message)" "WARNING"
    }

    Write-Log ""
    Write-Log "=========================================" "WARNING"
    Write-Log "IMPORTANT NOTICE" "WARNING"
    Write-Log "=========================================" "WARNING"
    Write-Log "ActivTrak requires a pre-configured MSI downloaded from your portal!" "WARNING"
    Write-Log ""
    Write-Log "Steps to get the correct MSI:" "INFO"
    Write-Log "1. Go to: https://app.activtrak.com" "INFO"
    Write-Log "2. Navigate to: Settings > Agents > Download Agent" "INFO"
    Write-Log "3. Select: 'MSI for mass deployment'" "INFO"
    Write-Log "4. Download the MSI (filename will be ATAcct680398_XXXXXX.msi)" "INFO"
    Write-Log "5. DO NOT rename the file!" "WARNING"
    Write-Log "6. Upload to GitHub releases or use local path" "INFO"
    Write-Log "=========================================" "WARNING"
    Write-Log ""

    # Check if using local file or download
    if (Test-Path variable:localMsiPath) {
        Write-Log "Using local MSI file: $localMsiPath" "INFO"
        if (-not (Test-Path $localMsiPath)) {
            throw "Local MSI file not found: $localMsiPath"
        }
        $installerPath = $localMsiPath
    } else {
        # Download the installer
        Write-Log "Downloading ActivTrak installer..." "INFO"
        Write-Log "URL: $downloadUrl"

        if ($downloadUrl -like "*{TOKEN}*") {
            Write-Log "ERROR: Download URL still contains placeholder {TOKEN}" "ERROR"
            Write-Log "You must replace {TOKEN} with your actual security token from the MSI filename" "ERROR"
            throw "Download URL not configured correctly"
        }

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec $downloadTimeoutSeconds
            Write-Log "Download completed" "SUCCESS"
        } catch {
            throw "Download failed: $($_.Exception.Message)"
        }
    }

    # Verify download
    if (-not (Test-Path $installerPath)) {
        throw "Installer file not found: $installerPath"
    }

    $fileSize = (Get-Item $installerPath).Length
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Log "MSI File: $fileSizeMB MB" "SUCCESS"

    # CRITICAL: Check filename format
    $filename = [System.IO.Path]::GetFileName($installerPath)
    Write-Log "MSI Filename: $filename" "INFO"

    # Check filename format - must match ActivTrak's expected format
    # Valid patterns:
    # - ATAcct######_{token}.msi (required format with account credentials)
    # - ATAcct######(version)_{token}_{timestamp}.msi (full original format)
    if ($filename -notmatch "ATAcct\d+[._\(].*\.msi") {
        Write-Log "=========================================" "ERROR"
        Write-Log "ERROR: INCORRECT MSI FILENAME FORMAT!" "ERROR"
        Write-Log "=========================================" "ERROR"
        Write-Log "Current filename: $filename" "ERROR"
        Write-Log "Required format: ATAcct######_{token}.msi or ATAcct######(version)_{token}_{timestamp}.msi" "ERROR"
        Write-Log ""
        Write-Log "The MSI filename MUST match ActivTrak's format with embedded account credentials." "ERROR"
        Write-Log "This script saves the downloaded MSI with the correct format automatically." "ERROR"
        Write-Log "=========================================" "ERROR"
        throw "Invalid MSI filename format - installation will fail"
    }

    Write-Log "Filename format is correct!" "SUCCESS"
    Write-Log ""

    # Calculate hash
    try {
        $fileHash = Get-FileHash -Path $installerPath -Algorithm SHA256
        Write-Log "SHA256: $($fileHash.Hash)"
    } catch {
        Write-Log "Could not calculate hash" "WARNING"
    }

    # Remove existing installations
    Write-Log "Checking for existing ActivTrak installation..."
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $existingApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*ActivTrak*" }

    if ($existingApps) {
        Write-Log "Found existing installation, removing..." "WARNING"
        foreach ($app in $existingApps) {
            Write-Log "Uninstalling: $($app.DisplayName)"
            if ($app.UninstallString -match "msiexec") {
                $productCode = $app.UninstallString -replace ".*(\{[A-F0-9-]+\}).*", '$1'
                $uninstallProc = Start-Process "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -PassThru -NoNewWindow
                Write-Log "Uninstall exit code: $($uninstallProc.ExitCode)"
                Start-Sleep -Seconds 5
            }
        }
    } else {
        Write-Log "No existing installation found"
    }

    # Stop services and processes
    Write-Log "Stopping ActivTrak services and processes..."
    Get-Service | Where-Object { $_.Name -like "*ActivTrak*" } | ForEach-Object {
        Write-Log "Stopping service: $($_.Name)"
        Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
    }

    Get-Process | Where-Object { $_.ProcessName -like "*ActivTrak*" } | ForEach-Object {
        Write-Log "Stopping process: $($_.ProcessName)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 3

    # INSTALLATION - SIMPLIFIED PER OFFICIAL DOCS
    Write-Log ""
    Write-Log "=========================================" "INFO"
    Write-Log "Starting Silent Installation" "INFO"
    Write-Log "=========================================" "INFO"
    Write-Log "Using official ActivTrak silent install method" "INFO"
    Write-Log "No account properties needed - embedded in MSI filename" "INFO"
    Write-Log ""

    # Official ActivTrak silent installation command
    # Per documentation: MSIEXEC /i ATAcctXXXXXX_{token}.msi -Quiet /l*v %TEMP%\atinstall.log
    $installArgs = "/i `"$installerPath`" /qn /norestart /l*v `"$msiLogPath`""
    Write-Log "Command: msiexec.exe $installArgs"

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
    Write-Log "Exit code: $exitCode"

    if ($exitCode -eq 0) {
        Write-Log "Installation completed successfully!" "SUCCESS"
    } elseif ($exitCode -eq 3010) {
        Write-Log "Installation completed successfully (reboot required)" "SUCCESS"
    } else {
        Write-Log "=========================================" "ERROR"
        Write-Log "INSTALLATION FAILED - Exit Code: $exitCode" "ERROR"
        Write-Log "=========================================" "ERROR"

        if (Test-Path $msiLogPath) {
            Write-Log "Checking MSI log for errors..." "ERROR"
            $logContent = Get-Content $msiLogPath
            $errors = $logContent | Select-String -Pattern "error|failed|return value 3" | Select-Object -First 10
            if ($errors) {
                Write-Log "Recent errors from MSI log:" "ERROR"
                $errors | ForEach-Object { Write-Log $_.Line "ERROR" }
            }
            Write-Log "" "ERROR"
            Write-Log "Full MSI log: $msiLogPath" "ERROR"
        }

        throw "Installation failed with exit code $exitCode"
    }

    # Verify installation
    Write-Log ""
    Write-Log "=========================================" "INFO"
    Write-Log "Verifying installation..." "INFO"
    Write-Log "=========================================" "INFO"
    Start-Sleep -Seconds 5

    $verifyApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                  Where-Object { $_.DisplayName -like "*ActivTrak*" }

    if ($verifyApps) {
        foreach ($app in $verifyApps) {
            Write-Log "Installed: $($app.DisplayName) v$($app.DisplayVersion)" "SUCCESS"
        }
    } else {
        Write-Log "WARNING: Could not verify installation in registry" "WARNING"
    }

    # Check service
    $service = Get-Service | Where-Object { $_.DisplayName -like "*ActivTrak*" } | Select-Object -First 1
    if ($service) {
        Write-Log "Service: $($service.Name) - Status: $($service.Status)" "SUCCESS"

        if ($service.Status -ne 'Running') {
            Write-Log "Starting ActivTrak service..."
            Start-Service -Name $service.Name -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $service.Refresh()
            Write-Log "Service status: $($service.Status)"
        }
    } else {
        Write-Log "WARNING: ActivTrak service not found" "WARNING"
    }

    # Cleanup
    if ($installerPath -like "$env:TEMP\*") {
        Write-Log "Cleaning up temporary installer file..."
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }

    Write-Log ""
    Write-Log "=========================================" "SUCCESS"
    Write-Log "INSTALLATION COMPLETED SUCCESSFULLY" "SUCCESS"
    Write-Log "=========================================" "SUCCESS"
    Write-Log "Log file: $logPath"
    Write-Log "=========================================" "SUCCESS"

    exit 0

} catch {
    Write-Log "=========================================" "ERROR"
    Write-Log "INSTALLATION FAILED" "ERROR"
    Write-Log "=========================================" "ERROR"
    Write-Log "ERROR: $($_.Exception.Message)" "ERROR"
    Write-Log "Type: $($_.Exception.GetType().FullName)" "ERROR"

    if ($_.ScriptStackTrace) {
        Write-Log "Stack: $($_.ScriptStackTrace)" "ERROR"
    }

    Write-Log "=========================================" "ERROR"
    Write-Log "Logs saved:" "ERROR"
    Write-Log "  Install log: $logPath" "ERROR"
    if (Test-Path $msiLogPath) {
        Write-Log "  MSI log: $msiLogPath" "ERROR"
    }
    Write-Log "=========================================" "ERROR"

    # Cleanup
    if ($installerPath -like "$env:TEMP\*") {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }

    exit 1
}
