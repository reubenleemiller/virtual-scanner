param(
    [string]$GhostscriptReleaseApi = "https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest"
)

$ErrorActionPreference = "Stop"

function Test-Ghostscript {
    $envPath = [Environment]::GetEnvironmentVariable("VIRTUAL_SCANNER_GHOSTSCRIPT", "Machine")
    if ($envPath -and (Test-Path -LiteralPath $envPath)) {
        return $true
    }

    foreach ($name in @("gswin64c.exe", "gswin32c.exe")) {
        if (Get-Command $name -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    $roots = @(
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ }

    foreach ($root in $roots) {
        $gsRoot = Join-Path $root "gs"
        if (-not (Test-Path -LiteralPath $gsRoot)) {
            continue
        }

        foreach ($versionDir in Get-ChildItem -LiteralPath $gsRoot -Directory -Filter "gs*" -ErrorAction SilentlyContinue) {
            foreach ($exeName in @("gswin64c.exe", "gswin32c.exe")) {
                $candidate = Join-Path $versionDir.FullName "bin\$exeName"
                if (Test-Path -LiteralPath $candidate) {
                    return $true
                }
            }
        }
    }

    return $false
}

function Get-GhostscriptInstallerUrl {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $assetPattern = if ([Environment]::Is64BitOperatingSystem) {
        "^gs\d+w64\.exe$"
    } else {
        "^gs\d+w32\.exe$"
    }

    Write-Host "Looking up the latest Ghostscript Windows installer..."
    $release = Invoke-RestMethod `
        -Uri $GhostscriptReleaseApi `
        -Headers @{ "User-Agent" = "VirtualScannerInstaller" } `
        -UseBasicParsing

    $asset = $release.assets |
        Where-Object { $_.name -match $assetPattern } |
        Select-Object -First 1

    if (-not $asset) {
        throw "Could not find a matching Ghostscript Windows installer asset."
    }

    return $asset.browser_download_url
}

function Install-GhostscriptFromDownload {
    $url = Get-GhostscriptInstallerUrl
    $fileName = Split-Path ([Uri]$url).AbsolutePath -Leaf
    $downloadPath = Join-Path $env:TEMP $fileName

    Write-Host "Downloading Ghostscript from $url"
    Invoke-WebRequest `
        -Uri $url `
        -OutFile $downloadPath `
        -Headers @{ "User-Agent" = "VirtualScannerInstaller" } `
        -UseBasicParsing

    Write-Host "Launching Ghostscript installer: $downloadPath"
    Write-Host "Complete the Ghostscript setup window, then this installer will continue."
    $process = Start-Process -FilePath $downloadPath -Wait -PassThru
    Write-Host "Ghostscript installer exited with code $($process.ExitCode)"

    if (Test-Ghostscript) {
        Write-Host "Ghostscript installed successfully from the downloaded installer."
        return $true
    }

    return $false
}

if (Test-Ghostscript) {
    Write-Host "Ghostscript is already installed."
    exit 0
}

try {
    if (Install-GhostscriptFromDownload) {
        exit 0
    }
} catch {
    Write-Host "Ghostscript download or installer launch failed: $($_.Exception.Message)"
}

Write-Host "Ghostscript was not installed."
exit 3
