!ifndef VERSION
!define VERSION "1.5.3"
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
!define GHOSTSCRIPT_EXE "gswin32c.exe"
!else
!define TWAIN_FOLDER "twain_64"
!define GHOSTSCRIPT_EXE "gswin64c.exe"
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
!insertmacro MUI_PAGE_LICENSE "${SOURCE_DIR}/installer/license-agreement.txt"
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
    File "${SOURCE_DIR}/app/VirtualScanner-icon.png"
    File "${SOURCE_DIR}/LICENSE"
    File "${SOURCE_DIR}/NOTICE"
    File "${SOURCE_DIR}/THIRD_PARTY_NOTICES.md"
    CreateDirectory "$INSTDIR\Redist"
    SetOutPath "$INSTDIR\Redist"
    File "${SOURCE_DIR}/dist/vcredist-${ARCH}/vc_redist.exe"
    ExecWait '"$INSTDIR\Redist\vc_redist.exe" /install /quiet /norestart'
    CreateDirectory "$INSTDIR\Ghostscript"
    SetOutPath "$INSTDIR\Ghostscript"
    File /r "${SOURCE_DIR}/dist/ghostscript-${ARCH}\*.*"
    SetOutPath "$INSTDIR"
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
    WriteRegStr HKLM "${ENV_KEY}" "VIRTUAL_SCANNER_GHOSTSCRIPT" "$INSTDIR\Ghostscript\bin\${GHOSTSCRIPT_EXE}"
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
    Delete "$INSTDIR\VirtualScanner-icon.png"
    Delete "$INSTDIR\VirtualScannerInbox.vbs"
    Delete "$INSTDIR\VirtualScannerInbox.ps1"
    Delete "$INSTDIR\VirtualScanner.ds"
    Delete "$INSTDIR\LICENSE"
    Delete "$INSTDIR\NOTICE"
    Delete "$INSTDIR\THIRD_PARTY_NOTICES.md"
    Delete "$INSTDIR\Uninstall.exe"
    Delete "$INSTDIR\Redist\vc_redist.exe"
    RMDir "$INSTDIR\Redist"
    RMDir /r "$INSTDIR\Ghostscript"
    RMDir "$INSTDIR"
    DeleteRegKey HKLM "${UNINSTALL_KEY}"
    DeleteRegValue HKLM "${ENV_KEY}" "VIRTUAL_SCANNER_INBOX"
    DeleteRegValue HKLM "${ENV_KEY}" "VIRTUAL_SCANNER_GHOSTSCRIPT"
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd
