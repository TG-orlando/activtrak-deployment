# ActivTrak Installation Script for Rippling MDM
# Version: 2.0 - Production Ready
# This script downloads and installs ActivTrak from a permanent GitHub-hosted URL

$ErrorActionPreference = "Stop"

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Script is not running as Administrator. Attempting to elevate..."

    # Re-launch the script with elevated privileges
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs -Wait
        exit
    } else {
        # If running from Rippling, the script content is passed directly
        $tempScript = "$env:TEMP\ActivTrak_Elevation_$(Get-Date -Format 'yyyyMMddHHmmss').ps1"

        # Get current script content
        try {
            $currentScript = Get-Content $PSCommandPath -Raw -ErrorAction Stop
            $currentScript | Out-File -FilePath $tempScript -Force -Encoding UTF8
        } catch {
            # Fallback: use MyInvocation
            $MyInvocation.MyCommand.ScriptBlock.ToString() | Out-File -FilePath $tempScript -Force -Encoding UTF8
        }

        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs -Wait
        Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue
        exit
    }
}

Write-Host "Running with Administrator privileges"

# Configuration - Permanent GitHub-hosted URL
$downloadUrl = "https://github.com/TG-orlando/activtrak-deployment/releases/download/v1.0.0/ActivTrak.msi"
$installerPath = "$env:TEMP\ActivTrak.msi"
$logPath = "$env:TEMP\ActivTrak_Install.log"
$downloadTimeoutSeconds = 600

# Function to write log
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    $logMessage | Out-File -FilePath $logPath -Append
    Write-Host $Message
}

# Function to download file with timeout
function Download-FileWithTimeout {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$TimeoutSeconds = 600
    )

    $webClient = $null
    try {
        Write-Log "Attempting download with WebClient..."

        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell/ActivTrak-Installer")

        $uri = New-Object System.Uri($Url)
        $downloadTask = $webClient.DownloadFileTaskAsync($uri, $OutputPath)

        if ($downloadTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            if ($downloadTask.Exception) {
                throw $downloadTask.Exception.InnerException
            }
            Write-Log "Download completed successfully"
            return $true
        } else {
            $webClient.CancelAsync()
            throw "Download timed out after $TimeoutSeconds seconds"
        }
    } catch {
        Write-Log "WebClient download failed: $($_.Exception.Message)"
        Write-Log "Attempting fallback with Invoke-WebRequest..."

        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec $TimeoutSeconds
            Write-Log "Download completed successfully with Invoke-WebRequest"
            return $true
        } catch {
            Write-Log "All download methods failed: $($_.Exception.Message)"
            throw
        }
    } finally {
        if ($webClient) {
            $webClient.Dispose()
        }
    }
}

