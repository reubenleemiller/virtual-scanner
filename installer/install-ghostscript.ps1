param(
    [string[]]$PackageIds = @(
        "ArtifexSoftware.GhostScript",
        "ArtifexSoftware.Ghostscript"
    )
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

function Find-Winget {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    }

    $candidates += Get-ChildItem -Path "C:\Users\*\AppData\Local\Microsoft\WindowsApps\winget.exe" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

if (Test-Ghostscript) {
    Write-Host "Ghostscript is already installed."
    exit 0
}

$winget = Find-Winget
if (-not $winget) {
    Write-Host "winget.exe was not found for this elevated installer session."
    exit 2
}

Write-Host "Using winget: $winget"

try {
    & $winget source update --accept-source-agreements
} catch {
    Write-Host "winget source update failed, continuing anyway: $($_.Exception.Message)"
}

foreach ($packageId in $PackageIds) {
    Write-Host "Trying Ghostscript package id: $packageId"
    & $winget install `
        --exact `
        --id $packageId `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity

    $exitCode = $LASTEXITCODE
    Write-Host "winget exited with code $exitCode for $packageId"

    if ($exitCode -eq 0 -and (Test-Ghostscript)) {
        Write-Host "Ghostscript installed successfully."
        exit 0
    }
}

if (Test-Ghostscript) {
    Write-Host "Ghostscript was found after winget completed."
    exit 0
}

Write-Host "Ghostscript was not installed by winget."
exit 3
