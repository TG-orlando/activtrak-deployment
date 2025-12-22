# ActivTrak Installation Script for Rippling MDM
# This script downloads and installs ActivTrak

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
        # Save the entire script to a temp file for elevation
        $scriptContent = @'
# PASTE THE ENTIRE SCRIPT CONTENT HERE WHEN DEPLOYING VIA RIPPLING
'@
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

# Configuration
# Permanent download URL hosted on GitHub Releases
# This URL will not expire and always points to the latest version
$downloadUrl = "https://github.com/TG-orlando/activtrak-deployment/releases/download/v1.0.0/ActivTrak.msi"

# To update to a new version:
# 1. Download the new MSI from ActivTrak
# 2. Create a new release in the GitHub repository
# 3. Upload the new MSI to the release
# 4. Update the version in the URL above

$originalFilename = "ActivTrak.msi"
$installerPath = "$env:TEMP\$originalFilename"
$logPath = "$env:TEMP\ActivTrak_Install.log"
$downloadTimeoutSeconds = 600  # 10 minute timeout for download

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

    try {
        Write-Log "Attempting download with WebClient (with timeout)..."

        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell/ActivTrak-Installer")

        # Register async download with timeout
        $uri = New-Object System.Uri($Url)
        $downloadTask = $webClient.DownloadFileTaskAsync($uri, $OutputPath)

        # Wait for download with timeout
        if ($downloadTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            if ($downloadTask.Exception) {
                throw $downloadTask.Exception.InnerException
            }
            Write-Log "Download completed successfully with WebClient"
            return $true
        } else {
            $webClient.CancelAsync()
            throw "Download timed out after $TimeoutSeconds seconds"
        }
    } catch {
        Write-Log "WebClient download failed: $($_.Exception.Message)"
        Write-Log "Attempting fallback download with Invoke-WebRequest..."

        try {
            # Fallback to Invoke-WebRequest with timeout
            $ProgressPreference = 'SilentlyContinue'  # Faster downloads
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -TimeoutSec $TimeoutSeconds
            Write-Log "Download completed successfully with Invoke-WebRequest"
            return $true
        } catch {
            Write-Log "Invoke-WebRequest download failed: $($_.Exception.Message)"

            # Check if it's an authentication error (expired URL)
            if ($_.Exception.Message -match "403|Forbidden|SignatureDoesNotMatch|expired") {
                throw "Download URL has expired or is invalid. Please generate a fresh download URL from ActivTrak and update the script."
            }

            throw "All download methods failed: $($_.Exception.Message)"
        }
    } finally {
        if ($webClient) {
            $webClient.Dispose()
        }
    }
}

