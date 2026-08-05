!ifndef VERSION
!define VERSION "1.5.2"
!endif
!ifndef SOURCE_DIR
!define SOURCE_DIR "."
!endif
!ifndef ARCH
!define ARCH "x64"
!endif
!include WinMessages.nsh
!include LogicLib.nsh
!include MUI2.nsh
!include x64.nsh

!define APP_NAME "Virtual Scanner"
!define COMPANY_NAME "Reuben Miller"
!define STARTMENU_FOLDER "Virtual Scanner"
!if "${ARCH}" == "x86"
!define TWAIN_FOLDER "twain_32"
!else
!define TWAIN_FOLDER "twain_64"
!endif
!define INSTALL_DIR "$WINDIR\${TWAIN_FOLDER}\VirtualScanner-${ARCH}"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\VirtualScanner-${ARCH}"
!define ENV_KEY "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"

Name "${APP_NAME} ${ARCH}"
OutFile "${SOURCE_DIR}/dist/VirtualScanner-${VERSION}-${ARCH}-setup.exe"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel admin
Unicode true
Icon "${SOURCE_DIR}/app/VirtualScanner.ico"
UninstallIcon "${SOURCE_DIR}/app/VirtualScanner.ico"
BrandingText "${APP_NAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${COMPANY_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} ${ARCH} Installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (c) Reuben Miller"
VIAddVersionKey "OriginalFilename" "VirtualScanner-${VERSION}-${ARCH}-setup.exe"
VIAddVersionKey "ProductVersion" "${VERSION}"

!define MUI_ICON "${SOURCE_DIR}/app/VirtualScanner.ico"
!define MUI_UNICON "${SOURCE_DIR}/app/VirtualScanner.ico"
!define MUI_ABORTWARNING
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP "${SOURCE_DIR}/installer/assets/header.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP "${SOURCE_DIR}/installer/assets/welcome.bmp"
!define MUI_WELCOMEPAGE_TITLE "Install ${APP_NAME} ${ARCH}"
!define MUI_WELCOMEPAGE_TEXT "Setup will install ${APP_NAME}, create an inbox folder for scan files, add desktop and Start Menu shortcuts, and check for Ghostscript so PDF files can be scanned."
!insertmacro MUI_PAGE_WELCOME
!define MUI_LICENSEPAGE_CHECKBOX
!insertmacro MUI_PAGE_LICENSE "${SOURCE_DIR}/LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "${APP_NAME} is ready"
!define MUI_FINISHPAGE_TEXT "The virtual scanner data source and inbox shortcut were installed successfully."
!define MUI_FINISHPAGE_RUN "$WINDIR\System32\wscript.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open Virtual Scanner Inbox"
!define MUI_FINISHPAGE_RUN_PARAMETERS "$\"$INSTDIR\VirtualScannerInbox.vbs$\""
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section -Prerequisites
    Call IsGhostscriptInstalled
    Pop $0
    ${If} $0 == "1"
        DetailPrint "Ghostscript found."
    ${Else}
        DetailPrint "Ghostscript was not found."
        MessageBox MB_YESNO|MB_ICONQUESTION "Ghostscript is required for scanning PDF files. Download and run the official Ghostscript installer now?" IDYES install_ghostscript IDNO skip_ghostscript

        install_ghostscript:
            InitPluginsDir
            File /oname=$PLUGINSDIR\install-ghostscript.ps1 "${SOURCE_DIR}/installer/install-ghostscript.ps1"
            DetailPrint "Downloading and installing Ghostscript..."
            nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PLUGINSDIR\install-ghostscript.ps1"'
            Pop $0
            Call IsGhostscriptInstalled
            Pop $1
            ${If} $1 == "1"
                DetailPrint "Ghostscript installed."
            ${Else}
                DetailPrint "Ghostscript installation exited with code $0."
                MessageBox MB_OK|MB_ICONEXCLAMATION "Ghostscript could not be installed. Virtual Scanner will still be installed, but PDF scanning will require Ghostscript to be installed later."
            ${EndIf}
            Goto done_ghostscript

        skip_ghostscript:
            DetailPrint "Ghostscript installation skipped. PDF scanning will be unavailable until Ghostscript is installed."
            MessageBox MB_OK|MB_ICONINFORMATION "PDF scanning will be unavailable until Ghostscript is installed."

        done_ghostscript:
    ${EndIf}
SectionEnd

