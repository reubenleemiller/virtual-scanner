#include "twain_min.h"

#include <shlobj.h>
#include <wincodec.h>

#include <algorithm>
#include <cstring>
#include <cwchar>
#include <cwctype>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#define PAGE_WIDTH 2550
#define PAGE_HEIGHT 3300
#define FALLBACK_PAGE_WIDTH PAGE_WIDTH
#define FALLBACK_PAGE_HEIGHT PAGE_HEIGHT
#define BYTES_PER_PIXEL 3

struct PageInfo {
    TW_INT32 width;
    TW_INT32 height;
};

static TW_STATUS g_status = {TWCC_SUCCESS, 0};
static TW_BOOL g_open = 0;
static TW_BOOL g_enabled = 0;
static TW_BOOL g_xfer_ready_posted = 0;
static TW_BOOL g_inbox_helper_launched = 0;
static TW_BOOL g_waiting_for_scan_signal = 0;
static TW_UINT16 g_pending_images = 1;
static std::wstring g_current_file;
static PageInfo g_current_page = {FALLBACK_PAGE_WIDTH, FALLBACK_PAGE_HEIGHT};
static std::wstring g_scan_session_folder;
static HINSTANCE g_instance = nullptr;

static void append_log(const char *message)
{
    wchar_t path[MAX_PATH];
    DWORD len = GetEnvironmentVariableW(L"VIRTUAL_SCANNER_INBOX", path, MAX_PATH);
    std::wstring log_path;
    if (len > 0 && len < MAX_PATH) {
        log_path = path;
    } else {
        log_path = L"C:\\Users\\Public\\Documents\\VirtualScannerInbox";
    }

    CreateDirectoryW(log_path.c_str(), nullptr);
    log_path += L"\\VirtualScanner.log";

    HANDLE file = CreateFileW(
        log_path.c_str(),
        FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }

    DWORD written = 0;
    WriteFile(file, message, (DWORD)strlen(message), &written, nullptr);
    WriteFile(file, "\r\n", 2, &written, nullptr);
    CloseHandle(file);
}

static bool debug_logging_enabled()
{
    static int enabled = -1;
    if (enabled != -1) {
        return enabled == 1;
    }

    wchar_t value[16];
    DWORD len = GetEnvironmentVariableW(L"VIRTUAL_SCANNER_DEBUG", value, 16);
    if (len == 0 || len >= 16) {
        enabled = 0;
        return false;
    }

    enabled = (wcscmp(value, L"1") == 0 ||
               _wcsicmp(value, L"true") == 0 ||
               _wcsicmp(value, L"yes") == 0)
                  ? 1
                  : 0;
    return enabled == 1;
}

static void log_entry(TW_UINT32 DG, TW_UINT16 DAT, TW_UINT16 MSG, TW_MEMREF pData)
{
    if (!debug_logging_enabled()) {
        return;
    }

    char line[160];
    TW_UINT16 cap = 0;
    if (DAT == DAT_CAPABILITY && pData) {
        cap = ((pTW_CAPABILITY)pData)->Cap;
    }
    snprintf(line, sizeof(line), "DS_Entry DG=0x%04lx DAT=0x%04x MSG=0x%04x CAP=0x%04x", (unsigned long)DG, DAT, MSG, cap);
    append_log(line);
}

static void set_status(TW_UINT16 condition)
{
    g_status.ConditionCode = condition;
}

static TW_FIX32 fix32_from_int(TW_INT16 value)
{
    TW_FIX32 result;
    result.Whole = value;
    result.Frac = 0;
    return result;
}

static TW_FIX32 fix32_from_double(double value)
{
    TW_FIX32 result;
    result.Whole = (TW_INT16)value;
    result.Frac = (TW_UINT16)((value - result.Whole) * 65536.0 + 0.5);
    return result;
}

static void copy_twain_string(char *dest, size_t size, const char *src)
{
    if (size == 0) {
        return;
    }
    strncpy(dest, src, size - 1);
    dest[size - 1] = '\0';
}

static void fill_identity(pTW_IDENTITY id)
{
    memset(id, 0, sizeof(*id));
    id->Id = 1;
    id->Version.MajorNum = 1;
    id->Version.MinorNum = 0;
    id->Version.Language = TWLG_USA;
    id->Version.Country = TWCY_USA;
    copy_twain_string(id->Version.Info, sizeof(id->Version.Info), "1.0");
    id->ProtocolMajor = TWON_PROTOCOLMAJOR;
    id->ProtocolMinor = TWON_PROTOCOLMINOR;
    id->SupportedGroups = DF_DS2 | DG_CONTROL_MASK | DG_IMAGE_MASK;
    copy_twain_string(id->Manufacturer, sizeof(id->Manufacturer), "Codex");
    copy_twain_string(id->ProductFamily, sizeof(id->ProductFamily), "Virtual Scanner");
    copy_twain_string(id->ProductName, sizeof(id->ProductName), "Virtual Scanner");
}

static TW_UINT16 return_failure(TW_UINT16 condition)
{
    set_status(condition);
    return TWRC_FAILURE;
}

static std::wstring lowercase(std::wstring value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) {
        return (wchar_t)towlower(c);
    });
    return value;
}

static bool has_supported_extension(const std::wstring &path)
{
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos) {
        return false;
    }

    std::wstring ext = lowercase(path.substr(dot));
    return ext == L".png" || ext == L".jpg" || ext == L".jpeg" ||
           ext == L".bmp" || ext == L".tif" || ext == L".tiff";
}

