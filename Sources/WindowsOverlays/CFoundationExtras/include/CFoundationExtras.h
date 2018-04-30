#ifndef CFoundationExtras_h
#define CFoundationExtras_h

#define UNICODE
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <intrin.h>
#include <windows.h> 

#include <time.h>

#include <errno.h>

#if defined(_WIN64)
typedef unsigned __int64  uintptr_t;
#else
typedef unsigned __int32  uintptr_t;
#endif

#include <stdbool.h>
#include <errno.h>
#include <string.h>
#include <io.h>
#include <fcntl.h>
#include <direct.h>
#include <strsafe.h>
#include <Shlwapi.h>
#include <ShlObj.h>

int mkstemp (char *_Nonnull tmpl);

inline int getErrno() {
    return errno;
}

inline int _wopenNoMode(  
   const wchar_t *_Nonnull filename,  
   int oflag) {
       return _wopen(filename, oflag);
}  

inline int _wopenWithMode(  
   const wchar_t *_Nonnull filename,  
   int oflag, int pmode) {
       return _wopen(filename, oflag, pmode);
}  

inline DWORD GetPageSize() {
    SYSTEM_INFO siSysInfo;
    // Copy the hardware information to the SYSTEM_INFO structure. 
    GetSystemInfo(&siSysInfo);

    return siSysInfo.dwPageSize;
}

inline BOOL CPathIsDirectoryW(LPCWSTR _Nonnull szPath)
{
  DWORD dwAttrib = GetFileAttributesW(szPath);

  return (dwAttrib != INVALID_FILE_ATTRIBUTES && 
         (dwAttrib & FILE_ATTRIBUTE_DIRECTORY));
}

typedef struct {
    void *_Nonnull memory;
    size_t capacity;
    bool onStack;
} _ConditionalAllocationBuffer;

bool _resizeConditionalAllocationBuffer(_ConditionalAllocationBuffer *_Nonnull buffer, size_t amt);

bool _withStackOrHeapBuffer(size_t amount, void (__attribute__((noescape)) ^ _Nonnull applier)(_ConditionalAllocationBuffer *_Nonnull));


#if __LLP64__ || defined(_WIN64)
typedef unsigned long long CFTypeID;
typedef unsigned long long CFOptionFlags;
typedef unsigned long long CFHashCode;
typedef signed long long CFIndex;
#else
typedef unsigned int CFTypeID;
typedef unsigned int CFOptionFlags;
typedef unsigned int CFHashCode;
typedef signed int CFIndex;
#endif

#if defined(__cplusplus)
#define CF_EXPORT extern "C"
#else
#define CF_EXPORT
#endif


#include <inttypes.h>

// Forward declarations of internal CF functions.

typedef size_t CFDoubleHashCode;

CF_EXPORT CFHashCode CFHashBytes(uint8_t *_Nullable bytes, CFIndex length);
CF_EXPORT CFDoubleHashCode __CFHashDouble(double d);

CF_EXPORT bool regexSearch(const wchar_t *_Nonnull pattern, const wchar_t *_Nonnull string);

#endif /* CFoundationExtras_h */