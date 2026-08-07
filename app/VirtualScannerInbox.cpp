#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <commdlg.h>
#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <string>
#include <vector>

#define IDC_PATH 1001
#define IDC_OPEN 1002
#define IDC_ADD 1003
#define IDC_CLEAR 1004
#define IDC_REFRESH 1005
#define IDC_REMOVE 1006
#define IDC_SCAN 1007
#define IDC_LIST 1008
#define IDC_STATUS 1009

static HINSTANCE g_instance;
static HWND g_main;
static HWND g_path;
static HWND g_list;
static HWND g_status;
static HWND g_clear;
static HWND g_remove;
static HWND g_scan;
static std::wstring g_inbox;

static std::wstring join_path(const std::wstring &base, const std::wstring &name)
{
    if (base.empty() || base.back() == L'\\') {
        return base + name;
    }
    return base + L"\\" + name;
}

static std::wstring get_inbox_path()
{
    wchar_t configured[MAX_PATH * 2] = {};
    DWORD len = GetEnvironmentVariableW(L"VIRTUAL_SCANNER_INBOX", configured, ARRAYSIZE(configured));
    std::wstring path;
    if (len > 0 && len < ARRAYSIZE(configured)) {
        path = configured;
    } else {
        wchar_t public_path[MAX_PATH] = {};
        len = GetEnvironmentVariableW(L"PUBLIC", public_path, ARRAYSIZE(public_path));
        if (len > 0 && len < ARRAYSIZE(public_path)) {
            path = join_path(public_path, L"Documents\\VirtualScannerInbox");
        } else {
            path = L"C:\\Users\\Public\\Documents\\VirtualScannerInbox";
        }
    }
    CreateDirectoryW(path.c_str(), nullptr);
    CreateDirectoryW(join_path(path, L"Scanned").c_str(), nullptr);
    return path;
}

static std::wstring lower_ext(const std::wstring &path)
{
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos) {
        return L"";
    }
    std::wstring ext = path.substr(dot);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](wchar_t ch) {
        return (wchar_t)towlower(ch);
    });
    return ext;
}

static bool supported_file(const std::wstring &path)
{
    std::wstring ext = lower_ext(path);
    return ext == L".png" || ext == L".jpg" || ext == L".jpeg" ||
           ext == L".bmp" || ext == L".tif" || ext == L".tiff" || ext == L".pdf";
}

static std::wstring file_name(const std::wstring &path)
{
    size_t slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

static bool copy_with_unique_name(const std::wstring &source)
{
    if (!supported_file(source)) {
        return false;
    }

    std::wstring name = file_name(source);
    std::wstring target = join_path(g_inbox, name);
    if (GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES) {
        return CopyFileW(source.c_str(), target.c_str(), TRUE) != FALSE;
    }

    std::wstring base = name;
    std::wstring ext;
    size_t dot = name.find_last_of(L'.');
    if (dot != std::wstring::npos) {
        base = name.substr(0, dot);
        ext = name.substr(dot);
    }

    SYSTEMTIME now;
    GetLocalTime(&now);
    wchar_t stamp[32] = {};
    swprintf_s(stamp, L"%04u%02u%02u-%02u%02u%02u",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond);

    for (int index = 1; index < 10000; ++index) {
        wchar_t suffix[48] = {};
        swprintf_s(suffix, L"-%s-%d%s", stamp, index, ext.c_str());
        target = join_path(g_inbox, base + suffix);
        if (GetFileAttributesW(target.c_str()) == INVALID_FILE_ATTRIBUTES) {
            return CopyFileW(source.c_str(), target.c_str(), TRUE) != FALSE;
        }
    }
    return false;
}

static std::vector<std::wstring> ready_files()
{
    std::vector<std::wstring> files;
    WIN32_FIND_DATAW data = {};
    HANDLE find = FindFirstFileW(join_path(g_inbox, L"*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        return files;
    }
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 && supported_file(data.cFileName)) {
            files.emplace_back(data.cFileName);
        }
    } while (FindNextFileW(find, &data));
    FindClose(find);
    std::sort(files.begin(), files.end());
    return files;
}

