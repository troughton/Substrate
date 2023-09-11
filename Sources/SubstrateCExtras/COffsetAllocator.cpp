#include "include/COffsetAllocator.h"
#include "offsetAllocator.hpp"


COffsetAllocator *_Nonnull OffsetAllocator_New(uint32_t size, uint32_t maxAllocs) {
    return new OffsetAllocator::Allocator(size, maxAllocs);
}


void OffsetAllocator_Delete(COffsetAllocator *_Nonnull allocator) {
    delete allocator;
}

void OffsetAllocator_Reset(COffsetAllocator *_Nonnull allocator) {
    allocator->reset();
}

OffsetAllocatorAllocation OffsetAllocator_Allocate(COffsetAllocator *_Nonnull allocator, uint32_t size) {
    return allocator->allocate(size);
}

void OffsetAllocator_Free(COffsetAllocator *_Nonnull allocator, OffsetAllocatorAllocation allocation) {
    return allocator->free(allocation);
}

uint32_t OffsetAllocator_AllocationSize(COffsetAllocator *_Nonnull allocator, OffsetAllocatorAllocation allocation) {
    return allocator->allocationSize(allocation);
}

OffsetAllocatorStorageReport OffsetAllocator_StorageReport(COffsetAllocator *const _Nonnull allocator) {
    return allocator->storageReport();
}

OffsetAllocatorStorageReportFull OffsetAllocator_StorageReportFull(COffsetAllocator *const _Nonnull allocator) {
    return allocator->storageReportFull();
}
