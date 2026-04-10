# Setup Script: Install Python 3 64-bit, configure venv, and run setuparchive.py

$ErrorActionPreference = "Stop"

# --- Configuration ---
$PythonVersion    = "3.13.3"
$PythonUrl        = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
$PythonInstaller  = "$env:TEMP\python-amd64-installer.exe"
$PythonInstallDir = "C:\Python313"
$VenvDir          = ".\venv"
$DefaultGamePath  = "C:\Program Files\Meta Horizon\Software\Software\ready-at-dawn-echo-arena"
$DataSubPath      = "_data\5932408047"
$PatchedOutput    = ".\patched_output"
$LogFile          = ".\pewpew_prepare.log"

# ============================================================
# --- Logging helper ---
# ============================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS","STEP")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine   = "[$timestamp] [$Level] $Message"

    # Always write to log file
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8

    # Write to console with colour
    switch ($Level) {
        "STEP"    { Write-Host $logLine -ForegroundColor Cyan }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
        "WARN"    { Write-Host $logLine -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logLine -ForegroundColor Red }
        default   { Write-Host $logLine -ForegroundColor Gray }
    }
}

function Write-LogSeparator {
    $line = "----------------------------------------"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor DarkGray
}

# ============================================================
# Initialise log file
# ============================================================
$null = New-Item -Path $LogFile -ItemType File -Force
Write-Log "========================================" "INFO"
Write-Log "  Echo Arena - Archive Patcher Setup    " "INFO"
Write-Log "  Log file: $LogFile                    " "INFO"
Write-Log "========================================" "INFO"
Write-Log "Script started by: $env:USERNAME on $env:COMPUTERNAME" "INFO"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)" "INFO"

# ============================================================
# --- Step 0: Resolve game folder path ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 0: Resolving game folder path" "STEP"

$GameFolder = $null

if (Test-Path $DefaultGamePath) {
    Write-Log "Default game folder found: $DefaultGamePath" "SUCCESS"
    Write-Host ""
    $confirm = Read-Host "Is this the correct game folder? (Y/N)"
    Write-Log "User response to default path confirmation: '$confirm'" "INFO"
    if ($confirm -match "^[Yy]$") {
        $GameFolder = $DefaultGamePath
        Write-Log "User accepted default game folder." "INFO"
    } else {
        Write-Log "User rejected default game folder. Prompting for manual input." "INFO"
    }
} else {
    Write-Log "Default game folder not found at: $DefaultGamePath" "WARN"
}

if (-not $GameFolder) {
    Write-Host ""
    Write-Host "Please enter the full path to the 'ready-at-dawn-echo-arena' folder:" -ForegroundColor Cyan
    do {
        $inputPath = Read-Host "Path"
        $inputPath = $inputPath.Trim('"').Trim("'").Trim()
        Write-Log "User entered path: '$inputPath'" "INFO"
        if (-not (Test-Path $inputPath)) {
            Write-Log "Path not found: '$inputPath'. Asking again." "WARN"
            Write-Host "  Path not found. Please try again." -ForegroundColor Red
        }
    } while (-not (Test-Path $inputPath))
    $GameFolder = $inputPath
    Write-Log "Manual game folder accepted: $GameFolder" "SUCCESS"
}

$ArchivePath = Join-Path $GameFolder $DataSubPath
Write-Log "Archive path resolved to: $ArchivePath" "SUCCESS"

# ============================================================
# --- Step 0b: Ask about auto-copy of patched files ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 0b: Auto-copy preference" "STEP"

Write-Host ""
$copyAnswer = Read-Host "Automatically copy patched files into the game folder when done? (Y/N)"
$AutoCopy   = $copyAnswer -match "^[Yy]$"
Write-Log "User response to auto-copy prompt: '$copyAnswer'" "INFO"

if ($AutoCopy) {
    Write-Log "Auto-copy ENABLED. Patched files will be copied to: $ArchivePath" "SUCCESS"
} else {
    Write-Log "Auto-copy DISABLED. Patched files will not be copied automatically." "INFO"
}

# ============================================================
# --- Step 1: Check if Python is already installed & usable ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 1: Checking for existing Python 64-bit installation" "STEP"

$PythonExe = $null

