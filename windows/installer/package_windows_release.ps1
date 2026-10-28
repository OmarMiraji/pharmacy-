# After: flutter build windows --release
# Creates dist zip + Setup package with verified DLLs.

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

$pubspec = Get-Content "pubspec.yaml" -Raw
if ($pubspec -match 'version:\s*([\d.]+)\+(\d+)') {
  $version = $Matches[1]
  $build = $Matches[2]
} else {
  throw "Could not read version from pubspec.yaml"
}

$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  throw "Run 'flutter build windows --release' first. Missing: $releaseDir"
}

$requiredFiles = @(
  "PharmSpecio.exe",
  "flutter_windows.dll",
  "flutter_secure_storage_windows_plugin.dll"
)
$missing = @()
foreach ($f in $requiredFiles) {
  if (-not (Test-Path (Join-Path $releaseDir $f))) { $missing += $f }
}
if (-not (Test-Path (Join-Path $releaseDir "data"))) { $missing += "data\" }
if ($missing.Count -gt 0) {
  throw "Release folder is incomplete. Missing: $($missing -join ', '). Rebuild with flutter build windows --release."
}

$distRoot = Join-Path $repoRoot "dist"
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null

$stageDir = Join-Path $distRoot "pharmspecio-windows-$version"
if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
Copy-Item -Path "$releaseDir\*" -Destination $stageDir -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot "Install-PharmSpecio.ps1") $stageDir -Force
Copy-Item (Join-Path $PSScriptRoot "Install-PharmSpecio.bat") $stageDir -Force
Copy-Item (Join-Path $PSScriptRoot "SAKINISHA-KWANZA.txt") $stageDir -Force
Set-Content -Path (Join-Path $stageDir "version.txt") -Value $version -NoNewline
$redistInStage = Join-Path $stageDir "redist"
if (Test-Path (Join-Path $PSScriptRoot "redist")) {
  Copy-Item (Join-Path $PSScriptRoot "redist") $redistInStage -Recurse -Force
}

$zipName = "pharmspecio-windows-$version.zip"
$zipPath = Join-Path $distRoot $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path "$stageDir\*" -DestinationPath $zipPath -Force
Copy-Item $zipPath (Join-Path $distRoot "pharmspecio-windows.zip") -Force

$packageDir = Join-Path $distRoot "PharmSpecio-Setup-Package-$version"
$portableDir = Join-Path $packageDir "PharmSpecio-$version-portable"
if (Test-Path $packageDir) { Remove-Item $packageDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
Copy-Item -Path "$releaseDir\*" -Destination $portableDir -Recurse -Force

$redistSrc = Join-Path $PSScriptRoot "redist"
$redistDst = Join-Path $packageDir "redist"
if (Test-Path $redistSrc) {
  Copy-Item -Path $redistSrc -Destination $redistDst -Recurse -Force
}

Copy-Item (Join-Path $PSScriptRoot "Install-PharmSpecio.ps1") $packageDir -Force
Copy-Item (Join-Path $PSScriptRoot "Install-PharmSpecio.bat") $packageDir -Force
Copy-Item (Join-Path $PSScriptRoot "SAKINISHA-KWANZA.txt") $packageDir -Force
Set-Content -Path (Join-Path $packageDir "version.txt") -Value $version -NoNewline

$guide = @"
PharmSpecio $version — kusakinisha kwenye PC ya duka (Windows 10/11)

MUHIMU: Usihamishi PharmSpecio.exe peke yake. Lazima folder nzima iwe na .dll (k.m. flutter_secure_storage_windows_plugin.dll).

NJIA A — Installer (inapendekezwa)
1. Copy folder "PharmSpecio-Setup-Package-$version" kwenye USB au UltraViewer.
2. Kwenye PC ya duka: fungua folder hiyo.
3. Bofya mara mbili "Install-PharmSpecio.bat" (kubali Run as administrator).
4. Subiri "Done", kisha fungua PharmSpecio kwenye Desktop.

NJIA B — Zip
1. Extract "$zipName" kwenye C:\PharmSpecio (folder iwe na PharmSpecio.exe + dll + data).
2. Endesha PharmSpecio.exe kutoka ndani ya folder hiyo — si nje ya folder.
3. Ikiwa haifunguki: install "redist\vc_redist.x64.exe" kwanza.

Imetengenezwa: $(Get-Date -Format "yyyy-MM-dd")
"@
Set-Content -Path (Join-Path $packageDir "MWONGOZO-SAKinisho-$version.txt") -Value $guide -Encoding UTF8

$setupZip = Join-Path $distRoot "PharmSpecio-Setup-Package-$version.zip"
if (Test-Path $setupZip) { Remove-Item $setupZip -Force }
Compress-Archive -Path $packageDir -DestinationPath $setupZip -Force

Write-Host "OK version $version (build $build)"
Write-Host "  $zipPath"
Write-Host "  $setupZip"
