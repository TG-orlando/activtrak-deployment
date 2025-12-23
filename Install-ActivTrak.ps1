# ActivTrak Installation Script - Robust Version
# Version: 3.0 - Enhanced for remote deployment via Rippling MDM
# Handles common 1603 errors and provides detailed diagnostics

$ErrorActionPreference = "Stop"

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
$downloadUrl = "https://github.com/TG-orlando/activtrak-deployment/releases/download/v1.0.0/ActivTrak.msi"
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
            Write-Log "Download completed with Invoke-WebRequest" "SUCCESS"
            return $true
        } catch {
            throw "All download methods failed: $($_.Exception.Message)"
        }
    } finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

try {
    Write-Log "========================================="
    Write-Log "ActivTrak Installation Script v3.0 (Robust)"
    Write-Log "========================================="
    Write-Log "Computer: $env:COMPUTERNAME"
    Write-Log "User: $env:USERNAME"
    Write-Log "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
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

    # Add Windows Defender exclusions (helps prevent 1603 errors)
    Write-Log "Adding Windows Defender exclusions..."
    try {
        Add-MpPreference -ExclusionPath "C:\Program Files\ActivTrak" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath "C:\Program Files (x86)\ActivTrak" -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath $env:TEMP -ErrorAction SilentlyContinue
        Write-Log "Windows Defender exclusions added" "SUCCESS"
    } catch {
        Write-Log "Could not add Defender exclusions (not critical): $($_.Exception.Message)" "WARNING"
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

    if ($fileSize -lt 1MB) {
        throw "Downloaded file is too small ($fileSizeMB MB)"
    }

    # Calculate hash
    try {
        $fileHash = Get-FileHash -Path $installerPath -Algorithm SHA256
        Write-Log "SHA256: $($fileHash.Hash)"
    } catch {
        Write-Log "Could not calculate hash" "WARNING"
    }

    # Validate MSI
    Write-Log "Validating MSI file..."
    $fileBytes = [System.IO.File]::ReadAllBytes($installerPath)
    if ($fileBytes.Length -gt 8) {
        $header = [System.BitConverter]::ToString($fileBytes[0..7]) -replace '-', ''
        if ($header -eq 'D0CF11E0A1B11AE1') {
            Write-Log "MSI validation: PASSED" "SUCCESS"
        } else {
            throw "File is not a valid MSI (header: $header)"
        }
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

    # INSTALLATION - Try multiple methods
    Write-Log "========================================="
    Write-Log "Starting installation..."
    Write-Log "========================================="

    $installSuccess = $false
    $exitCode = 0

    # METHOD 1: Standard quiet installation
    Write-Log "Attempt 1: Standard installation with full logging..."
    $installArgs = "/i `"$installerPath`" /qn /norestart /l*v `"$msiLogPath`""
    Write-Log "Command: msiexec.exe $installArgs"

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
    Write-Log "Exit code: $exitCode"

    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        $installSuccess = $true
        Write-Log "Installation successful!" "SUCCESS"
    } else {
        Write-Log "Method 1 failed with exit code $exitCode" "WARNING"

        # METHOD 2: Try with basic UI (shows progress, might help with some errors)
        Write-Log "Attempt 2: Installation with basic UI..."
        $installArgs2 = "/i `"$installerPath`" /qb /norestart /l*v `"$msiLogPath`""

        $process2 = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs2 -Wait -PassThru -NoNewWindow
        $exitCode = $process2.ExitCode
        Write-Log "Exit code: $exitCode"

        if ($exitCode -eq 0 -or $exitCode -eq 3010) {
            $installSuccess = $true
            Write-Log "Installation successful with method 2!" "SUCCESS"
        } else {
            Write-Log "Method 2 also failed" "WARNING"
        }
    }

    # Analyze the result
    if (-not $installSuccess) {
        Write-Log "=========================================" "ERROR"
        Write-Log "INSTALLATION FAILED - Exit Code: $exitCode" "ERROR"
        Write-Log "=========================================" "ERROR"

        # Provide specific guidance based on exit code
        switch ($exitCode) {
            1603 {
                Write-Log "Error 1603 - Fatal installation error" "ERROR"
                Write-Log "Common causes:" "ERROR"
                Write-Log "  - Antivirus blocking the installation" "ERROR"
                Write-Log "  - Insufficient permissions" "ERROR"
                Write-Log "  - Corrupted Windows Installer" "ERROR"
                Write-Log "  - Missing prerequisites (.NET Framework)" "ERROR"
            }
            1618 { Write-Log "Error 1618 - Another installation is in progress" "ERROR" }
            1619 { Write-Log "Error 1619 - Installation package could not be opened" "ERROR" }
            1625 { Write-Log "Error 1625 - Installation forbidden by system policy" "ERROR" }
            1638 { Write-Log "Error 1638 - Another version already installed" "ERROR" }
            default { Write-Log "Error ${exitCode} - Unknown installation error" "ERROR" }
        }

        # Extract key errors from MSI log
        if (Test-Path $msiLogPath) {
            Write-Log "Analyzing MSI log for errors..."
            $logContent = Get-Content $msiLogPath

            $criticalErrors = $logContent | Select-String -Pattern "return value 3|error.*failed|CustomAction.*returned [^0]" -CaseSensitive:$false | Select-Object -First 5

            if ($criticalErrors) {
                Write-Log "Key errors from MSI log:" "ERROR"
                $criticalErrors | ForEach-Object {
                    Write-Log "  $($_.Line)" "ERROR"
                }
            }

            Write-Log "Full MSI log saved to: $msiLogPath" "ERROR"
        }

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

        # Try to start the service if it's not running
        if ($service.Status -ne 'Running') {
            Write-Log "Starting ActivTrak service..."
            Start-Service -Name $service.Name -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $service.Refresh()
            Write-Log "Service status after start attempt: $($service.Status)"
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
    Write-Log "MSI log: $msiLogPath"
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
    Write-Log "Log saved to: $logPath" "ERROR"
    if (Test-Path $msiLogPath) {
        Write-Log "MSI log: $msiLogPath" "ERROR"
    }
    Write-Log "=========================================" "ERROR"

    # Cleanup
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    exit 1
}