try {
    Write-Log "========================================="
    Write-Log "ActivTrak Installation Script v2.0"
    Write-Log "========================================="
    Write-Log "Starting installation process..."

    # Download the installer
    Write-Log "Downloading ActivTrak from GitHub..."
    Write-Log "URL: $downloadUrl"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Download-FileWithTimeout -Url $downloadUrl -OutputPath $installerPath -TimeoutSeconds $downloadTimeoutSeconds

    # Verify download
    if (-not (Test-Path $installerPath)) {
        throw "Installer file not found after download"
    }

    $fileSize = (Get-Item $installerPath).Length
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Log "Downloaded successfully: $fileSizeMB MB"

    if ($fileSize -lt 1MB) {
        throw "Downloaded file is too small ($fileSizeMB MB), likely corrupt"
    }

    # Get file hash
    try {
        $fileHash = Get-FileHash -Path $installerPath -Algorithm SHA256
        Write-Log "SHA256: $($fileHash.Hash)"
    } catch {
        Write-Log "WARNING: Could not calculate hash: $($_.Exception.Message)"
    }

    # Validate MSI header
    Write-Log "Validating MSI file..."
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($installerPath)
        if ($fileBytes.Length -gt 8) {
            $header = [System.BitConverter]::ToString($fileBytes[0..7]) -replace '-', ''
            if ($header -eq 'D0CF11E0A1B11AE1') {
                Write-Log "MSI validation: PASSED"
            } else {
                Write-Log "WARNING: File header does not match MSI format"
                $fileStart = [System.Text.Encoding]::ASCII.GetString($fileBytes[0..[Math]::Min(100, $fileBytes.Length-1)])
                if ($fileStart -match '<html|<!DOCTYPE') {
                    throw "Downloaded file is HTML, not an MSI"
                }
            }
        }
    } catch {
        Write-Log "WARNING: MSI validation error: $($_.Exception.Message)"
    }

    # Check for existing installation
    Write-Log "Checking for existing ActivTrak installation..."

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $existingApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*ActivTrak*" }

    if ($existingApps) {
        Write-Log "Found existing installation, removing..."
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

    # Stop services
    Write-Log "Stopping ActivTrak services..."
    $services = Get-Service | Where-Object { $_.Name -like "*ActivTrak*" -or $_.DisplayName -like "*ActivTrak*" }
    foreach ($service in $services) {
        Write-Log "Stopping service: $($service.Name)"
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
    }

    # Stop processes
    Write-Log "Stopping ActivTrak processes..."
    $processes = Get-Process | Where-Object { $_.ProcessName -like "*ActivTrak*" }
    foreach ($proc in $processes) {
        Write-Log "Stopping process: $($proc.ProcessName)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 3

    # Install
    Write-Log "Installing ActivTrak..."
    $msiLogPath = "$env:TEMP\ActivTrak_MSI_Install.log"

    $installArgs = "/i `"$installerPath`" /qn /norestart /l*v `"$msiLogPath`""
    Write-Log "Running: msiexec.exe $installArgs"

    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

    Write-Log "Installation exit code: $($process.ExitCode)"

    # Check result
    if ($process.ExitCode -eq 0) {
        Write-Log "Installation successful"
    } elseif ($process.ExitCode -eq 3010) {
        Write-Log "Installation successful (reboot required)"
    } elseif ($process.ExitCode -eq 1603) {
        Write-Log "ERROR: Fatal installation error (1603)"
        if (Test-Path $msiLogPath) {
            Write-Log "Last 30 lines of MSI log:"
            Get-Content $msiLogPath -Tail 30 | ForEach-Object { Write-Log "  $_" }
        }
        throw "Installation failed with error 1603"
    } elseif ($process.ExitCode -eq 1618) {
        throw "Another installation is in progress (1618)"
    } elseif ($process.ExitCode -eq 1619) {
        throw "Installation package could not be opened (1619)"
    } elseif ($process.ExitCode -eq 1625) {
        throw "Installation forbidden by system policy (1625)"
    } else {
        throw "Installation failed with exit code: $($process.ExitCode)"
    }

    # Verify installation
    Write-Log "Verifying installation..."
    Start-Sleep -Seconds 5

    $verifyApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*ActivTrak*" }

    if ($verifyApps) {
        foreach ($app in $verifyApps) {
            Write-Log "Installed: $($app.DisplayName) v$($app.DisplayVersion)"
        }
    } else {
        Write-Log "WARNING: Could not verify installation"
    }

    # Check service
    $service = Get-Service | Where-Object { $_.DisplayName -like "*ActivTrak*" } | Select-Object -First 1
    if ($service) {
        Write-Log "Service: $($service.Name) - Status: $($service.Status)"
    }

    # Cleanup
    Write-Log "Cleaning up..."
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    Write-Log "========================================="
    Write-Log "Installation completed successfully"
    Write-Log "Log file: $logPath"
    Write-Log "========================================="

    exit 0

} catch {
    Write-Log "========================================="
    Write-Log "INSTALLATION FAILED"
    Write-Log "========================================="
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Type: $($_.Exception.GetType().FullName)"

    if ($_.ScriptStackTrace) {
        Write-Log "Stack: $($_.ScriptStackTrace)"
    }

    Write-Log "========================================="
    Write-Log "Log saved to: $logPath"
    Write-Log "========================================="

    # Cleanup
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    exit 1
}
