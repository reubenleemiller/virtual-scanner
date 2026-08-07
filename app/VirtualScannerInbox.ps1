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

function Get-InboxPath {
    $path = [Environment]::GetEnvironmentVariable("VIRTUAL_SCANNER_INBOX", "Machine")
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $env:PUBLIC "Documents\VirtualScannerInbox"
    }
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $path "Scanned") | Out-Null
    return $path
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
    $selected = @{}
    foreach ($item in $list.SelectedItems) {
        $selected[$item.Text] = $true
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
            if ($selected.ContainsKey($file.Name)) {
                $item.Selected = $true
            }
            [void]$list.Items.Add($item)
        }
    } finally {
        $list.EndUpdate()
    }

    $count = $script:ReadyFiles.Count
    $scanButton.Enabled = $count -gt 0
    $clearButton.Enabled = $count -gt 0
    if ($dropLabel -and $list) {
        $dropLabel.Visible = $count -eq 0
        $list.Visible = $count -gt 0
    }
    if ($count -eq 0) {
        Set-Status "Drop files here or choose Add Files."
    } elseif ($count -eq 1) {
        Set-Status "1 file ready to scan."
    } else {
        Set-Status "$count files ready to scan in name order."
    }
}

function Queue-Refresh {
    $refreshTimer.Stop()
    $refreshTimer.Start()
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

function Open-SelectedOrInbox {
    if ($list.SelectedItems.Count -gt 0) {
        Start-Process explorer.exe "/select,`"$($list.SelectedItems[0].Tag)`""
    } else {
        Start-Process explorer.exe "`"$script:InboxPath`""
    }
}

$script:InboxPath = Get-InboxPath

[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = "Virtual Scanner Inbox"
$form.Icon = [Drawing.SystemIcons]::Application
$form.Size = New-Object Drawing.Size(760, 500)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object Drawing.Size(640, 420)
$form.BackColor = [Drawing.Color]::FromArgb(246, 248, 251)
$form.Font = New-Object Drawing.Font("Segoe UI", 9)
$form.AllowDrop = $true

$header = New-Object Windows.Forms.Panel
$header.Dock = [Windows.Forms.DockStyle]::Top
$header.Height = 98
$header.BackColor = [Drawing.Color]::FromArgb(29, 78, 216)
$form.Controls.Add($header)

$titleLabel = New-Object Windows.Forms.Label
$titleLabel.Text = "Virtual Scanner Inbox"
$titleLabel.ForeColor = [Drawing.Color]::White
$titleLabel.Font = New-Object Drawing.Font("Segoe UI Semibold", 16)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object Drawing.Point(22, 16)
$header.Controls.Add($titleLabel)

$subtitleLabel = New-Object Windows.Forms.Label
$subtitleLabel.Text = "Add images or PDFs, then start the scan."
$subtitleLabel.ForeColor = [Drawing.Color]::FromArgb(219, 234, 254)
$subtitleLabel.AutoSize = $true
$subtitleLabel.Location = New-Object Drawing.Point(24, 50)
$header.Controls.Add($subtitleLabel)

$scanButton = New-Object Windows.Forms.Button
$scanButton.Text = "Scan"
$scanButton.Font = New-Object Drawing.Font("Segoe UI Semibold", 10)
$scanButton.Size = New-Object Drawing.Size(132, 40)
$scanButton.Anchor = [Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right
$scanButton.Location = New-Object Drawing.Point(602, 28)
$scanButton.FlatStyle = [Windows.Forms.FlatStyle]::Flat
$scanButton.BackColor = [Drawing.Color]::White
$scanButton.ForeColor = [Drawing.Color]::FromArgb(29, 78, 216)
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

$pathPanel = New-Object Windows.Forms.Panel
$pathPanel.Dock = [Windows.Forms.DockStyle]::Top
$pathPanel.Height = 58
$pathPanel.Padding = New-Object Windows.Forms.Padding(18, 14, 18, 10)
$pathPanel.BackColor = $form.BackColor
$form.Controls.Add($pathPanel)

$pathBox = New-Object Windows.Forms.TextBox
$pathBox.Dock = [Windows.Forms.DockStyle]::Fill
$pathBox.ReadOnly = $true
$pathBox.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
$pathBox.Text = $script:InboxPath
$pathPanel.Controls.Add($pathBox)

$openButton = New-Object Windows.Forms.Button
$openButton.Text = "Open"
$openButton.Dock = [Windows.Forms.DockStyle]::Right
$openButton.Width = 86
$openButton.Margin = New-Object Windows.Forms.Padding(8, 0, 0, 0)
$openButton.Add_Click({ Open-SelectedOrInbox })
$pathPanel.Controls.Add($openButton)

$toolbar = New-Object Windows.Forms.FlowLayoutPanel
$toolbar.Dock = [Windows.Forms.DockStyle]::Top
$toolbar.Height = 48
$toolbar.Padding = New-Object Windows.Forms.Padding(14, 4, 14, 6)
$toolbar.BackColor = $form.BackColor
$form.Controls.Add($toolbar)

$addButton = New-Object Windows.Forms.Button
$addButton.Text = "Add Files..."
$addButton.Size = New-Object Drawing.Size(104, 32)
$addButton.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = "Add scanner files"
    $dialog.Filter = "Scanner files|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.pdf|All files|*.*"
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
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
$removeButton.Add_Click({
    foreach ($item in @($list.SelectedItems)) {
        Remove-Item -LiteralPath $item.Tag -Force
    }
    Refresh-List
})
[void]$toolbar.Controls.Add($removeButton)

$clearButton = New-Object Windows.Forms.Button
$clearButton.Text = "Clear All"
$clearButton.Size = New-Object Drawing.Size(92, 32)
$clearButton.Add_Click({
    $confirm = [Windows.Forms.MessageBox]::Show(
        "Remove all ready-to-scan files from the inbox?",
        "Clear ready files",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -eq [Windows.Forms.DialogResult]::Yes) {
        foreach ($file in $script:ReadyFiles) {
            Remove-Item -LiteralPath $file.FullName -Force
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

$content = New-Object Windows.Forms.Panel
$content.Dock = [Windows.Forms.DockStyle]::Fill
$content.Padding = New-Object Windows.Forms.Padding(18, 0, 18, 0)
$content.BackColor = $form.BackColor
$form.Controls.Add($content)

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
[void]$list.Columns.Add("Name", 380)
[void]$list.Columns.Add("Size", 90)
[void]$list.Columns.Add("Modified", 180)
$list.Add_DoubleClick({ Open-SelectedOrInbox })
$list.Add_SelectedIndexChanged({ $removeButton.Enabled = $list.SelectedItems.Count -gt 0 })
$content.Controls.Add($list)

$dropLabel = New-Object Windows.Forms.Label
$dropLabel.Text = "Drop PNG, JPG, TIFF, BMP, or PDF files here"
$dropLabel.Dock = [Windows.Forms.DockStyle]::Fill
$dropLabel.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
$dropLabel.ForeColor = [Drawing.Color]::FromArgb(100, 116, 139)
$dropLabel.BackColor = [Drawing.Color]::White
$dropLabel.Visible = $false
$content.Controls.Add($dropLabel)

$statusPanel = New-Object Windows.Forms.Panel
$statusPanel.Dock = [Windows.Forms.DockStyle]::Bottom
$statusPanel.Height = 40
$statusPanel.Padding = New-Object Windows.Forms.Padding(18, 8, 18, 8)
$statusPanel.BackColor = $form.BackColor
$form.Controls.Add($statusPanel)

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Dock = [Windows.Forms.DockStyle]::Fill
$statusLabel.ForeColor = [Drawing.Color]::FromArgb(51, 65, 85)
$statusPanel.Controls.Add($statusLabel)

$refreshTimer = New-Object Windows.Forms.Timer
$refreshTimer.Interval = 250
$refreshTimer.Add_Tick({
    $refreshTimer.Stop()
    Refresh-List
})

$watcher = New-Object IO.FileSystemWatcher
$watcher.Path = $script:InboxPath
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [IO.NotifyFilters]"FileName, LastWrite, Size"
$queueRefreshOnUi = {
    if ($form -and -not $form.IsDisposed) {
        [void]$form.BeginInvoke([Action]{ Queue-Refresh })
    }
}
$watcher.Add_Created($queueRefreshOnUi)
$watcher.Add_Deleted($queueRefreshOnUi)
$watcher.Add_Renamed($queueRefreshOnUi)
$watcher.Add_Changed($queueRefreshOnUi)

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
$dropLabel.Add_DragEnter($dragHandler)
$dropLabel.Add_DragDrop($dropHandler)

$form.Add_KeyDown({
    if ($_.KeyCode -eq [Windows.Forms.Keys]::F5) {
        Refresh-List
    } elseif ($_.KeyCode -eq [Windows.Forms.Keys]::Delete -and $list.SelectedItems.Count -gt 0) {
        foreach ($item in @($list.SelectedItems)) {
            Remove-Item -LiteralPath $item.Tag -Force
        }
        Refresh-List
    } elseif ($_.Control -and $_.KeyCode -eq [Windows.Forms.Keys]::O) {
        Open-SelectedOrInbox
    }
})
$form.KeyPreview = $true

$form.Add_Resize({
    $scanButton.Left = $header.ClientSize.Width - $scanButton.Width - 26
})

$form.Add_Shown({
    $removeButton.Enabled = $false
    Refresh-List
})

try {
    [void]$form.ShowDialog()
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message, "Virtual Scanner Inbox Error")
} finally {
    if ($watcher) {
        $watcher.Dispose()
    }
}
