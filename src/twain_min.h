#ifndef VIRTUAL_SCANNER_TWAIN_MIN_H
#define VIRTUAL_SCANNER_TWAIN_MIN_H

#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
typedef void *HANDLE;
#endif

#pragma pack(push, 2)

typedef uint8_t TW_UINT8;
typedef int16_t TW_INT16;
typedef uint16_t TW_UINT16;
typedef int32_t TW_INT32;
typedef uint32_t TW_UINT32;
typedef uintptr_t TW_UINTPTR;
typedef void *TW_MEMREF;
typedef HANDLE TW_HANDLE;
typedef char TW_STR32[34];
typedef char TW_STR255[256];
typedef TW_UINT16 TW_BOOL;

typedef struct {
    TW_INT16 Whole;
    TW_UINT16 Frac;
} TW_FIX32;

typedef struct {
    TW_UINT16 MajorNum;
    TW_UINT16 MinorNum;
    TW_UINT16 Language;
    TW_UINT16 Country;
    TW_STR32 Info;
} TW_VERSION;

typedef struct {
    TW_UINT32 Id;
    TW_VERSION Version;
    TW_UINT16 ProtocolMajor;
    TW_UINT16 ProtocolMinor;
    TW_UINT32 SupportedGroups;
    TW_STR32 Manufacturer;
    TW_STR32 ProductFamily;
    TW_STR32 ProductName;
} TW_IDENTITY, *pTW_IDENTITY;

typedef struct {
    TW_UINT16 ConditionCode;
    TW_UINT16 Reserved;
} TW_STATUS, *pTW_STATUS;

typedef struct {
    TW_BOOL ShowUI;
    TW_BOOL ModalUI;
    TW_HANDLE hParent;
} TW_USERINTERFACE, *pTW_USERINTERFACE;

typedef struct {
    TW_MEMREF pEvent;
    TW_UINT16 TWMessage;
} TW_EVENT, *pTW_EVENT;

typedef struct {
    TW_UINT16 Count;
    TW_UINT32 EOJ;
} TW_PENDINGXFERS, *pTW_PENDINGXFERS;

typedef struct {
    TW_FIX32 XResolution;
    TW_FIX32 YResolution;
    TW_INT32 ImageWidth;
    TW_INT32 ImageLength;
    TW_INT16 SamplesPerPixel;
    TW_INT16 BitsPerSample[8];
    TW_INT16 BitsPerPixel;
    TW_BOOL Planar;
    TW_INT16 PixelType;
    TW_UINT16 Compression;
} TW_IMAGEINFO, *pTW_IMAGEINFO;

typedef struct {
    TW_FIX32 Left;
    TW_FIX32 Top;
    TW_FIX32 Right;
    TW_FIX32 Bottom;
} TW_FRAME, *pTW_FRAME;

typedef struct {
    TW_FRAME Frame;
    TW_UINT32 DocumentNumber;
    TW_UINT32 PageNumber;
    TW_UINT32 FrameNumber;
} TW_IMAGELAYOUT, *pTW_IMAGELAYOUT;

typedef struct {
    TW_UINT16 Cap;
    TW_UINT16 ConType;
    TW_HANDLE hContainer;
} TW_CAPABILITY, *pTW_CAPABILITY;

typedef struct {
    TW_UINT16 ItemType;
    TW_UINT32 Item;
} TW_ONEVALUE, *pTW_ONEVALUE;

typedef struct {
    TW_UINT16 ItemType;
    TW_UINT32 NumItems;
    TW_UINT8 ItemList[1];
} TW_ARRAY, *pTW_ARRAY;

#pragma pack(pop)

#define TWON_ONEVALUE 0x0005
#define TWON_ARRAY 0x0003
#define TWTY_INT16 0x0001
#define TWTY_INT32 0x0002
#define TWTY_UINT16 0x0004
#define TWTY_UINT32 0x0005
#define TWTY_BOOL 0x0006
#define TWTY_FIX32 0x0007

#define DG_CONTROL 0x0001
#define DG_IMAGE 0x0002

