# Setup Script: Install Python 3 64-bit, configure venv, and run setuparchive.py

$ErrorActionPreference = "Stop"

# --- Configuration ---
$PythonVersion   = "3.13.3"
$PythonUrl       = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
$PythonInstaller = "$env:TEMP\python-amd64-installer.exe"
$PythonInstallDir = "C:\Python313"
$VenvDir         = ".\venv"
$DefaultGamePath = "C:\Program Files\Meta Horizon\Software\Software\ready-at-dawn-echo-arena"
$DataSubPath     = "_data\5932408047"
$PatchedOutput   = ".\patched_output"

# ============================================================
# --- Step 0: Resolve game folder path ---
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Echo Arena - Archive Patcher Setup" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

$GameFolder = $null

if (Test-Path $DefaultGamePath) {
    Write-Host "Game folder found at default location:" -ForegroundColor Green
    Write-Host "  $DefaultGamePath" -ForegroundColor White
    Write-Host ""
    $confirm = Read-Host "Is this the correct game folder? (Y/N)"
    if ($confirm -match "^[Yy]$") {
        $GameFolder = $DefaultGamePath
    }
}

if (-not $GameFolder) {
    Write-Host ""
    Write-Host "Please enter the full path to the 'ready-at-dawn-echo-arena' folder:" -ForegroundColor Cyan
    do {
        $inputPath = Read-Host "Path"
        $inputPath = $inputPath.Trim('"').Trim("'").Trim()
        if (-not (Test-Path $inputPath)) {
            Write-Host "  Path not found. Please try again." -ForegroundColor Red
        }
    } while (-not (Test-Path $inputPath))
    $GameFolder = $inputPath
}

$ArchivePath = Join-Path $GameFolder $DataSubPath
Write-Host ""
Write-Host "Using archive path: $ArchivePath" -ForegroundColor Green

# ============================================================
# --- Step 0b: Ask about auto-copy of patched files ---
# ============================================================
Write-Host ""
$copyAnswer = Read-Host "Automatically copy patched files into the game folder when done? (Y/N)"
$AutoCopy = $copyAnswer -match "^[Yy]$"

if ($AutoCopy) {
    Write-Host "Patched files WILL be copied to: $ArchivePath" -ForegroundColor Green
} else {
    Write-Host "Patched files will NOT be copied automatically." -ForegroundColor Gray
}
Write-Host ""

# ============================================================
# --- Step 1: Check if Python is already installed & usable ---
# ============================================================
Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host "Checking for existing Python installation..." -ForegroundColor Cyan

$PythonExe = $null

# First, check if 'python' is already on PATH and is 64-bit
$PythonOnPath = Get-Command python -ErrorAction SilentlyContinue

