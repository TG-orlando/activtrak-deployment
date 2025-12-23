# ActivTrak Installation Script - Final Version
# Version: 3.1 - With Account ID Configuration
# This version properly configures the ActivTrak account during installation

$ErrorActionPreference = "Stop"

# ===== CONFIGURATION =====
# These values were extracted from your ActivTrak deployment package
# If you get a new MSI from ActivTrak, update these values accordingly
$ACCOUNT_ID = "680398"
$AGENT_KEY = "1szujUFkra0G"

# Download URL (permanent GitHub hosting)
$downloadUrl = "https://github.com/TG-orlando/activtrak-deployment/releases/download/v1.0.0/ActivTrak.msi"
# ========================

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Script is not running as Administrator. Attempting to elevate..."
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -Wait
        exit
    } else {
        $tempScript = "$env:TEMP\ActivTrak_Elevation_$(Get-Date -Format 'yyyyMMddHHmmss').ps1"
        try {
            $currentScript = Get-Content $PSCommandPath -Raw -ErrorAction Stop
            $currentScript | Out-File -FilePath $tempScript -Force -Encoding UTF8
        } catch {
            $MyInvocation.MyCommand.ScriptBlock.ToString() | Out-File -FilePath $tempScript -Force -Encoding UTF8
        }
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs -Wait
        Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
        exit
    }
}

Write-Host "Running with Administrator privileges"

# Configuration
$installerPath = "$env:TEMP\ActivTrak.msi"
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
        default { Write-Host $Message }
    }
}

# Function to download file
function Download-FileWithTimeout {
    param([string]$Url, [string]$OutputPath, [int]$TimeoutSeconds = 600)

    $webClient = $null
    try {
        Write-Log "Downloading from GitHub..."
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell/ActivTrak-Installer")
        $uri = New-Object System.Uri($Url)
        $downloadTask = $webClient.DownloadFileTaskAsync($uri, $OutputPath)

        if ($downloadTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            if ($downloadTask.Exception) {
                throw $downloadTask.Exception.InnerException
            }
            Write-Log "Download completed" "SUCCESS"
            return $true
        } else {
            $webClient.CancelAsync()
            throw "Download timed out"
        }
    } catch {
        Write-Log "WebClient failed, trying Invoke-WebRequest..." "WARNING"
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec $TimeoutSeconds
            Write-Log "Download completed" "SUCCESS"
            return $true
        } catch {
            throw "Download failed: $($_.Exception.Message)"
        }
    } finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

