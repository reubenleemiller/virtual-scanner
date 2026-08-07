$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
}

$script:SupportedExtensions = @(".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".pdf")
$script:ReadyFiles = @()
$script:InboxPath = $null

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

function Get-AppImagePath {
    if ($PSScriptRoot) {
        $path = Join-Path $PSScriptRoot "VirtualScanner-icon.png"
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

function Format-FileSize {
    param([Parameter(Mandatory = $true)][long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
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

function Set-Status {
    param([string]$Message)
    $statusLabel.Text = $Message
}

function Refresh-List {
    $selectedPaths = @{}
    foreach ($item in $list.SelectedItems) {
        $selectedPaths[$item.Tag] = $true
    }

    $script:ReadyFiles = Get-ReadyFiles
    $list.BeginUpdate()
    try {
        $list.Items.Clear()
        foreach ($file in $script:ReadyFiles) {
            $item = New-Object Windows.Forms.ListViewItem($file.Name)
            [void]$item.SubItems.Add((Format-FileSize -Bytes $file.Length))
            [void]$item.SubItems.Add($file.LastWriteTime.ToString("g"))
            $item.Tag = $file.FullName
            if ($selectedPaths.ContainsKey($file.FullName)) {
                $item.Selected = $true
            }
            [void]$list.Items.Add($item)
        }
    } finally {
        $list.EndUpdate()
    }

    Resize-ListColumns

    $count = $script:ReadyFiles.Count
    $scanButton.Enabled = $count -gt 0
    $clearButton.Enabled = $count -gt 0
    $removeButton.Enabled = $list.SelectedItems.Count -gt 0

    if ($count -eq 0) {
        Set-Status "No files queued. Add or drop PNG, JPG, TIFF, BMP, or PDF files."
    } elseif ($count -eq 1) {
        Set-Status "1 file queued."
    } else {
        Set-Status "$count files queued in name order."
    }
}

function Resize-ListColumns {
    if (-not $list -or $list.Columns.Count -lt 3) {
        return
    }

    $available = [Math]::Max(360, $list.ClientSize.Width - 24)
    $list.Columns[1].Width = 92
    $list.Columns[2].Width = 150
    $list.Columns[0].Width = [Math]::Max(180, $available - $list.Columns[1].Width - $list.Columns[2].Width)
}

function Add-Files {
    param([string[]]$Paths)

    $added = 0
    $form.UseWaitCursor = $true
    $addButton.Enabled = $false
    try {
        foreach ($path in $Paths) {
            if ((Test-Path -LiteralPath $path -PathType Leaf) -and
                (Copy-WithUniqueName -Source $path -DestinationFolder $script:InboxPath)) {
                $added++
            }
        }
    } finally {
        $addButton.Enabled = $true
        $form.UseWaitCursor = $false
    }

    Refresh-List
    if ($added -eq 1) {
        Set-Status "Added 1 file."
    } elseif ($added -gt 1) {
        Set-Status "Added $added files."
    } else {
        Set-Status "No supported files were added."
    }
}

function Signal-ScanReady {
    $signalPath = Join-Path $script:InboxPath ".scan-now"
    [IO.File]::WriteAllText($signalPath, (Get-Date -Format "o"), [Text.Encoding]::ASCII)
}

function Open-Inbox {
    Start-Process explorer.exe "`"$script:InboxPath`""
}

function Open-SelectedFile {
    if ($list.SelectedItems.Count -gt 0) {
        Start-Process explorer.exe "/select,`"$($list.SelectedItems[0].Tag)`""
    } else {
        Open-Inbox
    }
}

function Remove-SelectedFiles {
    foreach ($item in @($list.SelectedItems)) {
        if (Test-Path -LiteralPath $item.Tag -PathType Leaf) {
            Remove-Item -LiteralPath $item.Tag -Force
        }
    }
    Refresh-List
}

function Add-RowStyle {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.TableLayoutPanel]$Panel,
        [Parameter(Mandatory = $true)][Windows.Forms.SizeType]$SizeType,
        [Parameter(Mandatory = $true)][single]$Height
    )
    $style = New-Object Windows.Forms.RowStyle
    $style.SizeType = $SizeType
    $style.Height = $Height
    [void]$Panel.RowStyles.Add($style)
}

function Add-ColumnStyle {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.TableLayoutPanel]$Panel,
        [Parameter(Mandatory = $true)][Windows.Forms.SizeType]$SizeType,
        [Parameter(Mandatory = $true)][single]$Width
    )
    $style = New-Object Windows.Forms.ColumnStyle
    $style.SizeType = $SizeType
    $style.Width = $Width
    [void]$Panel.ColumnStyles.Add($style)
}

$script:InboxPath = Get-InboxPath
$iconPath = Get-AppIconPath
$imagePath = Get-AppImagePath
$appIcon = $null
$headerImage = $null

[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = "Virtual Scanner Inbox"
$form.Size = New-Object Drawing.Size(760, 520)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object Drawing.Size(660, 440)
$form.BackColor = [Drawing.Color]::FromArgb(246, 248, 251)
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.AllowDrop = $true
$form.KeyPreview = $true
if ($iconPath) {
    $appIcon = New-Object Drawing.Icon($iconPath)
    $form.Icon = $appIcon
} else {
    $form.Icon = [Drawing.SystemIcons]::Application
}
if ($imagePath) {
    $headerImage = [Drawing.Image]::FromFile($imagePath)
} elseif ($appIcon) {
    $headerImage = $appIcon.ToBitmap()
}

$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = [Windows.Forms.DockStyle]::Fill
$layout.ColumnCount = 1
$layout.RowCount = 5
$layout.BackColor = $form.BackColor
Add-RowStyle -Panel $layout -SizeType ([Windows.Forms.SizeType]::Absolute) -Height 72
Add-RowStyle -Panel $layout -SizeType ([Windows.Forms.SizeType]::Absolute) -Height 52
Add-RowStyle -Panel $layout -SizeType ([Windows.Forms.SizeType]::Absolute) -Height 48
Add-RowStyle -Panel $layout -SizeType ([Windows.Forms.SizeType]::Percent) -Height 100
Add-RowStyle -Panel $layout -SizeType ([Windows.Forms.SizeType]::Absolute) -Height 38
$form.Controls.Add($layout)

$header = New-Object Windows.Forms.Panel
$header.Dock = [Windows.Forms.DockStyle]::Fill
$header.BackColor = [Drawing.Color]::White
$layout.Controls.Add($header, 0, 0)

if ($headerImage) {
    $iconBox = New-Object Windows.Forms.PictureBox
    $iconBox.Image = $headerImage
    $iconBox.SizeMode = [Windows.Forms.PictureBoxSizeMode]::StretchImage
    $iconBox.Size = New-Object Drawing.Size(36, 36)
    $iconBox.Location = New-Object Drawing.Point(20, 18)
    $header.Controls.Add($iconBox)
}

$titleLabel = New-Object Windows.Forms.Label
$titleLabel.Text = "Virtual Scanner Inbox"
$titleLabel.ForeColor = [Drawing.Color]::FromArgb(15, 23, 42)
$titleLabel.Font = New-Object Drawing.Font("Segoe UI Semibold", 15)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object Drawing.Point(68, 12)
$header.Controls.Add($titleLabel)

$subtitleLabel = New-Object Windows.Forms.Label
$subtitleLabel.Text = "Queue files for your next scan."
$subtitleLabel.ForeColor = [Drawing.Color]::FromArgb(71, 85, 105)
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object Drawing.Point(70, 42)
$header.Controls.Add($subtitleLabel)

$scanButton = New-Object Windows.Forms.Button
$scanButton.Text = "Scan"
$scanButton.Font = New-Object Drawing.Font("Segoe UI Semibold", 10)
$scanButton.Size = New-Object Drawing.Size(118, 36)
$scanButton.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$scanButton.Location = New-Object Drawing.Point(620, 20)
$scanButton.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$scanButton.BackColor = [Drawing.Color]::FromArgb(30, 64, 175)
$scanButton.ForeColor = [Drawing.Color]::White
$scanButton.FlatAppearance.BorderSize = 0
$scanButton.Add_Click({
    Refresh-List
    if ($script:ReadyFiles.Count -eq 0) {
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
$header.Controls.Add($scanButton)

$pathPanel = New-Object Windows.Forms.TableLayoutPanel
$pathPanel.Dock = [Windows.Forms.DockStyle]::Fill
$pathPanel.ColumnCount = 2
$pathPanel.RowCount = 1
$pathPanel.Padding = New-Object Windows.Forms.Padding(18, 11, 18, 8)
$pathPanel.BackColor = $form.BackColor
[void]$pathPanel.ColumnStyles.Clear()
Add-ColumnStyle -Panel $pathPanel -SizeType ([Windows.Forms.SizeType]::Percent) -Width 100
Add-ColumnStyle -Panel $pathPanel -SizeType ([Windows.Forms.SizeType]::Absolute) -Width 94
$layout.Controls.Add($pathPanel, 0, 1)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Dock = [Windows.Forms.DockStyle]::Fill
$pathBox.ReadOnly = $true
$pathBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$pathBox.Text = $script:InboxPath
$pathBox.TabStop = $false
$pathPanel.Controls.Add($pathBox, 0, 0)

$openButton = New-Object Windows.Forms.Button
$openButton.Text = "Open"
$openButton.Dock = [Windows.Forms.DockStyle]::Fill
$openButton.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 0)
$openButton.Add_Click({ Open-Inbox })
$pathPanel.Controls.Add($openButton, 1, 0)

$toolbar = New-Object Windows.Forms.FlowLayoutPanel
$toolbar.Dock = [Windows.Forms.DockStyle]::Fill
$toolbar.Padding = New-Object Windows.Forms.Padding(14, 5, 14, 5)
$toolbar.BackColor = $form.BackColor
$toolbar.WrapContents = $false
$layout.Controls.Add($toolbar, 0, 2)

$addButton = New-Object Windows.Forms.Button
$addButton.Text = "Add Files..."
$addButton.Size = New-Object Drawing.Size(104, 32)
$addButton.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = "Add scanner files"
    $dialog.Filter = "Scanner files|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.pdf|All files|*.*"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        Add-Files -Paths $dialog.FileNames
    }
})
[void]$toolbar.Controls.Add($addButton)

$refreshButton = New-Object Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Size = New-Object Drawing.Size(92, 32)
$refreshButton.Add_Click({ Refresh-List })
[void]$toolbar.Controls.Add($refreshButton)

$removeButton = New-Object Windows.Forms.Button
$removeButton.Text = "Remove"
$removeButton.Size = New-Object Drawing.Size(92, 32)
$removeButton.Add_Click({ Remove-SelectedFiles })
[void]$toolbar.Controls.Add($removeButton)

$clearButton = New-Object Windows.Forms.Button
$clearButton.Text = "Clear All"
$clearButton.Size = New-Object Drawing.Size(92, 32)
$clearButton.Add_Click({
    $confirm = [Windows.Forms.MessageBox]::Show(
        "Remove all queued files from the inbox?",
        "Clear queued files",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -eq [Windows.Forms.DialogResult]::Yes) {
        foreach ($file in $script:ReadyFiles) {
            if (Test-Path -LiteralPath $file.FullName -PathType Leaf) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
        }
        Refresh-List
    }
})
[void]$toolbar.Controls.Add($clearButton)

$openScannedButton = New-Object Windows.Forms.Button
$openScannedButton.Text = "Scanned"
$openScannedButton.Size = New-Object Drawing.Size(92, 32)
$openScannedButton.Add_Click({ Start-Process explorer.exe "`"$(Join-Path $script:InboxPath "Scanned")`"" })
[void]$toolbar.Controls.Add($openScannedButton)

$listPanel = New-Object Windows.Forms.Panel
$listPanel.Dock = [Windows.Forms.DockStyle]::Fill
$listPanel.Padding = New-Object Windows.Forms.Padding(18, 0, 18, 0)
$listPanel.BackColor = $form.BackColor
$layout.Controls.Add($listPanel, 0, 3)

$list = New-Object Windows.Forms.ListView
$list.Dock = [Windows.Forms.DockStyle]::Fill
$list.View = [Windows.Forms.View]::Details
$list.FullRowSelect = $true
$list.GridLines = $false
$list.HideSelection = $false
$list.MultiSelect = $true
$list.AllowDrop = $true
$list.BackColor = [Drawing.Color]::White
$list.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
[void]$list.Columns.Add("Name", 430)
[void]$list.Columns.Add("Size", 100)
[void]$list.Columns.Add("Modified", 180)
$list.Add_DoubleClick({ Open-SelectedFile })
$list.Add_SelectedIndexChanged({ $removeButton.Enabled = $list.SelectedItems.Count -gt 0 })
$listPanel.Controls.Add($list)

$statusPanel = New-Object Windows.Forms.Panel
$statusPanel.Dock = [Windows.Forms.DockStyle]::Fill
$statusPanel.Padding = New-Object Windows.Forms.Padding(18, 7, 18, 6)
$statusPanel.BackColor = $form.BackColor
$layout.Controls.Add($statusPanel, 0, 4)

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Dock = [Windows.Forms.DockStyle]::Fill
$statusLabel.ForeColor = [Drawing.Color]::FromArgb(51, 65, 85)
$statusPanel.Controls.Add($statusLabel)

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
    } elseif ($_.KeyCode -eq [Windows.Forms.Keys]::Delete -and $list.SelectedItems.Count -gt 0) {
        Remove-SelectedFiles
    } elseif ($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::O) {
        Open-Inbox
    }
})

$form.Add_Resize({
    $scanButton.Left = [Math]::Max(520, $header.ClientSize.Width - $scanButton.Width - 22)
    Resize-ListColumns
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