Section "Virtual Scanner" SEC_APP
    SectionIn RO
    ReadEnvStr $0 "PUBLIC"
    StrCpy $1 "$0\Documents\VirtualScannerInbox"
    CreateDirectory "$1"
    CreateDirectory "$1\Scanned"

    SetOutPath "$INSTDIR"
    File "${SOURCE_DIR}/dist/${ARCH}/VirtualScanner.ds"
    File "${SOURCE_DIR}/app/VirtualScannerInbox.ps1"
    File "${SOURCE_DIR}/app/VirtualScannerInbox.vbs"
    File "${SOURCE_DIR}/app/VirtualScanner.ico"
    CreateDirectory "$SMPROGRAMS\${STARTMENU_FOLDER}"
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateShortCut "$SMPROGRAMS\${STARTMENU_FOLDER}\Virtual Scanner Inbox.lnk" "$WINDIR\System32\wscript.exe" "$\"$INSTDIR\VirtualScannerInbox.vbs$\"" "$INSTDIR\VirtualScanner.ico" 0
    CreateShortCut "$SMPROGRAMS\${STARTMENU_FOLDER}\Uninstall Virtual Scanner.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\VirtualScanner.ico" 0
    CreateShortCut "$DESKTOP\Virtual Scanner Inbox.lnk" "$WINDIR\System32\wscript.exe" "$\"$INSTDIR\VirtualScannerInbox.vbs$\"" "$INSTDIR\VirtualScanner.ico" 0

    WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME} ${ARCH}"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${COMPANY_NAME}"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\VirtualScanner.ico"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
    WriteRegStr HKLM "${ENV_KEY}" "VIRTUAL_SCANNER_INBOX" "$1"
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd

Section "Uninstall"
    Delete "$SMPROGRAMS\${STARTMENU_FOLDER}\Uninstall Virtual Scanner.lnk"
    Delete "$SMPROGRAMS\${STARTMENU_FOLDER}\Virtual Scanner Inbox.lnk"
    RMDir "$SMPROGRAMS\${STARTMENU_FOLDER}"
    Delete "$SMPROGRAMS\Virtual Scanner Inbox.lnk"
    Delete "$DESKTOP\Virtual Scanner Inbox.lnk"
    Delete "$SMPROGRAMS\UniTwain Virtual Scanner Inbox.lnk"
    Delete "$DESKTOP\UniTwain Virtual Scanner Inbox.lnk"
    Delete "$INSTDIR\VirtualScanner.ico"
    Delete "$INSTDIR\VirtualScannerInbox.vbs"
    Delete "$INSTDIR\VirtualScannerInbox.ps1"
    Delete "$INSTDIR\VirtualScanner.ds"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKLM "${UNINSTALL_KEY}"
    DeleteRegValue HKLM "${ENV_KEY}" "VIRTUAL_SCANNER_INBOX"
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd

Function IsGhostscriptInstalled
    Push $0
    Push $1

    ReadEnvStr $0 "VIRTUAL_SCANNER_GHOSTSCRIPT"
    ${If} $0 != ""
    ${AndIf} ${FileExists} "$0"
        StrCpy $0 "1"
        Goto done
    ${EndIf}

    nsExec::ExecToStack '"$SYSDIR\where.exe" gswin64c.exe'
    Pop $1
    Pop $0
    ${If} $1 == "0"
        StrCpy $0 "1"
        Goto done
    ${EndIf}

    nsExec::ExecToStack '"$SYSDIR\where.exe" gswin32c.exe'
    Pop $1
    Pop $0
    ${If} $1 == "0"
        StrCpy $0 "1"
        Goto done
    ${EndIf}

    ${If} ${RunningX64}
        ${If} ${FileExists} "$PROGRAMFILES64\gs\gs*\bin\gswin64c.exe"
            StrCpy $0 "1"
            Goto done
        ${EndIf}
    ${EndIf}

    ${If} ${FileExists} "$PROGRAMFILES32\gs\gs*\bin\gswin32c.exe"
    ${OrIf} ${FileExists} "$PROGRAMFILES32\gs\gs*\bin\gswin64c.exe"
        StrCpy $0 "1"
        Goto done
    ${EndIf}

    ${If} ${FileExists} "$PROGRAMFILES\gs\gs*\bin\gswin64c.exe"
    ${OrIf} ${FileExists} "$PROGRAMFILES\gs\gs*\bin\gswin32c.exe"
        StrCpy $0 "1"
    ${Else}
        StrCpy $0 "0"
    ${EndIf}

    done:
    Pop $1
    Exch $0
FunctionEnd