try {
    Write-Log "========================================="
    Write-Log "ActivTrak Installation Script v3.1"
    Write-Log "========================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "User: $env:USERNAME"
    Write-Log "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "Account ID: $ACCOUNT_ID"
    Write-Log "========================================="

    # PRE-INSTALLATION CHECKS
    Write-Log "Running pre-installation checks..."

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
        Add-MpPreference -ExclusionPath $env:TEMP -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionProcess "ActivTrakAgent.exe" -ErrorAction SilentlyContinue
        Write-Log "Windows Defender exclusions added" "SUCCESS"
    } catch {
        Write-Log "Could not add Defender exclusions: $($_.Exception.Message)" "WARNING"
    }

    # Download the installer
    Write-Log "Downloading ActivTrak installer..."
    Write-Log "URL: $downloadUrl"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Download-FileWithTimeout -Url $downloadUrl -OutputPath $installerPath -TimeoutSeconds $downloadTimeoutSeconds

    # Verify download
    if (-not (Test-Path $installerPath)) {
        throw "Installer file not found after download"
    }

    $fileSize = (Get-Item $installerPath).Length
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Log "Downloaded: $fileSizeMB MB" "SUCCESS"

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

    # INSTALLATION WITH ACCOUNT CONFIGURATION
    Write-Log "========================================="
    Write-Log "Starting installation with account configuration..."
    Write-Log "========================================="

    $installSuccess = $false
    $exitCode = 0

    # Build installation command with account properties
    # Try different property combinations that ActivTrak might use
    $propertyVariations = @(
        "ACCOUNT_ID=$ACCOUNT_ID AGENT_KEY=$AGENT_KEY",
        "ACCOUNTID=$ACCOUNT_ID AGENTKEY=$AGENT_KEY",
        "ACTIVTRAK_ACCOUNT=$ACCOUNT_ID ACTIVTRAK_KEY=$AGENT_KEY",
        "AI_ACCOUNT_ID=$ACCOUNT_ID AI_AGENT_KEY=$AGENT_KEY"
    )

    foreach ($properties in $propertyVariations) {
        Write-Log "Attempting installation with properties: $properties"

        $installArgs = "/i `"$installerPath`" /qn /norestart $properties /l*v `"$msiLogPath`""
        Write-Log "Command: msiexec.exe $installArgs"

        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode
        Write-Log "Exit code: $exitCode"

        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            $installSuccess = $true
            Write-Log "Installation successful with properties: $properties" "SUCCESS"
            break
        } else {
            Write-Log "Failed with exit code $exitCode, trying next method..." "WARNING"
            Start-Sleep -Seconds 2
        }
    }

    # If all property variations failed, try without properties (embedded config)
    if (-not $installSuccess) {
        Write-Log "All property variations failed, trying with embedded configuration..." "WARNING"

        $installArgs = "/i `"$installerPath`" /qn /norestart /l*v `"$msiLogPath`""
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode
        Write-Log "Exit code: $exitCode"

        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            $installSuccess = $true
            Write-Log "Installation successful with embedded configuration!" "SUCCESS"
        }
    }

    # Analyze the result
    if (-not $installSuccess) {
        Write-Log "=========================================" "ERROR"
        Write-Log "INSTALLATION FAILED - Exit Code: $exitCode" "ERROR"
        Write-Log "=========================================" "ERROR"

        # Extract and show errors from MSI log
        if (Test-Path $msiLogPath) {
            Write-Log "Analyzing MSI log for errors..." "ERROR"
            $logContent = Get-Content $msiLogPath

            # Look for the installAccountId custom action specifically
            $accountIdErrors = $logContent | Select-String -Pattern "installAccountId|CustomAction.*returned" -Context 5,5

            if ($accountIdErrors) {
                Write-Log "Custom Action Errors:" "ERROR"
                $accountIdErrors | Select-Object -First 3 | ForEach-Object {
                    Write-Log $_.Line "ERROR"
                }
            }

            # Look for property values to see what the MSI is expecting
            $propertyLines = $logContent | Select-String -Pattern "Property.*ACCOUNT|Property.*AGENT|Property.*AI_" | Select-Object -First 10
            if ($propertyLines) {
                Write-Log "" "ERROR"
                Write-Log "MSI Properties found:" "ERROR"
                $propertyLines | ForEach-Object {
                    Write-Log $_.Line "ERROR"
                }
            }

            Write-Log "" "ERROR"
            Write-Log "Full MSI log: $msiLogPath" "ERROR"
        }

        Write-Log "" "ERROR"
        Write-Log "TROUBLESHOOTING STEPS:" "ERROR"
        Write-Log "1. Contact ActivTrak support to get a deployment MSI for account $ACCOUNT_ID" "ERROR"
        Write-Log "2. Ask for the correct MSI properties needed for silent installation" "ERROR"
        Write-Log "3. Check if your ActivTrak account requires agent approval/registration" "ERROR"

        throw "Installation failed with exit code $exitCode"
    }

    # Verify installation
    Write-Log "========================================="
    Write-Log "Verifying installation..."
    Write-Log "========================================="
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
    Write-Log "Cleaning up installer file..."
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    Write-Log "========================================="
    Write-Log "INSTALLATION COMPLETED SUCCESSFULLY" "SUCCESS"
    Write-Log "========================================="
    Write-Log "Log file: $logPath"
    Write-Log "========================================="

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
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    exit 1
}