static bool has_pdf_extension(const std::wstring &path)
{
    size_t dot = path.find_last_of(L'.');
    if (dot == std::wstring::npos) {
        return false;
    }

    return lowercase(path.substr(dot)) == L".pdf";
}

static std::wstring get_inbox_folder()
{
    wchar_t env_path[MAX_PATH];
    DWORD env_len = GetEnvironmentVariableW(L"VIRTUAL_SCANNER_INBOX", env_path, MAX_PATH);
    if (env_len > 0 && env_len < MAX_PATH) {
        return env_path;
    }

    PWSTR documents = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &documents))) {
        std::wstring result = documents;
        CoTaskMemFree(documents);
        result += L"\\VirtualScannerInbox";
        return result;
    }

    wchar_t user_profile[MAX_PATH];
    DWORD profile_len = GetEnvironmentVariableW(L"USERPROFILE", user_profile, MAX_PATH);
    if (profile_len > 0 && profile_len < MAX_PATH) {
        return std::wstring(user_profile) + L"\\Documents\\VirtualScannerInbox";
    }

    return L"C:\\VirtualScannerInbox";
}

static std::wstring get_scan_signal_path()
{
    return get_inbox_folder() + L"\\.scan-now";
}

static bool scan_signal_exists()
{
    std::wstring signal = get_scan_signal_path();
    return GetFileAttributesW(signal.c_str()) != INVALID_FILE_ATTRIBUTES;
}

static void clear_scan_signal()
{
    std::wstring signal = get_scan_signal_path();
    DeleteFileW(signal.c_str());
}

static std::vector<std::wstring> list_inbox_images()
{
    std::vector<std::wstring> files;
    std::wstring folder = get_inbox_folder();
    CreateDirectoryW(folder.c_str(), nullptr);

    std::wstring pattern = folder + L"\\*";
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        return files;
    }

    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }

        std::wstring path = folder + L"\\" + data.cFileName;
        if (data.cFileName[0] == L'.') {
            continue;
        }
        if (has_supported_extension(path)) {
            files.push_back(path);
        }
    } while (FindNextFileW(find, &data));

    FindClose(find);
    std::sort(files.begin(), files.end(), [](const std::wstring &a, const std::wstring &b) {
        return lowercase(a) < lowercase(b);
    });
    return files;
}

static std::vector<std::wstring> list_inbox_pdfs()
{
    std::vector<std::wstring> files;
    std::wstring folder = get_inbox_folder();
    CreateDirectoryW(folder.c_str(), nullptr);

    std::wstring pattern = folder + L"\\*";
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        return files;
    }

    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            continue;
        }

        std::wstring path = folder + L"\\" + data.cFileName;
        if (data.cFileName[0] == L'.') {
            continue;
        }
        if (has_pdf_extension(path)) {
            files.push_back(path);
        }
    } while (FindNextFileW(find, &data));

    FindClose(find);
    std::sort(files.begin(), files.end(), [](const std::wstring &a, const std::wstring &b) {
        return lowercase(a) < lowercase(b);
    });
    return files;
}

static std::wstring shell_quote(const std::wstring &value)
{
    std::wstring quoted = L"\"";
    for (wchar_t c : value) {
        if (c == L'"') {
            quoted += L"\\\"";
        } else {
            quoted += c;
        }
    }
    quoted += L"\"";
    return quoted;
}

static bool find_on_path(const wchar_t *exe_name, std::wstring *out_path)
{
    wchar_t buffer[MAX_PATH];
    DWORD len = SearchPathW(nullptr, exe_name, nullptr, MAX_PATH, buffer, nullptr);
    if (len > 0 && len < MAX_PATH) {
        *out_path = buffer;
        return true;
    }
    return false;
}

static bool find_ghostscript_in_folder(const std::wstring &root, std::wstring *out_path)
{
    std::wstring pattern = root + L"\\gs\\gs*";
    WIN32_FIND_DATAW data;
    HANDLE find = FindFirstFileW(pattern.c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) {
        return false;
    }

    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            continue;
        }
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) {
            continue;
        }

        std::wstring base = root + L"\\gs\\" + data.cFileName + L"\\bin\\";
        std::wstring candidate = base + L"gswin64c.exe";
        if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) {
            FindClose(find);
            *out_path = candidate;
            return true;
        }

        candidate = base + L"gswin32c.exe";
        if (GetFileAttributesW(candidate.c_str()) != INVALID_FILE_ATTRIBUTES) {
            FindClose(find);
            *out_path = candidate;
            return true;
        }
    } while (FindNextFileW(find, &data));

    FindClose(find);
    return false;
}

static bool find_ghostscript(std::wstring *out_path)
{
    wchar_t env_path[MAX_PATH];
    DWORD env_len = GetEnvironmentVariableW(L"VIRTUAL_SCANNER_GHOSTSCRIPT", env_path, MAX_PATH);
    if (env_len > 0 && env_len < MAX_PATH && GetFileAttributesW(env_path) != INVALID_FILE_ATTRIBUTES) {
        *out_path = env_path;
        return true;
    }

    if (find_on_path(L"gswin64c.exe", out_path) || find_on_path(L"gswin32c.exe", out_path)) {
        return true;
    }

    wchar_t program_files[MAX_PATH];
    DWORD len = GetEnvironmentVariableW(L"ProgramFiles", program_files, MAX_PATH);
    if (len > 0 && len < MAX_PATH && find_ghostscript_in_folder(program_files, out_path)) {
        return true;
    }

    len = GetEnvironmentVariableW(L"ProgramFiles(x86)", program_files, MAX_PATH);
    if (len > 0 && len < MAX_PATH && find_ghostscript_in_folder(program_files, out_path)) {
        return true;
    }

    return false;
}

