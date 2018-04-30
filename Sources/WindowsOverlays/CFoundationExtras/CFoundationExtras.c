#include <malloc.h>
#include <math.h>
#include <limits.h>
#include "include/CFoundationExtras.h"

/* For use by NSNumber and CFNumber.
  Hashing algorithm for CFNumber:
  M = Max CFHashCode (assumed to be unsigned)
  For positive integral values: (N * HASHFACTOR) mod M
  For negative integral values: ((-N) * HASHFACTOR) mod M
  For floating point numbers that are not integral: hash(integral part) + hash(float part * M)
  HASHFACTOR is 2654435761, from Knuth's multiplicative method
*/
#define HASHFACTOR 2654435761U

inline CFHashCode _CFHashInt(long i) {
    return ((i > 0) ? (CFHashCode)(i) : (CFHashCode)(-i)) * HASHFACTOR;
}

inline CFDoubleHashCode _CFHashDouble(double d) {
    double dInt;
    if (d < 0) d = -d;
    dInt = floor(d+0.5);
    CFDoubleHashCode integralHash = HASHFACTOR * (CFDoubleHashCode)fmod(dInt, (double)ULLONG_MAX);
    return (CFDoubleHashCode)(integralHash + (CFDoubleHashCode)((d - dInt) * ULLONG_MAX));
}

CFDoubleHashCode __CFHashDouble(double d) {
    return _CFHashDouble(d);
}

bool _resizeConditionalAllocationBuffer(_ConditionalAllocationBuffer *_Nonnull buffer, size_t amt) {
#if TARGET_OS_MAC
    size_t amount = malloc_good_size(amt);
#else
    size_t amount = amt;
#endif
    if (amount <= buffer->capacity) { return true; }
    void *newMemory;
    if (buffer->onStack) {
        newMemory = malloc(amount);
        if (newMemory == NULL) { return false; }
        memcpy(newMemory, buffer->memory, buffer->capacity);
        buffer->onStack = false;
    } else {
        newMemory = realloc(buffer->memory, amount);
        if (newMemory == NULL) { return false; }
    }
    if (newMemory == NULL) { return false; }
    buffer->memory = newMemory;
    buffer->capacity = amount;
    return true;
}

bool _withStackOrHeapBuffer(size_t amount, void (__attribute__((noescape)) ^ _Nonnull applier)(_ConditionalAllocationBuffer *_Nonnull)) {
    _ConditionalAllocationBuffer buffer;
#if TARGET_OS_MAC
    buffer.capacity = malloc_good_size(amount);
#else
    buffer.capacity = amount;
#endif
    buffer.onStack = buffer.capacity < 2048;
    buffer.memory = buffer.onStack ? _alloca(buffer.capacity) : malloc(buffer.capacity);
    if (buffer.memory == NULL) { return false; }
    applier(&buffer);
    if (!buffer.onStack) {
        free(buffer.memory);
    }
    return true;
}


#define ELF_STEP(B) T1 = (H << 4) + B; T2 = T1 & 0xF0000000; if (T2) T1 ^= (T2 >> 24); T1 &= (~T2); H = T1;

CFHashCode CFHashBytes(uint8_t *bytes, CFIndex length) {
    /* The ELF hash algorithm, used in the ELF object file format */
    uint32_t H = 0, T1, T2;
    int32_t rem = length;
    while (3 < rem) {
	ELF_STEP(bytes[length - rem]);
	ELF_STEP(bytes[length - rem + 1]);
	ELF_STEP(bytes[length - rem + 2]);
	ELF_STEP(bytes[length - rem + 3]);
	rem -= 4;
    }
    switch (rem) {
    case 3:  ELF_STEP(bytes[length - 3]);
    case 2:  ELF_STEP(bytes[length - 2]);
    case 1:  ELF_STEP(bytes[length - 1]);
    case 0:  ;
    }
    return H;
}

#undef ELF_STEP