$PythonOnPath = Get-Command python -ErrorAction SilentlyContinue

if ($PythonOnPath) {
    $detectedExe = $PythonOnPath.Source
    Write-Log "Python found on PATH: $detectedExe" "INFO"
    try {
        $arch = & $detectedExe -c "import struct; print(struct.calcsize('P') * 8)"
        $ver  = & $detectedExe --version 2>&1
        Write-Log "Detected Python: $ver | Architecture: ${arch}-bit" "INFO"
        if ($arch -eq "64") {
            Write-Log "Python on PATH is 64-bit and usable." "SUCCESS"
            $PythonExe = $detectedExe
        } else {
            Write-Log "Python on PATH is 32-bit. A 64-bit install is required." "WARN"
        }
    } catch {
        Write-Log "Python found on PATH but could not be queried: $_" "WARN"
    }
} else {
    Write-Log "Python not found on PATH." "INFO"
}

if (-not $PythonExe -and (Test-Path "$PythonInstallDir\python.exe")) {
    $detectedExe = "$PythonInstallDir\python.exe"
    Write-Log "Checking known install directory: $detectedExe" "INFO"
    try {
        $arch = & $detectedExe -c "import struct; print(struct.calcsize('P') * 8)"
        $ver  = & $detectedExe --version 2>&1
        Write-Log "Detected Python: $ver | Architecture: ${arch}-bit" "INFO"
        if ($arch -eq "64") {
            Write-Log "Python at install dir is 64-bit and usable." "SUCCESS"
            $PythonExe = $detectedExe
        }
    } catch {
        Write-Log "Python found at $detectedExe but could not be queried: $_" "WARN"
    }
}

# ============================================================
# --- Step 2: Install Python only if needed ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 2: Python installation" "STEP"

if ($PythonExe) {
    Write-Log "Skipping Python installation — already ready to use at: $PythonExe" "SUCCESS"
} else {
    Write-Log "Python 64-bit not found. Starting download of Python $PythonVersion..." "INFO"
    Write-Log "Download URL: $PythonUrl" "INFO"

    try {
        Invoke-WebRequest -Uri $PythonUrl -OutFile $PythonInstaller -UseBasicParsing
        Write-Log "Installer downloaded to: $PythonInstaller" "SUCCESS"
    } catch {
        Write-Log "Failed to download Python installer: $_" "ERROR"
        throw
    }

    Write-Log "Running Python installer silently to: $PythonInstallDir" "INFO"
    try {
        $proc = Start-Process -FilePath $PythonInstaller -ArgumentList @(
            "/quiet",
            "InstallAllUsers=1",
            "TargetDir=$PythonInstallDir",
            "PrependPath=0",
            "Include_launcher=1",
            "Include_pip=1",
            "Include_test=0"
        ) -Wait -NoNewWindow -PassThru
        Write-Log "Installer exited with code: $($proc.ExitCode)" "INFO"
        if ($proc.ExitCode -ne 0) {
            Write-Log "Installer returned non-zero exit code: $($proc.ExitCode)" "WARN"
        }
    } catch {
        Write-Log "Python installer failed: $_" "ERROR"
        throw
    }

    Remove-Item $PythonInstaller -Force
    Write-Log "Installer temp file removed." "INFO"

    $PythonExe = "$PythonInstallDir\python.exe"
    $ver = & $PythonExe --version 2>&1
    Write-Log "Python installed successfully: $ver" "SUCCESS"
}

# ============================================================
# --- Step 3: Ensure Python is on PATH (if not already) ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 3: Ensuring Python directories are on PATH" "STEP"

$PythonDir     = Split-Path $PythonExe -Parent
$PythonScripts = Join-Path $PythonDir "Scripts"

foreach ($p in @($PythonDir, $PythonScripts)) {
    $MachinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($MachinePath -notlike "*$p*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$MachinePath;$p", "Machine")
        Write-Log "Added to Machine PATH: $p" "INFO"
    } else {
        Write-Log "Already in Machine PATH: $p" "INFO"
    }
    if ($env:PATH -notlike "*$p*") {
        $env:PATH = "$env:PATH;$p"
        Write-Log "Added to session PATH: $p" "INFO"
    } else {
        Write-Log "Already in session PATH: $p" "INFO"
    }
}
Write-Log "PATH configuration complete." "SUCCESS"