try {
    Write-Log "Starting ActivTrak installation process"
    Write-Log "Script version: 2.0 (Production - GitHub Hosted)"

    # Download the installer
    Write-Log "Downloading ActivTrak installer from GitHub..."
    Write-Log "Download URL: $downloadUrl"
    Write-Log "Timeout set to: $downloadTimeoutSeconds seconds"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Download-FileWithTimeout -Url $downloadUrl -OutputPath $installerPath -TimeoutSeconds $downloadTimeoutSeconds

    # Verify the file exists
    if (-not (Test-Path $installerPath)) {
        throw "Installer file not found at $installerPath after download"
    }

    $fileSize = (Get-Item $installerPath).Length
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Log "Installer downloaded successfully: $fileSizeMB MB"

    # Validate file size (typical ActivTrak MSI is 5-50 MB)
    if ($fileSize -lt 1MB) {
        Write-Log "WARNING: Downloaded file is suspiciously small ($fileSizeMB MB)"
        Write-Log "This might indicate a download error or expired URL"
    }

    # Get file hash for validation and logging
    try {
        $fileHash = Get-FileHash -Path $installerPath -Algorithm SHA256
        Write-Log "File SHA256: $($fileHash.Hash)"
    } catch {
        Write-Log "WARNING: Could not calculate file hash: $($_.Exception.Message)"
    }

    # Verify it's a valid MSI file
    Write-Log "Validating MSI file integrity..."
    try {
        # Check file signature (first bytes should be MSI header)
        $fileBytes = [System.IO.File]::ReadAllBytes($installerPath)
        if ($fileBytes.Length -gt 8) {
            # MSI files start with D0CF11E0A1B11AE1 (OLE Compound Document)
            $header = [System.BitConverter]::ToString($fileBytes[0..7]) -replace '-', ''
            if ($header -eq 'D0CF11E0A1B11AE1') {
                Write-Log "MSI file header validation: PASSED"
            } else {
                Write-Log "WARNING: File header does not match MSI format. Header: $header"
                Write-Log "Expected: D0CF11E0A1B11AE1"

                # Check if it's an HTML error page
                $fileStart = [System.Text.Encoding]::ASCII.GetString($fileBytes[0..[Math]::Min(1000, $fileBytes.Length-1)])
                if ($fileStart -match '<html|<!DOCTYPE|<\?xml') {
                    throw "Downloaded file is HTML/XML, not an MSI. The download URL has likely expired or returned an error page."
                }
            }
        }

        # Try to open with Windows Installer COM object
        $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
        $msiDatabase = $windowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $windowsInstaller, @($installerPath, 0))

        # Try to read product name from MSI
        try {
            $view = $msiDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $msiDatabase, ("SELECT Value FROM Property WHERE Property='ProductName'"))
            $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
            $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)

            if ($record) {
                $productName = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
                Write-Log "MSI Product Name: $productName"

                if ($productName -notmatch "ActivTrak") {
                    Write-Log "WARNING: MSI product name does not contain 'ActivTrak'. Verify this is the correct installer."
                }
            }

            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($view) | Out-Null
            if ($record) {
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($record) | Out-Null
            }
        } catch {
            Write-Log "Could not read product name from MSI: $($_.Exception.Message)"
        }

        Write-Log "MSI file validation: PASSED"

        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($msiDatabase) | Out-Null
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($windowsInstaller) | Out-Null
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "ERROR: MSI file validation FAILED: $errorMessage"

        # Provide helpful error messages
        if ($errorMessage -match "database|corrupt|invalid") {
            throw "The downloaded MSI file is corrupted or invalid. The download URL may have expired. Please generate a fresh URL from ActivTrak."
        } else {
            throw "MSI validation failed: $errorMessage"
        }
    }

    # Check if ActivTrak is already installed
    Write-Log "Checking for existing ActivTrak installation..."

    # Check registry for ActivTrak
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $activTrakApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "*ActivTrak*" }

    if ($activTrakApps) {
        Write-Log "Found existing ActivTrak installation(s). Attempting to remove..."
        foreach ($app in $activTrakApps) {
            Write-Log "Uninstalling: $($app.DisplayName) (Version: $($app.DisplayVersion))"
            if ($app.UninstallString) {
                $uninstallString = $app.UninstallString
                if ($uninstallString -match "msiexec") {
                    $productCode = $uninstallString -replace ".*(\{[A-F0-9-]+\}).*", '$1'
                    Write-Log "Running: msiexec.exe /x $productCode /qn /norestart"

                    $uninstallProcess = Start-Process "msiexec.exe" -ArgumentList "/x $productCode /qn /norestart" -Wait -PassThru -NoNewWindow

                    if ($uninstallProcess.ExitCode -eq 0 -or $uninstallProcess.ExitCode -eq 3010) {
                        Write-Log "Uninstallation successful"
                    } else {
                        Write-Log "WARNING: Uninstallation returned exit code: $($uninstallProcess.ExitCode)"
                    }

                    Start-Sleep -Seconds 5
                }
            }
        }
    } else {
        Write-Log "No existing ActivTrak installation found"
    }

    # Stop any ActivTrak services
    Write-Log "Checking for ActivTrak services..."
    $services = Get-Service | Where-Object { $_.Name -like "*ActivTrak*" -or $_.DisplayName -like "*ActivTrak*" }
    if ($services) {
        foreach ($service in $services) {
            Write-Log "Stopping service: $($service.Name) (Status: $($service.Status))"
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            }
        }
    } else {
        Write-Log "No ActivTrak services found"
    }

    # Stop any ActivTrak processes
    Write-Log "Checking for ActivTrak processes..."
    $processes = Get-Process | Where-Object { $_.ProcessName -like "*ActivTrak*" }
    if ($processes) {
        foreach ($proc in $processes) {
            Write-Log "Stopping process: $($proc.ProcessName) (PID: $($proc.Id))"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    } else {
        Write-Log "No ActivTrak processes found"
    }

    # Install ActivTrak
    Write-Log "Installing ActivTrak..."
    $msiLogPath = "$env:TEMP\ActivTrak_MSI_Install.log"

    # Use Start-Process with proper MSI arguments
    $installArguments = @(
        "/i",
        "`"$installerPath`"",
        "/qn",
        "/norestart",
        "/l*v",
        "`"$msiLogPath`""
    )

    $installArgumentString = $installArguments -join " "
    Write-Log "Running: msiexec.exe $installArgumentString"

    try {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgumentString -Wait -PassThru -NoNewWindow
    } catch {
        Write-Log "Installation process error: $($_.Exception.Message)"
        throw
    }

    Write-Log "Installation process completed with exit code: $($process.ExitCode)"

    # Analyze MSI log for errors or warnings
    if (Test-Path $msiLogPath) {
        Write-Log "Analyzing MSI installation log..."

        $logContent = Get-Content $msiLogPath -ErrorAction SilentlyContinue
        if ($logContent) {
            # Check for common success indicators
            $successIndicators = $logContent | Select-String -Pattern "Installation success or error status: 0|Installation completed successfully"
            if ($successIndicators) {
                Write-Log "MSI log indicates successful installation"
            }

            # Check for errors
            $errorLines = $logContent | Select-String -Pattern "Installation success or error status: [^0]|return value 3|ERROR:" -Context 0,2
            if ($errorLines -and $process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
                Write-Log "Found potential errors in MSI log:"
                $errorLines | Select-Object -First 10 | ForEach-Object { Write-Log "  $($_.Line)" }
            }
        }
    }

    # Check exit code and provide detailed feedback
    if ($process.ExitCode -eq 0) {
        Write-Log "ActivTrak installed successfully (Exit Code: 0)"
    } elseif ($process.ExitCode -eq 3010) {
        Write-Log "ActivTrak installed successfully - Reboot required (Exit Code: 3010)"
    } elseif ($process.ExitCode -eq 1603) {
        Write-Log "ERROR: Installation failed - Fatal error during installation (Exit Code: 1603)"
        if (Test-Path $msiLogPath) {
            Write-Log "Last 50 lines of MSI log:"
            Get-Content $msiLogPath -Tail 50 | ForEach-Object { Write-Log "  $_" }
        }
        throw "Installation failed with exit code 1603. Check the MSI log at: $msiLogPath"
    } elseif ($process.ExitCode -eq 1618) {
        throw "Installation failed - Another installation is already in progress (Exit Code: 1618)"
    } elseif ($process.ExitCode -eq 1619) {
        throw "Installation failed - Installation package could not be opened (Exit Code: 1619)"
    } elseif ($process.ExitCode -eq 1620) {
        throw "Installation failed - Installation package could not be opened. Verify the package exists and is accessible (Exit Code: 1620)"
    } elseif ($process.ExitCode -eq 1625) {
        throw "Installation failed - Installation forbidden by system policy (Exit Code: 1625)"
    } else {
        Write-Log "WARNING: Installation completed with unexpected exit code: $($process.ExitCode)"
        if (Test-Path $msiLogPath) {
            Write-Log "Last 50 lines of MSI log:"
            Get-Content $msiLogPath -Tail 50 | ForEach-Object { Write-Log "  $_" }
        }
        throw "Installation failed with exit code: $($process.ExitCode). Check the MSI log at: $msiLogPath"
    }

    # Verify installation succeeded
    Write-Log "Verifying installation..."
    Start-Sleep -Seconds 5

    $verifyApps = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                  Where-Object { $_.DisplayName -like "*ActivTrak*" }

    if ($verifyApps) {
        Write-Log "Installation verified successfully:"
        foreach ($app in $verifyApps) {
            Write-Log "  - $($app.DisplayName) version $($app.DisplayVersion)"
        }
    } else {
        Write-Log "WARNING: Could not verify ActivTrak installation in registry"
    }

    # Check if service is running
    $verifyService = Get-Service | Where-Object { $_.DisplayName -like "*ActivTrak*" } | Select-Object -First 1
    if ($verifyService) {
        Write-Log "ActivTrak service found: $($verifyService.Name) (Status: $($verifyService.Status))"
        if ($verifyService.Status -ne 'Running') {
            Write-Log "Note: Service is not running yet, this may be normal on first installation"
        }
    }

    # Clean up installer
    Write-Log "Cleaning up installer file..."
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    Write-Log "========================================="
    Write-Log "ActivTrak installation completed successfully"
    Write-Log "Installation log: $logPath"
    Write-Log "MSI log: $msiLogPath"
    Write-Log "========================================="

    exit 0

} catch {
    Write-Log "========================================="
    Write-Log "INSTALLATION FAILED"
    Write-Log "========================================="
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log "Error Details: $($_.Exception.GetType().FullName)"
    if ($_.ScriptStackTrace) {
        Write-Log "Stack Trace: $($_.ScriptStackTrace)"
    }
    Write-Log "========================================="
    Write-Log "Installation log saved to: $logPath"
    if (Test-Path "$env:TEMP\ActivTrak_MSI_Install.log") {
        Write-Log "MSI log saved to: $env:TEMP\ActivTrak_MSI_Install.log"
    }
    Write-Log "========================================="

    # Clean up partial installation
    Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue

    exit 1
}
