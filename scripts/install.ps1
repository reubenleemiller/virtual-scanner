param(
    [string]$BuildPath = ".\build\x64\VirtualScanner.ds",
    [ValidateSet("x64", "x86")]
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an Administrator PowerShell session."
}

if (-not (Test-Path $BuildPath)) {
    throw "Cannot find built data source at $BuildPath"
}

$twainRoot = if ($Arch -eq "x64") { "C:\Windows\twain_64" } else { "C:\Windows\twain_32" }
$targetDir = Join-Path $twainRoot "VirtualScanner"
$targetPath = Join-Path $targetDir "VirtualScanner.ds"

New-Item -ItemType Directory -Force $targetDir | Out-Null
Copy-Item $BuildPath $targetPath -Force

Write-Host "Installed $targetPath"
Write-Host "Make sure the matching twaindsm.dll is available to your TWAIN application."
