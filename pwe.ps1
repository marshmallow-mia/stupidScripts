# Setup Script: Install Python 3 64-bit, configure venv, and run setuparchive.py

$ErrorActionPreference = "Stop"

# --- Configuration ---
$PythonVersion  = "3.13.3"
$PythonUrl      = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
$PythonInstaller = "$env:TEMP\python-amd64-installer.exe"
$PythonInstallDir = "C:\Python313"
$VenvDir        = ".\venv"
$ArchivePath    = "./ready-at-dawn-echo-arena/_data/5932408047"

# --- Step 1: Download Python 3 64-bit installer ---
Write-Host "Downloading Python $PythonVersion (64-bit)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $PythonUrl -OutFile $PythonInstaller -UseBasicParsing

# --- Step 2: Install Python silently ---
Write-Host "Installing Python $PythonVersion to $PythonInstallDir..." -ForegroundColor Cyan
Start-Process -FilePath $PythonInstaller -ArgumentList @(
    "/quiet",
    "InstallAllUsers=1",
    "TargetDir=$PythonInstallDir",
    "PrependPath=0",        # We'll manage PATH ourselves below
    "Include_launcher=1",
    "Include_pip=1",
    "Include_test=0"
) -Wait -NoNewWindow

Remove-Item $PythonInstaller -Force

# --- Step 3: Add Python to PATH (current session + permanently for Machine scope) ---
Write-Host "Adding Python to PATH..." -ForegroundColor Cyan

$PathsToAdd = @(
    $PythonInstallDir,
    "$PythonInstallDir\Scripts"
)

foreach ($p in $PathsToAdd) {
    # Permanent (Machine-level, requires admin)
    $CurrentMachinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($CurrentMachinePath -notlike "*$p*") {
        [System.Environment]::SetEnvironmentVariable(
            "Path",
            "$CurrentMachinePath;$p",
            "Machine"
        )
        Write-Host "  Added to Machine PATH: $p" -ForegroundColor Gray
    }

    # Current session
    if ($env:PATH -notlike "*$p*") {
        $env:PATH = "$env:PATH;$p"
    }
}

# Verify python is accessible
$PythonExe = "$PythonInstallDir\python.exe"
Write-Host "Python version: $(& $PythonExe --version)" -ForegroundColor Green

# --- Step 4: Create virtual environment ---
Write-Host "Creating virtual environment in $VenvDir..." -ForegroundColor Cyan
& $PythonExe -m venv $VenvDir

# --- Step 5: Activate the virtual environment ---
Write-Host "Activating virtual environment..." -ForegroundColor Cyan
$ActivateScript = "$VenvDir\Scripts\Activate.ps1"
if (-not (Test-Path $ActivateScript)) {
    throw "Activation script not found at: $ActivateScript"
}
& $ActivateScript

# --- Step 6: Upgrade pip, then install zstandard ---
Write-Host "Upgrading pip..." -ForegroundColor Cyan
& "$VenvDir\Scripts\python.exe" -m pip install --upgrade pip

Write-Host "Installing zstandard..." -ForegroundColor Cyan
& "$VenvDir\Scripts\pip.exe" install zstandard

# --- Step 7: Run setuparchive.py ---
Write-Host "Running setuparchive.py with path: $ArchivePath" -ForegroundColor Cyan
& "$VenvDir\Scripts\python.exe" setuparchive.py $ArchivePath

Write-Host "`nDone!" -ForegroundColor Green
