#ifndef COffsetAllocator_h
#define COffsetAllocator_h

#ifdef __cplusplus
#include "../offsetAllocator.hpp"
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#ifdef USE_16_BIT_NODE_INDICES
typedef uint16_t NodeIndex;
#else
typedef uint32_t NodeIndex;
#endif

#ifdef __cplusplus
typedef OffsetAllocator::Allocation OffsetAllocatorAllocation;
typedef OffsetAllocator::StorageReport OffsetAllocatorStorageReport;
typedef OffsetAllocator::StorageReportFull OffsetAllocatorStorageReportFull;
typedef OffsetAllocator::Allocator COffsetAllocator;
#else
typedef struct OffsetAllocatorAllocation {
    uint32 offset;
    NodeIndex metadata;
} OffsetAllocatorAllocation;

typedef struct OffsetAllocatorStorageReport {
    uint32_t totalFreeSpace;
    uint32_t largestFreeRegion;
} OffsetAllocatorStorageReport;

typedef struct OffsetAllocatorStorageReportFull {
    typedef struct Region {
        uint32_t size;
        uint32_t count;
    } Region;
    
    Region freeRegions[32 * 8];
} OffsetAllocatorStorageReportFull;

typedef struct COffsetAllocator COffsetAllocator;
#endif


COffsetAllocator *_Nonnull OffsetAllocator_New(uint32_t size, uint32_t maxAllocs);
void OffsetAllocator_Delete(COffsetAllocator *_Nonnull allocator);
void OffsetAllocator_Reset(COffsetAllocator *_Nonnull allocator);

OffsetAllocatorAllocation OffsetAllocator_Allocate(COffsetAllocator *_Nonnull allocator, uint32_t size);
void OffsetAllocator_Free(COffsetAllocator *_Nonnull allocator, OffsetAllocatorAllocation allocation);

uint32_t OffsetAllocator_AllocationSize(COffsetAllocator *_Nonnull allocator, OffsetAllocatorAllocation allocation);
OffsetAllocatorStorageReport OffsetAllocator_StorageReport(COffsetAllocator *const _Nonnull allocator);
OffsetAllocatorStorageReportFull OffsetAllocator_StorageReportFull(COffsetAllocator *const _Nonnull allocator);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* COffsetAllocator_h */
