$ErrorActionPreference = "Stop"

Write-Host "Processor architecture: $env:PROCESSOR_ARCHITECTURE"
Write-Host "Virtual scanner inbox: $env:VIRTUAL_SCANNER_INBOX"

Write-Host ""
Write-Host "TWAIN folders:"
$folders = @(
    "$env:WINDIR\twain_32",
    "$env:WINDIR\twain_64"
)

foreach ($folder in $folders) {
    Write-Host ""
    Write-Host $folder
    if (Test-Path $folder) {
        Get-ChildItem $folder -Recurse -Filter *.ds |
            Select-Object FullName, Length, LastWriteTime |
            Format-Table -AutoSize
    } else {
        Write-Host "Missing"
    }
}

Write-Host ""
Write-Host "ExamView process, if running:"
Get-Process |
    Where-Object { $_.ProcessName -match "exam|ev" } |
    Select-Object ProcessName, Id, Path |
    Format-Table -AutoSize