static std::wstring filename_without_extension(const std::wstring &path)
{
    size_t slash = path.find_last_of(L"\\/");
    std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
    size_t dot = name.find_last_of(L'.');
    if (dot != std::wstring::npos) {
        name = name.substr(0, dot);
    }
    return name;
}

static std::wstring make_timestamp()
{
    SYSTEMTIME now;
    GetLocalTime(&now);

    wchar_t stamp[64];
    wsprintfW(
        stamp,
        L"%04u%02u%02u-%02u%02u%02u-%03u",
        now.wYear,
        now.wMonth,
        now.wDay,
        now.wHour,
        now.wMinute,
        now.wSecond,
        now.wMilliseconds);
    return stamp;
}

static std::wstring get_scan_session_folder()
{
    if (!g_scan_session_folder.empty()) {
        return g_scan_session_folder;
    }

    std::wstring folder = get_inbox_folder();
    std::wstring scanned = folder + L"\\Scanned";
    CreateDirectoryW(scanned.c_str(), nullptr);

    g_scan_session_folder = scanned + L"\\" + make_timestamp();
    CreateDirectoryW(g_scan_session_folder.c_str(), nullptr);
    return g_scan_session_folder;
}

static void archive_file(const std::wstring &file)
{
    if (file.empty()) {
        return;
    }

    std::wstring archive = get_scan_session_folder();

    size_t slash = file.find_last_of(L"\\/");
    std::wstring name = slash == std::wstring::npos ? file : file.substr(slash + 1);
    std::wstring target = archive + L"\\" + name;

    if (GetFileAttributesW(target.c_str()) != INVALID_FILE_ATTRIBUTES) {
        wchar_t stamp[64];
        wsprintfW(stamp, L"-%lu", GetTickCount());
        size_t dot = name.find_last_of(L'.');
        if (dot == std::wstring::npos) {
            target = archive + L"\\" + name + stamp;
        } else {
            target = archive + L"\\" + name.substr(0, dot) + stamp + name.substr(dot);
        }
    }

    MoveFileExW(file.c_str(), target.c_str(), MOVEFILE_COPY_ALLOWED | MOVEFILE_REPLACE_EXISTING);
}

static bool run_process_and_wait(std::wstring command_line)
{
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    memset(&startup, 0, sizeof(startup));
    memset(&process, 0, sizeof(process));
    startup.cb = sizeof(startup);

    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');

    BOOL created = CreateProcessW(
        nullptr,
        mutable_command.data(),
        nullptr,
        nullptr,
        FALSE,
        CREATE_NO_WINDOW,
        nullptr,
        nullptr,
        &startup,
        &process);
    if (!created) {
        append_log("PDF conversion failed: CreateProcessW failed");
        return false;
    }

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exit_code = 1;
    GetExitCodeProcess(process.hProcess, &exit_code);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);

    if (exit_code != 0) {
        char line[96];
        snprintf(line, sizeof(line), "PDF conversion failed: Ghostscript exit code %lu", (unsigned long)exit_code);
        append_log(line);
        return false;
    }

    return true;
}

static bool convert_first_pdf_to_images()
{
    std::vector<std::wstring> pdfs = list_inbox_pdfs();
    if (pdfs.empty()) {
        return false;
    }

    std::wstring ghostscript;
    if (!find_ghostscript(&ghostscript)) {
        append_log("PDF conversion skipped: Ghostscript not found");
        return false;
    }

    std::wstring pdf = pdfs.front();
    std::wstring folder = get_inbox_folder();
    std::wstring base = filename_without_extension(pdf);
    std::wstring output = folder + L"\\" + base + L"-%03d.png";

    std::wstring command =
        shell_quote(ghostscript) +
        L" -dSAFER -dBATCH -dNOPAUSE -sDEVICE=png16m -r300 -dTextAlphaBits=4 -dGraphicsAlphaBits=4 -sOutputFile=" +
        shell_quote(output) + L" " + shell_quote(pdf);

    append_log("PDF conversion starting");
    if (!run_process_and_wait(command)) {
        return false;
    }

    append_log("PDF conversion finished");
    archive_file(pdf);
    return true;
}

static void archive_current_file()
{
    if (g_current_file.empty()) {
        return;
    }

    archive_file(g_current_file);
    g_current_file.clear();
}

static std::wstring get_module_folder()
{
    wchar_t module_path[MAX_PATH];
    DWORD len = GetModuleFileNameW(g_instance, module_path, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) {
        return L"";
    }

    std::wstring path = module_path;
    size_t slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) {
        return L"";
    }
    return path.substr(0, slash);
}

static void launch_inbox_helper()
{
    std::wstring module_folder = get_module_folder();
    if (module_folder.empty()) {
        append_log("Inbox helper launch skipped: module folder unavailable");
        return;
    }

    std::wstring launcher = module_folder + L"\\VirtualScannerInbox.vbs";
    if (GetFileAttributesW(launcher.c_str()) == INVALID_FILE_ATTRIBUTES) {
        append_log("Inbox helper launch skipped: launcher not found");
        return;
    }

    wchar_t system_dir[MAX_PATH];
    UINT system_len = GetSystemDirectoryW(system_dir, MAX_PATH);
    std::wstring wscript = L"wscript.exe";
    if (system_len > 0 && system_len < MAX_PATH) {
        wscript = std::wstring(system_dir) + L"\\wscript.exe";
    }

    std::wstring command =
        shell_quote(wscript) + L" " + shell_quote(launcher);

    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    memset(&startup, 0, sizeof(startup));
    memset(&process, 0, sizeof(process));
    startup.cb = sizeof(startup);

    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');

    BOOL created = CreateProcessW(
        nullptr,
        mutable_command.data(),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        nullptr,
        &startup,
        &process);
    if (!created) {
        append_log("Inbox helper launch failed");
        return;
    }

    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    append_log("Inbox helper launched");
}

