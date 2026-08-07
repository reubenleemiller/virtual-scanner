param(
    [ValidateSet("x86", "x64", "arm64")]
    [string]$Arch = "x86"
)

$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an Administrator PowerShell session."
}

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceDs = Join-Path $sourceRoot "VirtualScanner.ds"
if (-not (Test-Path $sourceDs)) {
    throw "Cannot find VirtualScanner.ds next to this installer script."
}

$twainRoot = if ($Arch -eq "x86") { "C:\Windows\twain_32" } else { "C:\Windows\twain_64" }
$installDir = Join-Path $twainRoot "VirtualScanner-$Arch"
$inbox = Join-Path $env:PUBLIC "Documents\VirtualScannerInbox"

New-Item -ItemType Directory -Force $installDir | Out-Null
New-Item -ItemType Directory -Force $inbox | Out-Null
New-Item -ItemType Directory -Force (Join-Path $inbox "Scanned") | Out-Null

Copy-Item $sourceDs (Join-Path $installDir "VirtualScanner.ds") -Force
$sourceInboxExe = Join-Path $sourceRoot "VirtualScannerInbox.exe"
if (Test-Path $sourceInboxExe) {
    Copy-Item $sourceInboxExe (Join-Path $installDir "VirtualScannerInbox.exe") -Force
}
Copy-Item (Join-Path $sourceRoot "VirtualScannerInbox.ps1") (Join-Path $installDir "VirtualScannerInbox.ps1") -Force
Copy-Item (Join-Path $sourceRoot "VirtualScannerInbox.vbs") (Join-Path $installDir "VirtualScannerInbox.vbs") -Force
Copy-Item (Join-Path $sourceRoot "VirtualScanner.ico") (Join-Path $installDir "VirtualScanner.ico") -Force
$iconPng = Join-Path $sourceRoot "VirtualScanner-icon.png"
if (Test-Path $iconPng) {
    Copy-Item $iconPng (Join-Path $installDir "VirtualScanner-icon.png") -Force
}

[Environment]::SetEnvironmentVariable("VIRTUAL_SCANNER_INBOX", $inbox, "Machine")

$desktop = [Environment]::GetFolderPath("DesktopDirectory")
$startMenu = [Environment]::GetFolderPath("Programs")
$wscript = Join-Path $env:WINDIR "System32\wscript.exe"
$launcher = Join-Path $installDir "VirtualScannerInbox.exe"
if (-not (Test-Path $launcher)) {
    $launcher = Join-Path $installDir "VirtualScannerInbox.vbs"
}
$icon = Join-Path $installDir "VirtualScanner.ico"

$shell = New-Object -ComObject WScript.Shell
foreach ($shortcutPath in @(
    (Join-Path $desktop "Virtual Scanner Inbox.lnk"),
    (Join-Path $startMenu "Virtual Scanner Inbox.lnk")
)) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    if ([IO.Path]::GetExtension($launcher).Equals(".exe", [StringComparison]::OrdinalIgnoreCase)) {
        $shortcut.TargetPath = $launcher
        $shortcut.Arguments = ""
    } else {
        $shortcut.TargetPath = $wscript
        $shortcut.Arguments = "`"$launcher`""
    }
    $shortcut.IconLocation = "$icon,0"
    $shortcut.Save()
}

Write-Host "Installed Virtual Scanner $Arch to $installDir"
Write-Host "Inbox: $inbox"
