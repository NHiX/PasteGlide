param(
    [string]$AppDir = "dist/windows/PasteGlide",
    [string]$Version = "0.0.0"
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$DistDir = Join-Path $RootDir "dist"
$ResolvedAppDir = Resolve-Path $AppDir -ErrorAction SilentlyContinue

if (-not $ResolvedAppDir) {
    throw "Missing Windows app folder: $AppDir. Build the Windows port first, then rerun this script."
}

$ExePath = Join-Path $ResolvedAppDir "PasteGlide.exe"
if (-not (Test-Path $ExePath)) {
    throw "Missing PasteGlide.exe in $ResolvedAppDir."
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$ZipPath = Join-Path $DistDir "PasteGlide-Windows-$Version.zip"
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive -Path (Join-Path $ResolvedAppDir "*") -DestinationPath $ZipPath
Write-Output $ZipPath

$Wix = Get-Command wix -ErrorAction SilentlyContinue
if (-not $Wix) {
    Write-Warning "WiX is not installed, so the .msi was not built. Install WiX with 'dotnet tool install --global wix'."
    exit 0
}

$MsiPath = Join-Path $DistDir "PasteGlide-Windows-$Version.msi"
$WxsPath = Join-Path $RootDir "packaging/windows/PasteGlide.wxs"

& $Wix.Source build $WxsPath `
    -d "ProductVersion=$Version" `
    -d "AppSource=$ResolvedAppDir" `
    -o $MsiPath

Write-Output $MsiPath