static bool load_image_as_dib(const std::wstring &path, HGLOBAL *out_dib, PageInfo *out_info)
{
    *out_dib = nullptr;

    HRESULT init_hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    bool uninitialize = SUCCEEDED(init_hr);
    if (init_hr == RPC_E_CHANGED_MODE) {
        uninitialize = false;
    } else if (FAILED(init_hr)) {
        return false;
    }

    IWICImagingFactory *factory = nullptr;
    IWICBitmapDecoder *decoder = nullptr;
    IWICBitmapFrameDecode *frame = nullptr;
    IWICFormatConverter *converter = nullptr;
    HGLOBAL dib = nullptr;
    bool ok = false;

    HRESULT hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IWICImagingFactory,
        (void **)&factory);

    if (SUCCEEDED(hr)) {
        hr = factory->CreateDecoderFromFilename(
            path.c_str(),
            nullptr,
            GENERIC_READ,
            WICDecodeMetadataCacheOnLoad,
            &decoder);
    }

    if (SUCCEEDED(hr)) {
        hr = decoder->GetFrame(0, &frame);
    }

    UINT width = 0;
    UINT height = 0;
    if (SUCCEEDED(hr)) {
        hr = frame->GetSize(&width, &height);
    }

    if (SUCCEEDED(hr)) {
        hr = factory->CreateFormatConverter(&converter);
    }

    if (SUCCEEDED(hr)) {
        hr = converter->Initialize(
            frame,
            GUID_WICPixelFormat24bppBGR,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom);
    }

    if (SUCCEEDED(hr) && width > 0 && height > 0) {
        TW_UINT32 dst_stride = ((PAGE_WIDTH * BYTES_PER_PIXEL + 3) / 4) * 4;
        TW_UINT32 pixel_bytes = dst_stride * PAGE_HEIGHT;
        TW_UINT32 dib_bytes = sizeof(BITMAPINFOHEADER) + pixel_bytes;

        dib = GlobalAlloc(GHND, dib_bytes);
        if (dib) {
            TW_UINT8 *memory = (TW_UINT8 *)GlobalLock(dib);
            if (memory) {
                BITMAPINFOHEADER *header = (BITMAPINFOHEADER *)memory;
                memset(header, 0, sizeof(*header));
                header->biSize = sizeof(BITMAPINFOHEADER);
                header->biWidth = PAGE_WIDTH;
                header->biHeight = PAGE_HEIGHT;
                header->biPlanes = 1;
                header->biBitCount = 24;
                header->biCompression = BI_RGB;
                header->biSizeImage = pixel_bytes;
                header->biXPelsPerMeter = 11811;
                header->biYPelsPerMeter = 11811;

                TW_UINT8 *pixels = memory + sizeof(BITMAPINFOHEADER);
                memset(pixels, 255, pixel_bytes);

                double scale_x = (double)PAGE_WIDTH / (double)width;
                double scale_y = (double)PAGE_HEIGHT / (double)height;
                double scale = scale_x < scale_y ? scale_x : scale_y;
                int draw_width = (int)(width * scale + 0.5);
                int draw_height = (int)(height * scale + 0.5);
                if (draw_width < 1) {
                    draw_width = 1;
                }
                if (draw_height < 1) {
                    draw_height = 1;
                }
                int x_offset = (PAGE_WIDTH - draw_width) / 2;
                int y_offset = (PAGE_HEIGHT - draw_height) / 2;

                TW_UINT32 src_stride = ((width * BYTES_PER_PIXEL + 3) / 4) * 4;
                std::vector<TW_UINT8> source(src_stride * height);
                hr = converter->CopyPixels(nullptr, src_stride, (UINT)source.size(), source.data());
                if (SUCCEEDED(hr)) {
                    for (int y = 0; y < draw_height; y++) {
                        int src_y = (int)((double)y / scale);
                        if (src_y >= (int)height) {
                            src_y = (int)height - 1;
                        }
                        TW_UINT8 *dst_row = pixels + ((PAGE_HEIGHT - 1 - (y_offset + y)) * dst_stride);
                        const TW_UINT8 *src_row = source.data() + (src_y * src_stride);

                        for (int x = 0; x < draw_width; x++) {
                            int src_x = (int)((double)x / scale);
                            if (src_x >= (int)width) {
                                src_x = (int)width - 1;
                            }

                            const TW_UINT8 *src_px = src_row + src_x * 3;
                            TW_UINT8 *dst_px = dst_row + (x_offset + x) * 3;
                            dst_px[0] = src_px[0];
                            dst_px[1] = src_px[1];
                            dst_px[2] = src_px[2];
                        }
                    }
                }
                GlobalUnlock(dib);

                if (SUCCEEDED(hr)) {
                    *out_dib = dib;
                    out_info->width = PAGE_WIDTH;
                    out_info->height = PAGE_HEIGHT;
                    ok = true;
                    dib = nullptr;
                }
            }
        }
    }

    if (dib) {
        GlobalFree(dib);
    }
    if (converter) {
        converter->Release();
    }
    if (frame) {
        frame->Release();
    }
    if (decoder) {
        decoder->Release();
    }
    if (factory) {
        factory->Release();
    }
    if (uninitialize) {
        CoUninitialize();
    }

    return ok;
}

