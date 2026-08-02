try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
}

$ErrorActionPreference = "Stop"

function Get-InboxPath {
    $path = [Environment]::GetEnvironmentVariable("VIRTUAL_SCANNER_INBOX", "Machine")
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $env:PUBLIC "Documents\VirtualScannerInbox"
    }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $path "Scanned") | Out-Null
    return $path
}

function Copy-WithUniqueName {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationFolder
    )

    $name = [IO.Path]::GetFileName($Source)
    $target = Join-Path $DestinationFolder $name
    if (-not (Test-Path $target)) {
        Copy-Item $Source $target
        return
    }

    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $ext = [IO.Path]::GetExtension($name)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item $Source (Join-Path $DestinationFolder "$base-$stamp$ext")
}

function Refresh-List {
    $list.Items.Clear()
    $files = Get-ChildItem $script:InboxPath -File |
        Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|bmp|tif|tiff|pdf)$' } |
        Sort-Object Name
    foreach ($file in $files) {
        [void]$list.Items.Add($file.Name)
    }
    $status.Text = "$($files.Count) file(s) ready"
}

function Signal-ScanReady {
    $signalPath = Join-Path $script:InboxPath ".scan-now"
    Set-Content -Path $signalPath -Value (Get-Date -Format "o") -Encoding ASCII
}

$script:InboxPath = Get-InboxPath

$form = New-Object Windows.Forms.Form
$form.Text = "Virtual Scanner Inbox"
$form.Icon = [Drawing.SystemIcons]::Application
$form.Size = New-Object Drawing.Size(620, 420)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object Drawing.Size(520, 340)

$label = New-Object Windows.Forms.Label
$label.Text = "Scanner inbox"
$label.Location = New-Object Drawing.Point(16, 14)
$label.AutoSize = $true
$form.Controls.Add($label)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Location = New-Object Drawing.Point(16, 38)
$pathBox.Size = New-Object Drawing.Size(470, 24)
$pathBox.ReadOnly = $true
$pathBox.Text = $script:InboxPath
$form.Controls.Add($pathBox)

$openButton = New-Object Windows.Forms.Button
$openButton.Text = "Open Folder"
$openButton.Location = New-Object Drawing.Point(494, 36)
$openButton.Size = New-Object Drawing.Size(95, 28)
$openButton.Add_Click({ Start-Process explorer.exe $script:InboxPath })
$form.Controls.Add($openButton)

$addButton = New-Object Windows.Forms.Button
$addButton.Text = "Add Files..."
$addButton.Location = New-Object Drawing.Point(16, 76)
$addButton.Size = New-Object Drawing.Size(100, 30)
$addButton.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = "Add scanner files"
    $dialog.Filter = "Scanner files|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.pdf|All files|*.*"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        foreach ($file in $dialog.FileNames) {
            Copy-WithUniqueName -Source $file -DestinationFolder $script:InboxPath
        }
        Refresh-List
    }
})
$form.Controls.Add($addButton)

$clearButton = New-Object Windows.Forms.Button
$clearButton.Text = "Clear Ready"
$clearButton.Location = New-Object Drawing.Point(124, 76)
$clearButton.Size = New-Object Drawing.Size(100, 30)
$clearButton.Add_Click({
    $confirm = [Windows.Forms.MessageBox]::Show(
        "Remove all ready-to-scan files from the inbox?",
        "Clear ready files",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -eq [Windows.Forms.DialogResult]::Yes) {
        Get-ChildItem $script:InboxPath -File |
            Where-Object { $_.Extension -match '^\.(png|jpg|jpeg|bmp|tif|tiff|pdf)$' } |
            Remove-Item -Force
        Refresh-List
    }
})
$form.Controls.Add($clearButton)

$refreshButton = New-Object Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Location = New-Object Drawing.Point(232, 76)
$refreshButton.Size = New-Object Drawing.Size(90, 30)
$refreshButton.Add_Click({ Refresh-List })
$form.Controls.Add($refreshButton)

$scanButton = New-Object Windows.Forms.Button
$scanButton.Text = "Scan"
$scanButton.Location = New-Object Drawing.Point(430, 76)
$scanButton.Size = New-Object Drawing.Size(160, 30)
$scanButton.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$scanButton.Add_Click({
    Refresh-List
    if ($list.Items.Count -eq 0) {
        [Windows.Forms.MessageBox]::Show(
            "Add at least one image or PDF before scanning.",
            "Virtual Scanner Inbox",
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    Signal-ScanReady
    $form.Close()
})
$form.Controls.Add($scanButton)

$list = New-Object Windows.Forms.ListBox
$list.Location = New-Object Drawing.Point(16, 118)
$list.Size = New-Object Drawing.Size(573, 210)
$list.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($list)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(16, 342)
$status.Size = New-Object Drawing.Size(573, 24)
$status.Anchor = [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($status)

$form.Add_Shown({ Refresh-List })
try {
    [void]$form.ShowDialog()
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Virtual Scanner Inbox Error")
}
