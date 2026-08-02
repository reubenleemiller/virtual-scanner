!ifndef VERSION
!define VERSION "1.5.1"
!endif
!ifndef SOURCE_DIR
!define SOURCE_DIR "."
!endif
!ifndef ARCH
!define ARCH "x64"
!endif
!include WinMessages.nsh

!define APP_NAME "Virtual Scanner"
!define COMPANY_NAME "Codex"
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

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${COMPANY_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} ${ARCH} Installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

Page directory
Page instfiles

UninstPage uninstConfirm
UninstPage instfiles

Section "Install"
    ReadEnvStr $0 "PUBLIC"
    StrCpy $1 "$0\Documents\VirtualScannerInbox"
    CreateDirectory "$1"

    SetOutPath "$INSTDIR"
    File "${SOURCE_DIR}/dist/${ARCH}/VirtualScanner.ds"
    File "${SOURCE_DIR}/app/VirtualScannerInbox.ps1"
    File "${SOURCE_DIR}/app/VirtualScannerInbox.vbs"
    File "${SOURCE_DIR}/app/VirtualScanner.ico"
    CreateShortCut "$SMPROGRAMS\Virtual Scanner Inbox.lnk" "$WINDIR\System32\wscript.exe" "$\"$INSTDIR\VirtualScannerInbox.vbs$\"" "$INSTDIR\VirtualScanner.ico" 0
    CreateShortCut "$DESKTOP\Virtual Scanner Inbox.lnk" "$WINDIR\System32\wscript.exe" "$\"$INSTDIR\VirtualScannerInbox.vbs$\"" "$INSTDIR\VirtualScanner.ico" 0

    WriteUninstaller "$INSTDIR\Uninstall.exe"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME} ${ARCH}"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "Publisher" "${COMPANY_NAME}"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${UNINSTALL_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
    WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${UNINSTALL_KEY}" "NoRepair" 1
    WriteRegStr HKLM "${ENV_KEY}" "VIRTUAL_SCANNER_INBOX" "$1"
    SendMessage ${HWND_BROADCAST} ${WM_SETTINGCHANGE} 0 "STR:Environment" /TIMEOUT=5000
SectionEnd

Section "Uninstall"
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