static void draw_fallback_page(TW_UINT8 *pixels, TW_UINT32 stride)
{
    for (int y = 0; y < FALLBACK_PAGE_HEIGHT; y++) {
        TW_UINT8 *row = pixels + ((FALLBACK_PAGE_HEIGHT - 1 - y) * stride);
        for (int x = 0; x < FALLBACK_PAGE_WIDTH; x++) {
            TW_UINT8 r = (TW_UINT8)((x * 255) / FALLBACK_PAGE_WIDTH);
            TW_UINT8 g = (TW_UINT8)((y * 255) / FALLBACK_PAGE_HEIGHT);
            TW_UINT8 b = 245;

            if ((x / 32 + y / 32) % 2 == 0) {
                r = (TW_UINT8)(255 - r / 3);
                g = (TW_UINT8)(255 - g / 3);
                b = 255;
            }

            row[x * 3 + 0] = b;
            row[x * 3 + 1] = g;
            row[x * 3 + 2] = r;
        }
    }
}

static HGLOBAL create_fallback_dib(PageInfo *out_info)
{
    TW_UINT32 stride = ((FALLBACK_PAGE_WIDTH * BYTES_PER_PIXEL + 3) / 4) * 4;
    TW_UINT32 pixel_bytes = stride * FALLBACK_PAGE_HEIGHT;
    TW_UINT32 dib_bytes = sizeof(BITMAPINFOHEADER) + pixel_bytes;

    HGLOBAL dib = GlobalAlloc(GHND, dib_bytes);
    if (!dib) {
        return nullptr;
    }

    TW_UINT8 *memory = (TW_UINT8 *)GlobalLock(dib);
    if (!memory) {
        GlobalFree(dib);
        return nullptr;
    }

    BITMAPINFOHEADER *header = (BITMAPINFOHEADER *)memory;
    memset(header, 0, sizeof(*header));
    header->biSize = sizeof(BITMAPINFOHEADER);
    header->biWidth = FALLBACK_PAGE_WIDTH;
    header->biHeight = FALLBACK_PAGE_HEIGHT;
    header->biPlanes = 1;
    header->biBitCount = 24;
    header->biCompression = BI_RGB;
    header->biSizeImage = pixel_bytes;
    header->biXPelsPerMeter = 11811;
    header->biYPelsPerMeter = 11811;

    draw_fallback_page(memory + sizeof(BITMAPINFOHEADER), stride);
    GlobalUnlock(dib);

    out_info->width = FALLBACK_PAGE_WIDTH;
    out_info->height = FALLBACK_PAGE_HEIGHT;
    return dib;
}

static bool select_next_page()
{
    if (g_waiting_for_scan_signal && !scan_signal_exists()) {
        g_pending_images = 0;
        return false;
    }

    std::vector<std::wstring> files = list_inbox_images();
    if (files.empty()) {
        convert_first_pdf_to_images();
        files = list_inbox_images();
    }

    if (files.empty()) {
        g_current_file.clear();
        g_current_page = {FALLBACK_PAGE_WIDTH, FALLBACK_PAGE_HEIGHT};
        g_scan_session_folder.clear();
        g_pending_images = 0;
        return false;
    }

    clear_scan_signal();
    g_waiting_for_scan_signal = 0;
    g_current_file = files.front();
    g_current_page = {FALLBACK_PAGE_WIDTH, FALLBACK_PAGE_HEIGHT};
    g_pending_images = 1;
    return true;
}

static TW_UINT16 handle_status(TW_MEMREF pData)
{
    if (!pData) {
        return return_failure(TWCC_BUMMER);
    }
    *(pTW_STATUS)pData = g_status;
    set_status(TWCC_SUCCESS);
    return TWRC_SUCCESS;
}

static TW_UINT32 fix32_bits(TW_INT16 value)
{
    TW_FIX32 fix = fix32_from_int(value);
    TW_UINT32 bits = 0;
    memcpy(&bits, &fix, sizeof(bits));
    return bits;
}

static TW_UINT32 fix32_double_bits(double value)
{
    TW_FIX32 fix = fix32_from_double(value);
    TW_UINT32 bits = 0;
    memcpy(&bits, &fix, sizeof(bits));
    return bits;
}

static TW_UINT16 capability_get_onevalue(pTW_CAPABILITY cap, TW_UINT16 item_type, TW_UINT32 item)
{
    HGLOBAL memory = GlobalAlloc(GHND, sizeof(TW_ONEVALUE));
    if (!memory) {
        return return_failure(TWCC_LOWMEMORY);
    }

    pTW_ONEVALUE value = (pTW_ONEVALUE)GlobalLock(memory);
    if (!value) {
        GlobalFree(memory);
        return return_failure(TWCC_LOWMEMORY);
    }

    value->ItemType = item_type;
    value->Item = item;
    GlobalUnlock(memory);

    cap->ConType = TWON_ONEVALUE;
    cap->hContainer = memory;
    set_status(TWCC_SUCCESS);
    return TWRC_SUCCESS;
}

static TW_UINT16 capability_get_array(pTW_CAPABILITY cap, TW_UINT16 item_type, const TW_UINT16 *items, TW_UINT32 count)
{
    size_t bytes = sizeof(TW_UINT16) + sizeof(TW_UINT32) + (sizeof(TW_UINT16) * count);
    HGLOBAL memory = GlobalAlloc(GHND, bytes);
    if (!memory) {
        return return_failure(TWCC_LOWMEMORY);
    }

    pTW_ARRAY array = (pTW_ARRAY)GlobalLock(memory);
    if (!array) {
        GlobalFree(memory);
        return return_failure(TWCC_LOWMEMORY);
    }

    array->ItemType = item_type;
    array->NumItems = count;
    memcpy(array->ItemList, items, sizeof(TW_UINT16) * count);
    GlobalUnlock(memory);

    cap->ConType = TWON_ARRAY;
    cap->hContainer = memory;
    set_status(TWCC_SUCCESS);
    return TWRC_SUCCESS;
}

static bool is_supported_cap(TW_UINT16 cap)
{
    switch (cap) {
    case CAP_XFERCOUNT:
    case CAP_FEEDERENABLED:
    case CAP_FEEDERLOADED:
    case CAP_SUPPORTEDCAPS:
    case CAP_AUTOFEED:
    case CAP_INDICATORS:
    case CAP_UICONTROLLABLE:
    case CAP_DEVICEONLINE:
    case CAP_AUTOSCAN:
    case CAP_DUPLEXENABLED:
    case ICAP_COMPRESSION:
    case ICAP_PIXELTYPE:
    case ICAP_UNITS:
    case ICAP_XFERMECH:
    case ICAP_PHYSICALWIDTH:
    case ICAP_PHYSICALHEIGHT:
    case ICAP_XRESOLUTION:
    case ICAP_YRESOLUTION:
    case ICAP_BITORDER:
    case ICAP_PIXELFLAVOR:
    case ICAP_PLANARCHUNKY:
    case ICAP_SUPPORTEDSIZES:
    case ICAP_BITDEPTH:
        return true;
    default:
        return false;
    }
}

static TW_UINT16 capability_get_supported_caps(pTW_CAPABILITY cap)
{
    static const TW_UINT16 caps[] = {
        CAP_XFERCOUNT,
        CAP_FEEDERENABLED,
        CAP_FEEDERLOADED,
        CAP_SUPPORTEDCAPS,
        CAP_AUTOFEED,
        CAP_INDICATORS,
        CAP_UICONTROLLABLE,
        CAP_DEVICEONLINE,
        CAP_AUTOSCAN,
        CAP_DUPLEXENABLED,
        ICAP_COMPRESSION,
        ICAP_PIXELTYPE,
        ICAP_UNITS,
        ICAP_XFERMECH,
        ICAP_PHYSICALWIDTH,
        ICAP_PHYSICALHEIGHT,
        ICAP_XRESOLUTION,
        ICAP_YRESOLUTION,
        ICAP_BITORDER,
        ICAP_PIXELFLAVOR,
        ICAP_PLANARCHUNKY,
        ICAP_SUPPORTEDSIZES,
        ICAP_BITDEPTH,
    };
    return capability_get_array(cap, TWTY_UINT16, caps, sizeof(caps) / sizeof(caps[0]));
}

static TW_UINT16 capability_query_support(pTW_CAPABILITY cap)
{
    if (!is_supported_cap(cap->Cap)) {
        return return_failure(TWCC_CAPUNSUPPORTED);
    }

    TW_UINT32 support = TWQC_GET | TWQC_GETCURRENT | TWQC_GETDEFAULT | TWQC_RESET;
    switch (cap->Cap) {
    case CAP_XFERCOUNT:
    case CAP_FEEDERENABLED:
    case CAP_AUTOFEED:
    case CAP_INDICATORS:
    case CAP_AUTOSCAN:
    case CAP_DUPLEXENABLED:
    case ICAP_PIXELTYPE:
    case ICAP_UNITS:
    case ICAP_XFERMECH:
    case ICAP_XRESOLUTION:
    case ICAP_YRESOLUTION:
    case ICAP_PHYSICALWIDTH:
    case ICAP_PHYSICALHEIGHT:
    case ICAP_SUPPORTEDSIZES:
    case ICAP_BITDEPTH:
        support |= TWQC_SET;
        break;
    default:
        break;
    }

    return capability_get_onevalue(cap, TWTY_INT32, support);
}