static std::wstring selected_file()
{
    int index = (int)SendMessageW(g_list, LB_GETCURSEL, 0, 0);
    if (index == LB_ERR) {
        return L"";
    }
    wchar_t text[MAX_PATH * 2] = {};
    SendMessageW(g_list, LB_GETTEXT, index, (LPARAM)text);
    std::wstring display = text;
    size_t sep = display.find(L"    ");
    return join_path(g_inbox, sep == std::wstring::npos ? display : display.substr(0, sep));
}

static void refresh_list()
{
    std::vector<std::wstring> files = ready_files();
    SendMessageW(g_list, WM_SETREDRAW, FALSE, 0);
    SendMessageW(g_list, LB_RESETCONTENT, 0, 0);
    for (const auto &name : files) {
        WIN32_FILE_ATTRIBUTE_DATA attr = {};
        GetFileAttributesExW(join_path(g_inbox, name).c_str(), GetFileExInfoStandard, &attr);
        ULARGE_INTEGER size = {};
        size.LowPart = attr.nFileSizeLow;
        size.HighPart = attr.nFileSizeHigh;
        unsigned long long kb = std::max<unsigned long long>(1, (size.QuadPart + 1023) / 1024);
        std::wstring row = name + L"    " + std::to_wstring(kb) + L" KB";
        SendMessageW(g_list, LB_ADDSTRING, 0, (LPARAM)row.c_str());
    }
    SendMessageW(g_list, WM_SETREDRAW, TRUE, 0);
    InvalidateRect(g_list, nullptr, TRUE);

    EnableWindow(g_clear, !files.empty());
    EnableWindow(g_remove, SendMessageW(g_list, LB_GETCURSEL, 0, 0) != LB_ERR);
    std::wstring status = std::to_wstring(files.size()) + (files.size() == 1 ? L" file ready" : L" files ready");
    SetWindowTextW(g_status, status.c_str());
}

static void add_files(const std::vector<std::wstring> &paths)
{
    int added = 0;
    for (const auto &path : paths) {
        DWORD attr = GetFileAttributesW(path.c_str());
        if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0 && copy_with_unique_name(path)) {
            ++added;
        }
    }
    refresh_list();
    if (added == 0) {
        SetWindowTextW(g_status, L"No supported files were added");
    }
}

static void choose_files()
{
    std::vector<wchar_t> buffer(65536);
    OPENFILENAMEW ofn = {};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_main;
    ofn.lpstrFilter = L"Scanner files\0*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.pdf\0All files\0*.*\0";
    ofn.lpstrFile = buffer.data();
    ofn.nMaxFile = (DWORD)buffer.size();
    ofn.Flags = OFN_ALLOWMULTISELECT | OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrTitle = L"Add scanner files";
    if (!GetOpenFileNameW(&ofn)) {
        return;
    }

    std::vector<std::wstring> paths;
    wchar_t *cursor = buffer.data();
    std::wstring first = cursor;
    cursor += first.size() + 1;
    if (*cursor == L'\0') {
        paths.push_back(first);
    } else {
        while (*cursor) {
            paths.push_back(join_path(first, cursor));
            cursor += wcslen(cursor) + 1;
        }
    }
    add_files(paths);
}

static void layout(HWND hwnd)
{
    RECT rc;
    GetClientRect(hwnd, &rc);
    int width = rc.right - rc.left;
    int height = rc.bottom - rc.top;
    int margin = 16;
    int top = 13;
    MoveWindow(GetDlgItem(hwnd, IDC_PATH), margin, 38, width - 150, 24, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_OPEN), width - 126, 36, 110, 28, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_ADD), margin, 76, 104, 30, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_CLEAR), 128, 76, 104, 30, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_REFRESH), 240, 76, 90, 30, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_REMOVE), 338, 76, 90, 30, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_SCAN), width - 176, 76, 160, 30, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_LIST), margin, 118, width - 32, height - 176, TRUE);
    MoveWindow(GetDlgItem(hwnd, IDC_STATUS), margin, height - 38, width - 32, 24, TRUE);
    (void)top;
}

