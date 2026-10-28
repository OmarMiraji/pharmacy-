# Builds PharmSpecio-Setup-{version}.exe (Inno Setup wizard — one file for users).
# Requires: Flutter SDK, Inno Setup 6 (ISCC.exe).

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -notmatch 'version:\s*([\d.]+)\+(\d+)') {
  throw "Could not read version from pubspec.yaml"
}
$version = $Matches[1]

$iss = Join-Path $PSScriptRoot "pharmspecio.iss"
$issText = Get-Content $iss -Raw
$issText = $issText -replace '#define MyAppVersion "[^"]+"', "#define MyAppVersion `"$version`""
Set-Content -Path $iss -Value $issText -NoNewline

Write-Host "Building Windows release..."
flutter pub get
flutter build windows --release

$release = Join-Path $repoRoot "build\windows\x64\runner\Release"
foreach ($f in @("PharmSpecio.exe", "flutter_windows.dll", "flutter_secure_storage_windows_plugin.dll")) {
  if (-not (Test-Path (Join-Path $release $f))) {
    throw "Missing $f in $release"
  }
}

$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
  throw "Install Inno Setup 6 from https://jrsoftware.org/isinfo.php then run this script again."
}

Write-Host "Compiling installer with Inno Setup..."
& $iscc $iss

$setup = Join-Path $repoRoot "dist\PharmSpecio-Setup-$version.exe"
if (-not (Test-Path $setup)) {
  throw "Expected installer was not created: $setup"
}

Write-Host ""
Write-Host "READY — give users this single file:"
Write-Host "  $setup"
Write-Host "They double-click it, click Next/Install, then open Desktop shortcut."