static TW_UINT16 capability_get_value(pTW_CAPABILITY cap)
{
    switch (cap->Cap) {
    case CAP_XFERCOUNT:
        return capability_get_onevalue(cap, TWTY_INT16, 1);
    case CAP_FEEDERENABLED:
    case CAP_FEEDERLOADED:
    case CAP_AUTOFEED:
    case CAP_INDICATORS:
    case CAP_UICONTROLLABLE:
    case CAP_DEVICEONLINE:
    case CAP_AUTOSCAN:
        return capability_get_onevalue(cap, TWTY_BOOL, 1);
    case CAP_DUPLEXENABLED:
        return capability_get_onevalue(cap, TWTY_BOOL, 0);
    case CAP_SUPPORTEDCAPS:
        return capability_get_supported_caps(cap);
    case ICAP_COMPRESSION:
        return capability_get_onevalue(cap, TWTY_UINT16, TWCP_NONE);
    case ICAP_PIXELTYPE:
        return capability_get_onevalue(cap, TWTY_UINT16, TWPT_RGB);
    case ICAP_UNITS:
        return capability_get_onevalue(cap, TWTY_UINT16, TWUN_INCHES);
    case ICAP_XFERMECH:
        return capability_get_onevalue(cap, TWTY_UINT16, TWSX_NATIVE);
    case ICAP_XRESOLUTION:
    case ICAP_YRESOLUTION:
        return capability_get_onevalue(cap, TWTY_FIX32, fix32_bits(300));
    case ICAP_PHYSICALWIDTH:
        return capability_get_onevalue(cap, TWTY_FIX32, fix32_double_bits(8.5));
    case ICAP_PHYSICALHEIGHT:
        return capability_get_onevalue(cap, TWTY_FIX32, fix32_double_bits(11.0));
    case ICAP_BITORDER:
        return capability_get_onevalue(cap, TWTY_UINT16, TWBO_LSBFIRST);
    case ICAP_PIXELFLAVOR:
        return capability_get_onevalue(cap, TWTY_UINT16, TWPF_CHOCOLATE);
    case ICAP_PLANARCHUNKY:
        return capability_get_onevalue(cap, TWTY_UINT16, TWPC_CHUNKY);
    case ICAP_SUPPORTEDSIZES:
        return capability_get_onevalue(cap, TWTY_UINT16, TWSS_USLETTER);
    case ICAP_BITDEPTH:
        return capability_get_onevalue(cap, TWTY_UINT16, 24);
    default:
        return return_failure(TWCC_CAPUNSUPPORTED);
    }
}

static TW_UINT16 handle_capability(TW_UINT16 MSG, TW_MEMREF pData)
{
    if (!pData) {
        return return_failure(TWCC_BUMMER);
    }

    pTW_CAPABILITY cap = (pTW_CAPABILITY)pData;

    if (!is_supported_cap(cap->Cap)) {
        return return_failure(TWCC_CAPUNSUPPORTED);
    }

    if (MSG == MSG_QUERYSUPPORT) {
        return capability_query_support(cap);
    }

    if (MSG == MSG_SET || MSG == MSG_RESET) {
        set_status(TWCC_SUCCESS);
        return TWRC_SUCCESS;
    }

    if (MSG == MSG_GET || MSG == MSG_GETCURRENT || MSG == MSG_GETDEFAULT) {
        return capability_get_value(cap);
    }

    return return_failure(TWCC_CAPBADOPERATION);
}

static TW_UINT16 handle_userinterface(TW_UINT16 MSG)
{
    if (MSG == MSG_ENABLEDS || MSG == MSG_ENABLEDSUIONLY) {
        if (!g_open) {
            return return_failure(TWCC_SEQERROR);
        }
        if (!select_next_page()) {
            launch_inbox_helper();
            g_enabled = 1;
            g_xfer_ready_posted = 0;
            g_inbox_helper_launched = 1;
            g_waiting_for_scan_signal = 1;
            set_status(TWCC_SUCCESS);
            return TWRC_SUCCESS;
        }
        g_enabled = 1;
        g_xfer_ready_posted = 0;
        g_inbox_helper_launched = 0;
        g_waiting_for_scan_signal = 0;
        set_status(TWCC_SUCCESS);
        return TWRC_SUCCESS;
    }

    if (MSG == MSG_DISABLEDS) {
        g_enabled = 0;
        g_xfer_ready_posted = 0;
        g_inbox_helper_launched = 0;
        g_waiting_for_scan_signal = 0;
        set_status(TWCC_SUCCESS);
        return TWRC_SUCCESS;
    }

    return return_failure(TWCC_CAPBADOPERATION);
}

static TW_UINT16 handle_event(TW_UINT16 MSG, TW_MEMREF pData)
{
    if (MSG != MSG_PROCESSEVENT || !pData) {
        return return_failure(TWCC_BUMMER);
    }

    pTW_EVENT event = (pTW_EVENT)pData;
    event->TWMessage = 0;

    if (g_enabled && !g_xfer_ready_posted && g_pending_images == 0) {
        if (select_next_page()) {
            g_inbox_helper_launched = 0;
        } else if (!g_inbox_helper_launched) {
            launch_inbox_helper();
            g_inbox_helper_launched = 1;
        }
    }

    if (g_enabled && !g_xfer_ready_posted && g_pending_images > 0) {
        g_xfer_ready_posted = 1;
        event->TWMessage = MSG_XFERREADY;
        set_status(TWCC_SUCCESS);
        return TWRC_DSEVENT;
    }

    set_status(TWCC_SUCCESS);
    return TWRC_NOTDSEVENT;
}

static TW_UINT16 handle_pendingxfers(TW_UINT16 MSG, TW_MEMREF pData)
{
    if (!pData) {
        return return_failure(TWCC_BUMMER);
    }

    pTW_PENDINGXFERS pending = (pTW_PENDINGXFERS)pData;

    if (MSG == MSG_GET) {
        pending->Count = g_pending_images;
        pending->EOJ = 0;
        set_status(TWCC_SUCCESS);
        return TWRC_SUCCESS;
    }

    if (MSG == MSG_ENDXFER) {
        if (g_pending_images > 0) {
            g_pending_images--;
        }
        if (g_pending_images == 0) {
            archive_current_file();
        }
        pending->Count = g_pending_images;
        pending->EOJ = 0;
        set_status(TWCC_SUCCESS);
        return TWRC_SUCCESS;
    }

    return return_failure(TWCC_CAPBADOPERATION);
}

