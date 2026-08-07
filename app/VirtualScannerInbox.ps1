$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
}

$script:SupportedExtensions = @(".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".pdf")

function Get-InboxPath {
    $path = [Environment]::GetEnvironmentVariable("VIRTUAL_SCANNER_INBOX", "Machine")
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $env:PUBLIC "Documents\VirtualScannerInbox"
    }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $path "Scanned") | Out-Null
    return $path
}

function Get-AppIconPath {
    if ($PSScriptRoot) {
        $path = Join-Path $PSScriptRoot "VirtualScanner.ico"
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }
    return $null
}

function Test-SupportedFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return $script:SupportedExtensions -contains ([IO.Path]::GetExtension($Path).ToLowerInvariant())
}

function Copy-WithUniqueName {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationFolder
    )

    if (-not (Test-SupportedFile -Path $Source)) {
        return $false
    }

    $name = [IO.Path]::GetFileName($Source)
    $target = Join-Path $DestinationFolder $name
    if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $Source -Destination $target
        return $true
    }

    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $ext = [IO.Path]::GetExtension($name)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $index = 1
    do {
        $target = Join-Path $DestinationFolder ("{0}-{1}-{2}{3}" -f $base, $stamp, $index, $ext)
        $index++
    } while (Test-Path -LiteralPath $target)

    Copy-Item -LiteralPath $Source -Destination $target
    return $true
}

function Get-ReadyFiles {
    if (-not (Test-Path -LiteralPath $script:InboxPath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $script:InboxPath -File |
        Where-Object { Test-SupportedFile -Path $_.FullName } |
        Sort-Object Name)
}

function Refresh-List {
    $selectedName = $null
    if ($list.SelectedItem) {
        $selectedName = [string]$list.SelectedItem
    }

    $files = Get-ReadyFiles
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        foreach ($file in $files) {
            $display = "{0}    {1:N0} KB" -f $file.Name, [Math]::Max(1, [Math]::Ceiling($file.Length / 1KB))
            [void]$list.Items.Add($display)
            if ($selectedName -and $display.StartsWith($selectedName.Split("    ")[0])) {
                $list.SelectedItem = $display
            }
        }
    } finally {
        $list.EndUpdate()
    }

    $count = $files.Count
    $clearButton.Enabled = $count -gt 0
    $removeButton.Enabled = $list.SelectedIndex -ge 0
    if ($count -eq 1) {
        $status.Text = "1 file ready"
    } else {
        $status.Text = "$count files ready"
    }
}

function Add-Files {
    param([string[]]$Paths)

    $added = 0
    foreach ($path in $Paths) {
        if ((Test-Path -LiteralPath $path -PathType Leaf) -and
            (Copy-WithUniqueName -Source $path -DestinationFolder $script:InboxPath)) {
            $added++
        }
    }

    Refresh-List
    if ($added -eq 0) {
        $status.Text = "No supported files were added"
    }
}

function Get-SelectedFilePath {
    if ($list.SelectedIndex -lt 0) {
        return $null
    }

    $selected = [string]$list.SelectedItem
    $name = $selected.Split("    ")[0]
    $path = Join-Path $script:InboxPath $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return $path
    }
    return $null
}

function Signal-ScanReady {
    $signalPath = Join-Path $script:InboxPath ".scan-now"
    [IO.File]::WriteAllText($signalPath, (Get-Date -Format "o"), [Text.Encoding]::ASCII)
}

function Open-Inbox {
    Start-Process explorer.exe "`"$script:InboxPath`""
}

function Open-SelectedFile {
    $path = Get-SelectedFilePath
    if ($path) {
        Start-Process explorer.exe "/select,`"$path`""
    } else {
        Open-Inbox
    }
}

function Remove-SelectedFile {
    $path = Get-SelectedFilePath
    if ($path) {
        Remove-Item -LiteralPath $path -Force
        Refresh-List
    }
}

$script:InboxPath = Get-InboxPath
$iconPath = Get-AppIconPath

