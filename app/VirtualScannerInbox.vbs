Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptPath = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "VirtualScannerInbox.ps1")
command = "powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34)
shell.Run command, 0, False