static void signal_scan_ready()
{
    HANDLE file = CreateFileW(join_path(g_inbox, L".scan-now").c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
        SYSTEMTIME now;
        GetSystemTime(&now);
        char stamp[64] = {};
        sprintf_s(stamp, "%04u-%02u-%02uT%02u:%02u:%02uZ",
            now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond);
        DWORD written = 0;
        WriteFile(file, stamp, (DWORD)strlen(stamp), &written, nullptr);
        CloseHandle(file);
    }
}

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg) {
    case WM_CREATE: {
        HICON icon = LoadIconW(g_instance, MAKEINTRESOURCEW(1));
        SendMessageW(hwnd, WM_SETICON, ICON_BIG, (LPARAM)icon);
        SendMessageW(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)icon);
        DragAcceptFiles(hwnd, TRUE);

        HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
        HWND title = CreateWindowW(L"STATIC", L"Virtual Scanner Inbox", WS_CHILD | WS_VISIBLE,
            48, 13, 260, 22, hwnd, nullptr, g_instance, nullptr);
        SendMessageW(title, WM_SETFONT, (WPARAM)font, TRUE);

        HWND pic = CreateWindowW(L"STATIC", nullptr, WS_CHILD | WS_VISIBLE | SS_ICON,
            16, 12, 24, 24, hwnd, nullptr, g_instance, nullptr);
        SendMessageW(pic, STM_SETICON, (WPARAM)icon, 0);

        g_path = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", g_inbox.c_str(), WS_CHILD | WS_VISIBLE | ES_READONLY,
            16, 38, 470, 24, hwnd, (HMENU)IDC_PATH, g_instance, nullptr);
        CreateWindowW(L"BUTTON", L"Open Folder", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            494, 36, 110, 28, hwnd, (HMENU)IDC_OPEN, g_instance, nullptr);
        CreateWindowW(L"BUTTON", L"Add Files...", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            16, 76, 104, 30, hwnd, (HMENU)IDC_ADD, g_instance, nullptr);
        g_clear = CreateWindowW(L"BUTTON", L"Clear Ready", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            128, 76, 104, 30, hwnd, (HMENU)IDC_CLEAR, g_instance, nullptr);
        CreateWindowW(L"BUTTON", L"Refresh", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            240, 76, 90, 30, hwnd, (HMENU)IDC_REFRESH, g_instance, nullptr);
        g_remove = CreateWindowW(L"BUTTON", L"Remove", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            338, 76, 90, 30, hwnd, (HMENU)IDC_REMOVE, g_instance, nullptr);
        g_scan = CreateWindowW(L"BUTTON", L"Scan", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
            430, 76, 160, 30, hwnd, (HMENU)IDC_SCAN, g_instance, nullptr);
        g_list = CreateWindowExW(WS_EX_CLIENTEDGE, L"LISTBOX", nullptr,
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_HSCROLL | LBS_NOTIFY,
            16, 118, 573, 210, hwnd, (HMENU)IDC_LIST, g_instance, nullptr);
        g_status = CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE,
            16, 342, 573, 24, hwnd, (HMENU)IDC_STATUS, g_instance, nullptr);

        HWND controls[] = { title, g_path, GetDlgItem(hwnd, IDC_OPEN), GetDlgItem(hwnd, IDC_ADD),
            g_clear, GetDlgItem(hwnd, IDC_REFRESH), g_remove, g_scan, g_list, g_status };
        for (HWND control : controls) {
            SendMessageW(control, WM_SETFONT, (WPARAM)font, TRUE);
        }
        refresh_list();
        layout(hwnd);
        return 0;
    }
    case WM_SIZE:
        layout(hwnd);
        return 0;
    case WM_DROPFILES: {
        HDROP drop = (HDROP)wparam;
        UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
        std::vector<std::wstring> paths;
        for (UINT i = 0; i < count; ++i) {
            UINT len = DragQueryFileW(drop, i, nullptr, 0);
            std::wstring path(len + 1, L'\0');
            DragQueryFileW(drop, i, path.data(), len + 1);
            path.resize(len);
            paths.push_back(path);
        }
        DragFinish(drop);
        add_files(paths);
        return 0;
    }
    case WM_COMMAND:
        switch (LOWORD(wparam)) {
        case IDC_OPEN:
            ShellExecuteW(hwnd, L"open", g_inbox.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            return 0;
        case IDC_ADD:
            choose_files();
            return 0;
        case IDC_CLEAR:
            if (MessageBoxW(hwnd, L"Remove all ready-to-scan files from the inbox?", L"Clear ready files", MB_YESNO | MB_ICONQUESTION) == IDYES) {
                for (const auto &name : ready_files()) {
                    DeleteFileW(join_path(g_inbox, name).c_str());
                }
                refresh_list();
            }
            return 0;
        case IDC_REFRESH:
            refresh_list();
            return 0;
        case IDC_REMOVE: {
            std::wstring path = selected_file();
            if (!path.empty()) {
                DeleteFileW(path.c_str());
                refresh_list();
            }
            return 0;
        }
        case IDC_SCAN:
            refresh_list();
            if (SendMessageW(g_list, LB_GETCOUNT, 0, 0) == 0) {
                MessageBoxW(hwnd, L"Add at least one image or PDF before scanning.", L"Virtual Scanner Inbox", MB_OK | MB_ICONINFORMATION);
                return 0;
            }
            signal_scan_ready();
            DestroyWindow(hwnd);
            return 0;
        case IDC_LIST:
            if (HIWORD(wparam) == LBN_SELCHANGE) {
                EnableWindow(g_remove, SendMessageW(g_list, LB_GETCURSEL, 0, 0) != LB_ERR);
            } else if (HIWORD(wparam) == LBN_DBLCLK) {
                std::wstring path = selected_file();
                if (!path.empty()) {
                    std::wstring args = L"/select,\"" + path + L"\"";
                    ShellExecuteW(hwnd, L"open", L"explorer.exe", args.c_str(), nullptr, SW_SHOWNORMAL);
                }
            }
            return 0;
        }
        break;
    case WM_DRAWITEM: {
        DRAWITEMSTRUCT *item = (DRAWITEMSTRUCT *)lparam;
        if (item && item->CtlID == IDC_SCAN) {
            bool pressed = (item->itemState & ODS_SELECTED) != 0;
            bool focused = (item->itemState & ODS_FOCUS) != 0;
            COLORREF fill = pressed ? RGB(23, 53, 145) : RGB(30, 64, 175);
            HBRUSH brush = CreateSolidBrush(fill);
            FillRect(item->hDC, &item->rcItem, brush);
            DeleteObject(brush);
            SetBkMode(item->hDC, TRANSPARENT);
            SetTextColor(item->hDC, RGB(255, 255, 255));
            DrawTextW(item->hDC, L"Scan", -1, &item->rcItem, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            if (focused) {
                RECT focus = item->rcItem;
                InflateRect(&focus, -4, -4);
                DrawFocusRect(item->hDC, &focus);
            }
            return TRUE;
        }
        break;
    }
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show)
{
    g_instance = instance;
    g_inbox = get_inbox_path();

    WNDCLASSW wc = {};
    wc.lpfnWndProc = window_proc;
    wc.hInstance = instance;
    wc.lpszClassName = L"VirtualScannerInboxWindow";
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(1));
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    RegisterClassW(&wc);

    g_main = CreateWindowExW(0, wc.lpszClassName, L"Virtual Scanner Inbox",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 620, 420,
        nullptr, nullptr, instance, nullptr);
    if (!g_main) {
        return 1;
    }
    ShowWindow(g_main, show);
    UpdateWindow(g_main);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return (int)msg.wParam;
}