[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = "Virtual Scanner Inbox"
$form.Size = New-Object Drawing.Size(620, 420)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object Drawing.Size(520, 340)
$form.BackColor = [Drawing.Color]::FromArgb(246, 248, 251)
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.AllowDrop = $true
$form.KeyPreview = $true
if ($iconPath) {
    $form.Icon = New-Object Drawing.Icon($iconPath)
} else {
    $form.Icon = [Drawing.SystemIcons]::Application
}

$titleIcon = New-Object Windows.Forms.PictureBox
$titleIcon.Location = New-Object Drawing.Point(16, 12)
$titleIcon.Size = New-Object Drawing.Size(24, 24)
$titleIcon.SizeMode = [Windows.Forms.PictureBoxSizeMode]::StretchImage
if ($form.Icon) {
    $titleIcon.Image = $form.Icon.ToBitmap()
}
$form.Controls.Add($titleIcon)

$label = New-Object Windows.Forms.Label
$label.Text = "Virtual Scanner Inbox"
$label.Location = New-Object Drawing.Point(48, 13)
$label.AutoSize = $true
$label.Font = New-Object Drawing.Font("Segoe UI Semibold", 10)
$label.ForeColor = [Drawing.Color]::FromArgb(15, 23, 42)
$form.Controls.Add($label)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Location = New-Object Drawing.Point(16, 38)
$pathBox.Size = New-Object Drawing.Size(470, 24)
$pathBox.ReadOnly = $true
$pathBox.TabStop = $false
$pathBox.Text = $script:InboxPath
$form.Controls.Add($pathBox)

$openButton = New-Object Windows.Forms.Button
$openButton.Text = "Open Folder"
$openButton.Location = New-Object Drawing.Point(494, 36)
$openButton.Size = New-Object Drawing.Size(95, 28)
$openButton.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$openButton.Add_Click({ Open-Inbox })
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
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        Add-Files -Paths $dialog.FileNames
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
        foreach ($file in Get-ReadyFiles) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
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

$removeButton = New-Object Windows.Forms.Button
$removeButton.Text = "Remove"
$removeButton.Location = New-Object Drawing.Point(330, 76)
$removeButton.Size = New-Object Drawing.Size(90, 30)
$removeButton.Add_Click({ Remove-SelectedFile })
$form.Controls.Add($removeButton)

$scanButton = New-Object Windows.Forms.Button
$scanButton.Text = "Scan"
$scanButton.Location = New-Object Drawing.Point(430, 76)
$scanButton.Size = New-Object Drawing.Size(160, 30)
$scanButton.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$scanButton.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$scanButton.BackColor = [Drawing.Color]::FromArgb(30, 64, 175)
$scanButton.ForeColor = [Drawing.Color]::White
$scanButton.FlatAppearance.BorderSize = 0
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
$list.BackColor = [Drawing.Color]::White
$list.Add_DoubleClick({ Open-SelectedFile })
$list.Add_SelectedIndexChanged({ $removeButton.Enabled = $list.SelectedIndex -ge 0 })
$form.Controls.Add($list)

$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(16, 342)
$status.Size = New-Object Drawing.Size(573, 24)
$status.Anchor = [Windows.Forms.AnchorStyles]::Bottom -bor [Windows.Forms.AnchorStyles]::Left -bor [Windows.Forms.AnchorStyles]::Right
$status.ForeColor = [Drawing.Color]::FromArgb(51, 65, 85)
$form.Controls.Add($status)

$dragHandler = {
    if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [Windows.Forms.DragDropEffects]::Copy
    } else {
        $_.Effect = [Windows.Forms.DragDropEffects]::None
    }
}
$dropHandler = {
    $paths = [string[]]$_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    Add-Files -Paths $paths
}
$form.Add_DragEnter($dragHandler)
$form.Add_DragDrop($dropHandler)
$list.Add_DragEnter($dragHandler)
$list.Add_DragDrop($dropHandler)

$form.Add_KeyDown({
    if ($_.KeyCode -eq [Windows.Forms.Keys]::F5) {
        Refresh-List
    } elseif ($_.KeyCode -eq [Windows.Forms.Keys]::Delete -and $list.SelectedIndex -ge 0) {
        Remove-SelectedFile
    } elseif ($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::O) {
        Open-Inbox
    }
})

$form.Add_Shown({
    $removeButton.Enabled = $false
    Refresh-List
    $addButton.Focus()
})

try {
    [void]$form.ShowDialog()
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Virtual Scanner Inbox Error")
}