static TW_UINT16 handle_imageinfo(TW_MEMREF pData)
{
    if (!pData) {
        return return_failure(TWCC_BUMMER);
    }

    pTW_IMAGEINFO info = (pTW_IMAGEINFO)pData;
    memset(info, 0, sizeof(*info));
    info->XResolution = fix32_from_int(300);
    info->YResolution = fix32_from_int(300);
    info->ImageWidth = g_current_page.width;
    info->ImageLength = g_current_page.height;
    info->SamplesPerPixel = 3;
    info->BitsPerSample[0] = 8;
    info->BitsPerSample[1] = 8;
    info->BitsPerSample[2] = 8;
    info->BitsPerPixel = 24;
    info->Planar = 0;
    info->PixelType = TWPT_RGB;
    info->Compression = TWCP_NONE;
    set_status(TWCC_SUCCESS);
    return TWRC_SUCCESS;
}

static TW_UINT16 handle_imagelayout(TW_MEMREF pData)
{
    if (!pData) {
        return return_failure(TWCC_BUMMER);
    }

    pTW_IMAGELAYOUT layout = (pTW_IMAGELAYOUT)pData;
    memset(layout, 0, sizeof(*layout));
    layout->Frame.Left = fix32_from_double(0.0);
    layout->Frame.Top = fix32_from_double(0.0);
    layout->Frame.Right = fix32_from_double(8.5);
    layout->Frame.Bottom = fix32_from_double(11.0);
    layout->DocumentNumber = 1;
    layout->PageNumber = 1;
    layout->FrameNumber = 1;
    set_status(TWCC_SUCCESS);
    return TWRC_SUCCESS;
}

static TW_UINT16 handle_native_transfer(TW_MEMREF pData)
{
    if (!pData || g_pending_images == 0) {
        return return_failure(TWCC_SEQERROR);
    }

    HGLOBAL dib = nullptr;
    PageInfo info = {FALLBACK_PAGE_WIDTH, FALLBACK_PAGE_HEIGHT};

    if (!g_current_file.empty()) {
        load_image_as_dib(g_current_file, &dib, &info);
    }
    if (!dib) {
        dib = create_fallback_dib(&info);
    }
    if (!dib) {
        return return_failure(TWCC_LOWMEMORY);
    }

    g_current_page = info;
    *(TW_UINTPTR *)pData = (TW_UINTPTR)dib;
    set_status(TWCC_SUCCESS);
    return TWRC_XFERDONE;
}

extern "C" TW_UINT16 __stdcall DS_Entry(
    pTW_IDENTITY pOrigin,
    TW_UINT32 DG,
    TW_UINT16 DAT,
    TW_UINT16 MSG,
    TW_MEMREF pData)
{
    (void)pOrigin;
    log_entry(DG, DAT, MSG, pData);

    if (DG == DG_CONTROL) {
        switch (DAT) {
        case DAT_IDENTITY:
            if (MSG == MSG_GET || MSG == MSG_GETFIRST) {
                fill_identity((pTW_IDENTITY)pData);
                set_status(TWCC_SUCCESS);
                return TWRC_SUCCESS;
            }
            if (MSG == MSG_GETNEXT) {
                return TWRC_ENDOFLIST;
            }
            if (MSG == MSG_OPENDS) {
                g_open = 1;
                g_scan_session_folder.clear();
                g_inbox_helper_launched = 0;
                g_waiting_for_scan_signal = 0;
                g_pending_images = 0;
                g_current_file.clear();
                g_current_page = {FALLBACK_PAGE_WIDTH, FALLBACK_PAGE_HEIGHT};
                set_status(TWCC_SUCCESS);
                return TWRC_SUCCESS;
            }
            if (MSG == MSG_CLOSEDS) {
                g_open = 0;
                g_enabled = 0;
                g_xfer_ready_posted = 0;
                g_inbox_helper_launched = 0;
                g_waiting_for_scan_signal = 0;
                set_status(TWCC_SUCCESS);
                return TWRC_SUCCESS;
            }
            break;
        case DAT_STATUS:
            if (MSG == MSG_GET) {
                return handle_status(pData);
            }
            break;
        case DAT_CAPABILITY:
            return handle_capability(MSG, pData);
        case DAT_USERINTERFACE:
            return handle_userinterface(MSG);
        case DAT_EVENT:
            return handle_event(MSG, pData);
        case DAT_PENDINGXFERS:
            return handle_pendingxfers(MSG, pData);
        case DAT_XFERGROUP:
            if (MSG == MSG_GET || MSG == MSG_GETCURRENT || MSG == MSG_GETDEFAULT) {
                *(TW_UINT32 *)pData = DG_IMAGE_MASK;
                set_status(TWCC_SUCCESS);
                return TWRC_SUCCESS;
            }
            break;
        default:
            break;
        }
    }

    if (DG == DG_IMAGE) {
        switch (DAT) {
        case DAT_IMAGEINFO:
            if (MSG == MSG_GET) {
                return handle_imageinfo(pData);
            }
            break;
        case DAT_IMAGELAYOUT:
            if (MSG == MSG_GET || MSG == MSG_GETCURRENT || MSG == MSG_GETDEFAULT) {
                return handle_imagelayout(pData);
            }
            if (MSG == MSG_SET || MSG == MSG_RESET) {
                set_status(TWCC_SUCCESS);
                return TWRC_SUCCESS;
            }
            break;
        case DAT_IMAGENATIVEXFER:
            if (MSG == MSG_GET) {
                return handle_native_transfer(pData);
            }
            break;
        default:
            break;
        }
    }

    return return_failure(TWCC_BUMMER);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    (void)reason;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        g_instance = instance;
    }
    return TRUE;
}
