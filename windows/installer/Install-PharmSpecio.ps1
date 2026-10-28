# Run as Administrator (Install-PharmSpecio.bat does this).
$ErrorActionPreference = "Stop"

$Version = "1.0.26"
$versionFile = Join-Path $PSScriptRoot "version.txt"
if (Test-Path $versionFile) {
  $Version = (Get-Content $versionFile -Raw).Trim()
}

$portableName = "PharmSpecio-$Version-portable"
$source = Join-Path $PSScriptRoot $portableName
$target = Join-Path ${env:ProgramFiles} "PharmSpecio"
$exe = Join-Path $target "PharmSpecio.exe"

$required = @(
  "PharmSpecio.exe",
  "flutter_windows.dll",
  "flutter_secure_storage_windows_plugin.dll",
  "data"
)

function Test-PharmSpecioBundle {
  param([string]$Root)
  $missing = @()
  foreach ($item in $required) {
    $path = Join-Path $Root $item
    if (-not (Test-Path $path)) { $missing += $item }
  }
  if ($missing.Count -gt 0) {
    throw "Incomplete PharmSpecio folder. Missing: $($missing -join ', '). Extract the full zip or copy the whole '$portableName' folder — do not copy PharmSpecio.exe alone."
  }
}

if (-not (Test-Path $source)) {
  $alt = Join-Path $PSScriptRoot "portable"
  if (Test-Path $alt) { $source = $alt } else {
    Write-Host "Missing folder: $source"
    Write-Host "Use the full Setup package from GitHub, not a single .exe file."
    exit 1
  }
}

Test-PharmSpecioBundle -Root $source

Write-Host "Installing PharmSpecio $Version to $target ..."
Get-Process PharmSpecio -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Path "$source\*" -Destination $target -Recurse -Force

Test-PharmSpecioBundle -Root $target

$vc = Join-Path $PSScriptRoot "redist\vc_redist.x64.exe"
if (Test-Path $vc) {
  Write-Host "Installing Visual C++ runtime..."
  Start-Process -FilePath $vc -ArgumentList "/install", "/quiet", "/norestart" -Wait
}

$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcut = $shell.CreateShortcut((Join-Path $desktop "PharmSpecio.lnk"))
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = $target
$shortcut.Save()

$startMenu = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
$smShortcut = $shell.CreateShortcut((Join-Path $startMenu "PharmSpecio.lnk"))
$smShortcut.TargetPath = $exe
$smShortcut.WorkingDirectory = $target
$smShortcut.Save()

Write-Host "Done. All files (including plugin DLLs) are in: $target"
Write-Host "Open PharmSpecio from the desktop shortcut."
