# Builds PureEQ for Windows and packages it as dist\PureEQ-Setup-<version>.exe.
# Requires Flutter, Visual Studio Build Tools (C++ workload) and Inno Setup 6.
#
#   .\scripts\build_windows_installer.ps1            # build + package
#   .\scripts\build_windows_installer.ps1 -NoBuild   # package an existing build
param([switch]$NoBuild)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$version = (Select-String pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value

if (-not $NoBuild) {
    flutter pub get
    # Update server address (see lib/config.dart); set by CI, optional locally.
    $defines = @()
    if ($env:PUREEQ_UPDATE_URL) { $defines += "--dart-define=PUREEQ_UPDATE_URL=$env:PUREEQ_UPDATE_URL" }
    flutter build windows --release @defines
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

# Find the Inno Setup compiler (per-user or machine-wide install, or PATH).
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { $iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source }
if (-not $iscc) { throw 'Inno Setup not found. Install it with: winget install JRSoftware.InnoSetup' }

& $iscc /Q "/DAppVersion=$version" installer\pureeq.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Write-Host "Created dist\PureEQ-Setup-$version.exe"