if ($PythonOnPath) {
    $detectedExe = $PythonOnPath.Source
    try {
        $arch = & $detectedExe -c "import struct; print(struct.calcsize('P') * 8)"
        $ver  = & $detectedExe --version 2>&1
        if ($arch -eq "64") {
            Write-Host "  Found usable 64-bit Python on PATH: $detectedExe" -ForegroundColor Green
            Write-Host "  Version: $ver" -ForegroundColor Gray
            $PythonExe = $detectedExe
        } else {
            Write-Host "  Found Python on PATH but it is 32-bit ($detectedExe). Will install 64-bit." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  Python found on PATH but could not be queried. Will install fresh." -ForegroundColor Yellow
    }
}

# If not found on PATH, check the known install directory
if (-not $PythonExe -and (Test-Path "$PythonInstallDir\python.exe")) {
    $detectedExe = "$PythonInstallDir\python.exe"
    try {
        $arch = & $detectedExe -c "import struct; print(struct.calcsize('P') * 8)"
        $ver  = & $detectedExe --version 2>&1
        if ($arch -eq "64") {
            Write-Host "  Found usable 64-bit Python at $detectedExe (not yet on PATH)." -ForegroundColor Green
            Write-Host "  Version: $ver" -ForegroundColor Gray
            $PythonExe = $detectedExe
        }
    } catch {
        Write-Host "  Python found at $detectedExe but could not be queried. Will reinstall." -ForegroundColor Yellow
    }
}

# ============================================================
# --- Step 2: Install Python only if needed ---
# ============================================================
if ($PythonExe) {
    Write-Host "Skipping Python installation — already ready to use." -ForegroundColor Green
} else {
    Write-Host "Python 64-bit not found. Downloading and installing Python $PythonVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PythonUrl -OutFile $PythonInstaller -UseBasicParsing

    Start-Process -FilePath $PythonInstaller -ArgumentList @(
        "/quiet",
        "InstallAllUsers=1",
        "TargetDir=$PythonInstallDir",
        "PrependPath=0",
        "Include_launcher=1",
        "Include_pip=1",
        "Include_test=0"
    ) -Wait -NoNewWindow

    Remove-Item $PythonInstaller -Force
    $PythonExe = "$PythonInstallDir\python.exe"
    Write-Host "Python installed: $(& $PythonExe --version)" -ForegroundColor Green
}

# ============================================================
# --- Step 3: Ensure Python is on PATH (if not already) ---
# ============================================================
$PythonDir     = Split-Path $PythonExe -Parent
$PythonScripts = Join-Path $PythonDir "Scripts"

foreach ($p in @($PythonDir, $PythonScripts)) {
    $MachinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($MachinePath -notlike "*$p*") {
        [System.Environment]::SetEnvironmentVariable("Path", "$MachinePath;$p", "Machine")
        Write-Host "  Added to Machine PATH: $p" -ForegroundColor Gray
    }
    if ($env:PATH -notlike "*$p*") {
        $env:PATH = "$env:PATH;$p"
        Write-Host "  Added to session PATH: $p" -ForegroundColor Gray
    }
}

# ============================================================
# --- Step 4: Create virtual environment ---
# ============================================================
Write-Host ""
Write-Host "Creating virtual environment in $VenvDir..." -ForegroundColor Cyan
& $PythonExe -m venv $VenvDir

# ============================================================
# --- Step 5: Activate the virtual environment ---
# ============================================================
Write-Host "Activating virtual environment..." -ForegroundColor Cyan
$ActivateScript = "$VenvDir\Scripts\Activate.ps1"
if (-not (Test-Path $ActivateScript)) {
    throw "Activation script not found at: $ActivateScript"
}
& $ActivateScript

# ============================================================
# --- Step 6: Upgrade pip + install zstandard ---
# ============================================================
Write-Host "Upgrading pip..." -ForegroundColor Cyan
& "$VenvDir\Scripts\python.exe" -m pip install --upgrade pip

Write-Host "Installing zstandard..." -ForegroundColor Cyan
& "$VenvDir\Scripts\pip.exe" install zstandard

# ============================================================
# --- Step 7: Run setuparchive.py ---
# ============================================================
Write-Host ""
Write-Host "Running setuparchive.py..." -ForegroundColor Cyan
Write-Host "  Archive path: $ArchivePath" -ForegroundColor Gray
& "$VenvDir\Scripts\python.exe" setuparchive.py $ArchivePath

# ============================================================
# --- Step 8: (Optional) Copy patched files into game folder ---
# ============================================================
if ($AutoCopy) {
    Write-Host ""
    Write-Host "Copying patched files to game folder..." -ForegroundColor Cyan

    if (-not (Test-Path $PatchedOutput)) {
        Write-Host "  WARNING: Patched output folder not found at '$PatchedOutput'. Skipping copy." -ForegroundColor Red
    } else {
        $PatchedItems = Get-ChildItem -Path $PatchedOutput -Recurse -File
        if ($PatchedItems.Count -eq 0) {
            Write-Host "  WARNING: No files found in '$PatchedOutput'. Skipping copy." -ForegroundColor Yellow
        } else {
            Copy-Item -Path "$PatchedOutput\*" -Destination $ArchivePath -Recurse -Force
            Write-Host "  Copied $($PatchedItems.Count) file(s) to: $ArchivePath" -ForegroundColor Green
        }
    }
}

# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  All done!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