# ============================================================
# --- Step 4: Create virtual environment ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 4: Creating virtual environment at '$VenvDir'" "STEP"

try {
    & $PythonExe -m venv $VenvDir
    Write-Log "Virtual environment created successfully at: $VenvDir" "SUCCESS"
} catch {
    Write-Log "Failed to create virtual environment: $_" "ERROR"
    throw
}

# ============================================================
# --- Step 5: Activate the virtual environment ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 5: Activating virtual environment" "STEP"

$ActivateScript = "$VenvDir\Scripts\Activate.ps1"
if (-not (Test-Path $ActivateScript)) {
    Write-Log "Activation script not found at: $ActivateScript" "ERROR"
    throw "Activation script not found at: $ActivateScript"
}

try {
    & $ActivateScript
    Write-Log "Virtual environment activated." "SUCCESS"
} catch {
    Write-Log "Failed to activate virtual environment: $_" "ERROR"
    throw
}

# ============================================================
# --- Step 6: Upgrade pip + install zstandard ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 6: Upgrading pip and installing dependencies" "STEP"

Write-Log "Upgrading pip..." "INFO"
try {
    & "$VenvDir\Scripts\python.exe" -m pip install --upgrade pip 2>&1 | ForEach-Object {
        Write-Log "  [pip] $_" "INFO"
    }
    Write-Log "pip upgraded successfully." "SUCCESS"
} catch {
    Write-Log "Failed to upgrade pip: $_" "ERROR"
    throw
}

Write-Log "Installing zstandard..." "INFO"
try {
    & "$VenvDir\Scripts\pip.exe" install zstandard 2>&1 | ForEach-Object {
        Write-Log "  [pip] $_" "INFO"
    }
    Write-Log "zstandard installed successfully." "SUCCESS"
} catch {
    Write-Log "Failed to install zstandard: $_" "ERROR"
    throw
}

# ============================================================
# --- Step 7: Run setuparchive.py ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 7: Running setuparchive.py" "STEP"
Write-Log "Archive path argument: $ArchivePath" "INFO"

try {
    & "$VenvDir\Scripts\python.exe" setuparchive.py $ArchivePath 2>&1 | ForEach-Object {
        Write-Log "  [python] $_" "INFO"
    }
    Write-Log "setuparchive.py completed." "SUCCESS"
} catch {
    Write-Log "setuparchive.py encountered an error: $_" "ERROR"
    throw
}

# ============================================================
# --- Step 8: (Optional) Copy patched files into game folder ---
# ============================================================
Write-LogSeparator
Write-Log "STEP 8: Post-patch file copy" "STEP"

if ($AutoCopy) {
    Write-Log "Auto-copy is enabled. Checking patched output folder: $PatchedOutput" "INFO"

    if (-not (Test-Path $PatchedOutput)) {
        Write-Log "Patched output folder not found at '$PatchedOutput'. Skipping copy." "WARN"
    } else {
        $PatchedItems = Get-ChildItem -Path $PatchedOutput -Recurse -File
        if ($PatchedItems.Count -eq 0) {
            Write-Log "No files found in '$PatchedOutput'. Skipping copy." "WARN"
        } else {
            Write-Log "Found $($PatchedItems.Count) file(s) to copy." "INFO"
            try {
                Copy-Item -Path "$PatchedOutput\*" -Destination $ArchivePath -Recurse -Force
                Write-Log "Successfully copied $($PatchedItems.Count) file(s) to: $ArchivePath" "SUCCESS"
                $PatchedItems | ForEach-Object {
                    Write-Log "  Copied: $($_.FullName)" "INFO"
                }
            } catch {
                Write-Log "Failed to copy patched files: $_" "ERROR"
                throw
            }
        }
    }
} else {
    Write-Log "Auto-copy is disabled. Skipping." "INFO"
}

# ============================================================
Write-LogSeparator
Write-Log "All steps completed successfully." "SUCCESS"
Write-Log "Log saved to: $((Resolve-Path $LogFile).Path)" "INFO"
Write-Log "========================================" "INFO"
Write-Host ""