#define DAT_NULL 0x0000
#define DAT_CAPABILITY 0x0001
#define DAT_EVENT 0x0002
#define DAT_IDENTITY 0x0003
#define DAT_PENDINGXFERS 0x0005
#define DAT_STATUS 0x0008
#define DAT_USERINTERFACE 0x0009
#define DAT_XFERGROUP 0x000a
#define DAT_IMAGEINFO 0x0101
#define DAT_IMAGELAYOUT 0x0102
#define DAT_IMAGENATIVEXFER 0x0104

#define MSG_GET 0x0001
#define MSG_GETCURRENT 0x0002
#define MSG_GETDEFAULT 0x0003
#define MSG_GETFIRST 0x0004
#define MSG_GETNEXT 0x0005
#define MSG_SET 0x0006
#define MSG_RESET 0x0007
#define MSG_QUERYSUPPORT 0x0008
#define MSG_XFERREADY 0x0101
#define MSG_OPENDSM 0x0301
#define MSG_CLOSEDSM 0x0302
#define MSG_OPENDS 0x0401
#define MSG_CLOSEDS 0x0402
#define MSG_USERSELECT 0x0403
#define MSG_DISABLEDS 0x0501
#define MSG_ENABLEDS 0x0502
#define MSG_ENABLEDSUIONLY 0x0503
#define MSG_PROCESSEVENT 0x0601
#define MSG_ENDXFER 0x0701

#define TWRC_SUCCESS 0
#define TWRC_FAILURE 1
#define TWRC_CHECKSTATUS 2
#define TWRC_DSEVENT 4
#define TWRC_NOTDSEVENT 5
#define TWRC_XFERDONE 6
#define TWRC_ENDOFLIST 7

#define TWCC_SUCCESS 0
#define TWCC_BUMMER 1
#define TWCC_LOWMEMORY 2
#define TWCC_BADCAP 6
#define TWCC_SEQERROR 11
#define TWCC_CAPUNSUPPORTED 13
#define TWCC_CAPBADOPERATION 14

#define TWQC_GET 0x0001
#define TWQC_SET 0x0002
#define TWQC_GETDEFAULT 0x0004
#define TWQC_GETCURRENT 0x0008
#define TWQC_RESET 0x0010

#define TWLG_USA 13
#define TWCY_USA 1
#define TWON_PROTOCOLMAJOR 1
#define TWON_PROTOCOLMINOR 9

#define DF_DS2 0x10000000UL
#define DG_IMAGE_MASK 0x00000002UL
#define DG_CONTROL_MASK 0x00000001UL

#define CAP_XFERCOUNT 0x0001
#define ICAP_COMPRESSION 0x0100
#define ICAP_PIXELTYPE 0x0101
#define ICAP_UNITS 0x0102
#define ICAP_XFERMECH 0x0103
#define ICAP_PHYSICALWIDTH 0x1108
#define ICAP_PHYSICALHEIGHT 0x1109
#define CAP_FEEDERENABLED 0x1002
#define CAP_FEEDERLOADED 0x1003
#define CAP_SUPPORTEDCAPS 0x1005
#define CAP_AUTOFEED 0x1007
#define CAP_INDICATORS 0x100b
#define CAP_UICONTROLLABLE 0x100e
#define CAP_DEVICEONLINE 0x100f
#define CAP_AUTOSCAN 0x1010
#define CAP_DUPLEXENABLED 0x1013
#define ICAP_XRESOLUTION 0x1118
#define ICAP_YRESOLUTION 0x1119
#define ICAP_BITORDER 0x111c
#define ICAP_PIXELFLAVOR 0x111f
#define ICAP_PLANARCHUNKY 0x1120
#define ICAP_SUPPORTEDSIZES 0x1122
#define ICAP_BITDEPTH 0x112b
#define TWPT_RGB 2
#define TWCP_NONE 0
#define TWSX_NATIVE 0
#define TWUN_INCHES 0
#define TWBO_LSBFIRST 0
#define TWPF_CHOCOLATE 0
#define TWPC_CHUNKY 0
#define TWSS_USLETTER 3

#ifdef __cplusplus
extern "C" {
#endif

TW_UINT16 __stdcall DS_Entry(
    pTW_IDENTITY pOrigin,
    TW_UINT32 DG,
    TW_UINT16 DAT,
    TW_UINT16 MSG,
    TW_MEMREF pData);

#ifdef __cplusplus
}
#endif

#endif
