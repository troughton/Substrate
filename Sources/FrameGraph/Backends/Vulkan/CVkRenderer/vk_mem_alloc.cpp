#define VMA_IMPLEMENTATION
#include "include/vk_mem_alloc.h"

// For Visual Studio IntelliSense.
#ifdef __INTELLISENSE__
#define VMA_IMPLEMENTATION
#endif

#ifdef VMA_IMPLEMENTATION
#undef VMA_IMPLEMENTATION

#include <cstdint>
#include <cstdlib>
#include <cstring>

/*******************************************************************************
CONFIGURATION SECTION

Define some of these macros before each #include of this header or change them
here if you need other then default behavior depending on your environment.
*/

/*
Define this macro to 1 to make the library fetch pointers to Vulkan functions
internally, like:

    vulkanFunctions.vkAllocateMemory = &vkAllocateMemory;

Define to 0 if you are going to provide you own pointers to Vulkan functions via
VmaAllocatorCreateInfo::pVulkanFunctions.
*/
#if !defined(VMA_STATIC_VULKAN_FUNCTIONS) && !defined(VK_NO_PROTOTYPES)
#define VMA_STATIC_VULKAN_FUNCTIONS 1
#endif

// Define this macro to 1 to make the library use STL containers instead of its own implementation.
//#define VMA_USE_STL_CONTAINERS 1

/* Set this macro to 1 to make the library including and using STL containers:
std::pair, std::vector, std::list, std::unordered_map.

Set it to 0 or undefined to make the library using its own implementation of
the containers.
*/
#if VMA_USE_STL_CONTAINERS
   #define VMA_USE_STL_VECTOR 1
   #define VMA_USE_STL_UNORDERED_MAP 1
   #define VMA_USE_STL_LIST 1
#endif

#if VMA_USE_STL_VECTOR
   #include <vector>
#endif

#if VMA_USE_STL_UNORDERED_MAP
   #include <unordered_map>
#endif

#if VMA_USE_STL_LIST
   #include <list>
#endif

/*
Following headers are used in this CONFIGURATION section only, so feel free to
remove them if not needed.
*/
#include <cassert> // for assert
#include <algorithm> // for min, max
#include <mutex> // for std::mutex
#include <atomic> // for std::atomic

#if !defined(_WIN32) && !defined(__APPLE__)
    #include <malloc.h> // for aligned_alloc()
#endif

#ifndef VMA_NULL
   // Value used as null pointer. Define it to e.g.: nullptr, NULL, 0, (void*)0.
   #define VMA_NULL   nullptr
#endif

#if defined(__APPLE__) || defined(__ANDROID__)
#include <cstdlib>
void *aligned_alloc(size_t alignment, size_t size)
{
    // alignment must be >= sizeof(void*)
    if(alignment < sizeof(void*))
    {
        alignment = sizeof(void*);
    }

    void *pointer;
    if(posix_memalign(&pointer, alignment, size) == 0)
        return pointer;
    return VMA_NULL;
}
#endif

// Normal assert to check for programmer's errors, especially in Debug configuration.
#ifndef VMA_ASSERT
   #ifdef _DEBUG
       #define VMA_ASSERT(expr)         assert(expr)
   #else
       #define VMA_ASSERT(expr)
   #endif
#endif

// Assert that will be called very often, like inside data structures e.g. operator[].
// Making it non-empty can make program slow.
#ifndef VMA_HEAVY_ASSERT
   #ifdef _DEBUG
       #define VMA_HEAVY_ASSERT(expr)   //VMA_ASSERT(expr)
   #else
       #define VMA_HEAVY_ASSERT(expr)
   #endif
#endif

#ifndef VMA_ALIGN_OF
   #define VMA_ALIGN_OF(type)       (__alignof(type))
#endif

#ifndef VMA_SYSTEM_ALIGNED_MALLOC
   #if defined(_WIN32)
       #define VMA_SYSTEM_ALIGNED_MALLOC(size, alignment)   (_aligned_malloc((size), (alignment)))
   #else
       #define VMA_SYSTEM_ALIGNED_MALLOC(size, alignment)   (aligned_alloc((alignment), (size) ))
   #endif
#endif

#ifndef VMA_SYSTEM_FREE
   #if defined(_WIN32)
       #define VMA_SYSTEM_FREE(ptr)   _aligned_free(ptr)
   #else
       #define VMA_SYSTEM_FREE(ptr)   free(ptr)
   #endif
#endif

#ifndef VMA_MIN
   #define VMA_MIN(v1, v2)    (std::min((v1), (v2)))
#endif

#ifndef VMA_MAX
   #define VMA_MAX(v1, v2)    (std::max((v1), (v2)))
#endif

#ifndef VMA_SWAP
   #define VMA_SWAP(v1, v2)   std::swap((v1), (v2))
#endif

#ifndef VMA_SORT
   #define VMA_SORT(beg, end, cmp)  std::sort(beg, end, cmp)
#endif

#ifndef VMA_DEBUG_LOG
   #define VMA_DEBUG_LOG(format, ...)
   /*
   #define VMA_DEBUG_LOG(format, ...) do { \
       printf(format, __VA_ARGS__); \
       printf("\n"); \
   } while(false)
   */
#endif

// Define this macro to 1 to enable functions: vmaBuildStatsString, vmaFreeStatsString.
#if VMA_STATS_STRING_ENABLED
   static inline void VmaUint32ToStr(char* outStr, size_t strLen, uint32_t num)
   {
       snprintf(outStr, strLen, "%u", static_cast<unsigned int>(num));
   }
   static inline void VmaUint64ToStr(char* outStr, size_t strLen, uint64_t num)
   {
       snprintf(outStr, strLen, "%llu", static_cast<unsigned long long>(num));
   }
   static inline void VmaPtrToStr(char* outStr, size_t strLen, const void* ptr)
   {
       snprintf(outStr, strLen, "%p", ptr);
   }
#endif

#ifndef VMA_MUTEX
   class VmaMutex
   {
   public:
       VmaMutex() { }
       ~VmaMutex() { }
       void Lock() { m_Mutex.lock(); }
       void Unlock() { m_Mutex.unlock(); }
   private:
       std::mutex m_Mutex;
   };
   #define VMA_MUTEX VmaMutex
#endif

/*
If providing your own implementation, you need to implement a subset of std::atomic:

- Constructor(uint32_t desired)
- uint32_t load() const
- void store(uint32_t desired)
- bool compare_exchange_weak(uint32_t& expected, uint32_t desired)
*/
#ifndef VMA_ATOMIC_UINT32
   #define VMA_ATOMIC_UINT32 std::atomic<uint32_t>
#endif

#ifndef VMA_BEST_FIT
   /**
   Main parameter for function assessing how good is a free suballocation for a new
   allocation request.

   - Set to 1 to use Best-Fit algorithm - prefer smaller blocks, as close to the
     size of requested allocations as possible.
   - Set to 0 to use Worst-Fit algorithm - prefer larger blocks, as large as
     possible.

   Experiments in special testing environment showed that Best-Fit algorithm is
   better.
   */
   #define VMA_BEST_FIT (1)
#endif

#ifndef VMA_DEBUG_ALWAYS_DEDICATED_MEMORY
   /**
   Every allocation will have its own memory block.
   Define to 1 for debugging purposes only.
   */
   #define VMA_DEBUG_ALWAYS_DEDICATED_MEMORY (0)
#endif

#ifndef VMA_DEBUG_ALIGNMENT
   /**
   Minimum alignment of all suballocations, in bytes.
   Set to more than 1 for debugging purposes only. Must be power of two.
   */
   #define VMA_DEBUG_ALIGNMENT (1)
#endif

#ifndef VMA_DEBUG_MARGIN
   /**
   Minimum margin between suballocations, in bytes.
   Set nonzero for debugging purposes only.
   */
   #define VMA_DEBUG_MARGIN (0)
#endif

#ifndef VMA_DEBUG_GLOBAL_MUTEX
   /**
   Set this to 1 for debugging purposes only, to enable single mutex protecting all
   entry calls to the library. Can be useful for debugging multithreading issues.
   */
   #define VMA_DEBUG_GLOBAL_MUTEX (0)
#endif

#ifndef VMA_DEBUG_MIN_BUFFER_IMAGE_GRANULARITY
   /**
   Minimum value for VkPhysicalDeviceLimits::bufferImageGranularity.
   Set to more than 1 for debugging purposes only. Must be power of two.
   */
   #define VMA_DEBUG_MIN_BUFFER_IMAGE_GRANULARITY (1)
#endif

#ifndef VMA_SMALL_HEAP_MAX_SIZE
   /// Maximum size of a memory heap in Vulkan to consider it "small".
   #define VMA_SMALL_HEAP_MAX_SIZE (1024ull * 1024 * 1024)
#endif

#ifndef VMA_DEFAULT_LARGE_HEAP_BLOCK_SIZE
   /// Default size of a block allocated as single VkDeviceMemory from a "large" heap.
   #define VMA_DEFAULT_LARGE_HEAP_BLOCK_SIZE (256ull * 1024 * 1024)
#endif

static const uint32_t VMA_FRAME_INDEX_LOST = UINT32_MAX;

/*******************************************************************************
END OF CONFIGURATION
*/

static VkAllocationCallbacks VmaEmptyAllocationCallbacks = {
    VMA_NULL, VMA_NULL, VMA_NULL, VMA_NULL, VMA_NULL, VMA_NULL };

// Returns number of bits set to 1 in (v).
static inline uint32_t VmaCountBitsSet(uint32_t v)
{
	uint32_t c = v - ((v >> 1) & 0x55555555);
	c = ((c >>  2) & 0x33333333) + (c & 0x33333333);
	c = ((c >>  4) + c) & 0x0F0F0F0F;
	c = ((c >>  8) + c) & 0x00FF00FF;
	c = ((c >> 16) + c) & 0x0000FFFF;
	return c;
}

// Aligns given value up to nearest multiply of align value. For example: VmaAlignUp(11, 8) = 16.
// Use types like uint32_t, uint64_t as T.
template <typename T>
static inline T VmaAlignUp(T val, T align)
{
	return (val + align - 1) / align * align;
}

// Division with mathematical rounding to nearest number.
template <typename T>
inline T VmaRoundDiv(T x, T y)
{
	return (x + (y / (T)2)) / y;
}

#ifndef VMA_SORT

template<typename Iterator, typename Compare>
Iterator VmaQuickSortPartition(Iterator beg, Iterator end, Compare cmp)
{
    Iterator centerValue = end; --centerValue;
    Iterator insertIndex = beg;
    for(Iterator memTypeIndex = beg; memTypeIndex < centerValue; ++memTypeIndex)
    {
        if(cmp(*memTypeIndex, *centerValue))
        {
            if(insertIndex != memTypeIndex)
            {
                VMA_SWAP(*memTypeIndex, *insertIndex);
            }
            ++insertIndex;
        }
    }
    if(insertIndex != centerValue)
    {
        VMA_SWAP(*insertIndex, *centerValue);
    }
    return insertIndex;
}

template<typename Iterator, typename Compare>
void VmaQuickSort(Iterator beg, Iterator end, Compare cmp)
{
    if(beg < end)
    {
        Iterator it = VmaQuickSortPartition<Iterator, Compare>(beg, end, cmp);
        VmaQuickSort<Iterator, Compare>(beg, it, cmp);
        VmaQuickSort<Iterator, Compare>(it + 1, end, cmp);
    }
}

#define VMA_SORT(beg, end, cmp) VmaQuickSort(beg, end, cmp)

#endif // #ifndef VMA_SORT

/*
Returns true if two memory blocks occupy overlapping pages.
ResourceA must be in less memory offset than ResourceB.

Algorithm is based on "Vulkan 1.0.39 - A Specification (with all registered Vulkan extensions)"
chapter 11.6 "Resource Memory Association", paragraph "Buffer-Image Granularity".
*/
static inline bool VmaBlocksOnSamePage(
    VkDeviceSize resourceAOffset,
    VkDeviceSize resourceASize,
    VkDeviceSize resourceBOffset,
    VkDeviceSize pageSize)
{
    VMA_ASSERT(resourceAOffset + resourceASize <= resourceBOffset && resourceASize > 0 && pageSize > 0);
    VkDeviceSize resourceAEnd = resourceAOffset + resourceASize - 1;
    VkDeviceSize resourceAEndPage = resourceAEnd & ~(pageSize - 1);
    VkDeviceSize resourceBStart = resourceBOffset;
    VkDeviceSize resourceBStartPage = resourceBStart & ~(pageSize - 1);
    return resourceAEndPage == resourceBStartPage;
}

enum VmaSuballocationType
{
    VMA_SUBALLOCATION_TYPE_FREE = 0,
    VMA_SUBALLOCATION_TYPE_UNKNOWN = 1,
    VMA_SUBALLOCATION_TYPE_BUFFER = 2,
    VMA_SUBALLOCATION_TYPE_IMAGE_UNKNOWN = 3,
    VMA_SUBALLOCATION_TYPE_IMAGE_LINEAR = 4,
    VMA_SUBALLOCATION_TYPE_IMAGE_OPTIMAL = 5,
    VMA_SUBALLOCATION_TYPE_MAX_ENUM = 0x7FFFFFFF
};

/*
Returns true if given suballocation types could conflict and must respect
VkPhysicalDeviceLimits::bufferImageGranularity. They conflict if one is buffer
or linear image and another one is optimal image. If type is unknown, behave
conservatively.
*/
static inline bool VmaIsBufferImageGranularityConflict(
    VmaSuballocationType suballocType1,
    VmaSuballocationType suballocType2)
{
    if(suballocType1 > suballocType2)
    {
        VMA_SWAP(suballocType1, suballocType2);
    }
    
    switch(suballocType1)
    {
    case VMA_SUBALLOCATION_TYPE_FREE:
        return false;
    case VMA_SUBALLOCATION_TYPE_UNKNOWN:
        return true;
    case VMA_SUBALLOCATION_TYPE_BUFFER:
        return
            suballocType2 == VMA_SUBALLOCATION_TYPE_IMAGE_UNKNOWN ||
            suballocType2 == VMA_SUBALLOCATION_TYPE_IMAGE_OPTIMAL;
    case VMA_SUBALLOCATION_TYPE_IMAGE_UNKNOWN:
        return
            suballocType2 == VMA_SUBALLOCATION_TYPE_IMAGE_UNKNOWN ||
            suballocType2 == VMA_SUBALLOCATION_TYPE_IMAGE_LINEAR ||
            suballocType2 == VMA_SUBALLOCATION_TYPE_IMAGE_OPTIMAL;
    case VMA_SUBALLOCATION_TYPE_IMAGE_LINEAR:
        return
            suballocType2 == VMA_SUBALLOCATION_TYPE_IMAGE_OPTIMAL;
    case VMA_SUBALLOCATION_TYPE_IMAGE_OPTIMAL:
        return false;
    default:
        VMA_ASSERT(0);
        return true;
    }
}

// Helper RAII class to lock a mutex in constructor and unlock it in destructor (at the end of scope).
struct VmaMutexLock
{
public:
    VmaMutexLock(VMA_MUTEX& mutex, bool useMutex) :
        m_pMutex(useMutex ? &mutex : VMA_NULL)
    {
        if(m_pMutex)
        {
            m_pMutex->Lock();
        }
    }
    
    ~VmaMutexLock()
    {
        if(m_pMutex)
        {
            m_pMutex->Unlock();
        }
    }

private:
    VMA_MUTEX* m_pMutex;
};

#if VMA_DEBUG_GLOBAL_MUTEX
    static VMA_MUTEX gDebugGlobalMutex;
    #define VMA_DEBUG_GLOBAL_MUTEX_LOCK VmaMutexLock debugGlobalMutexLock(gDebugGlobalMutex, true);
#else
    #define VMA_DEBUG_GLOBAL_MUTEX_LOCK
#endif

// Minimum size of a free suballocation to register it in the free suballocation collection.
static const VkDeviceSize VMA_MIN_FREE_SUBALLOCATION_SIZE_TO_REGISTER = 16;

/*
Performs binary search and returns iterator to first element that is greater or
equal to (key), according to comparison (cmp).

Cmp should return true if first argument is less than second argument.

Returned value is the found element, if present in the collection or place where
new element with value (key) should be inserted.
*/
template <typename IterT, typename KeyT, typename CmpT>
static IterT VmaBinaryFindFirstNotLess(IterT beg, IterT end, const KeyT &key, CmpT cmp)
{
   size_t down = 0, up = (end - beg);
   while(down < up)
   {
      const size_t mid = (down + up) / 2;
      if(cmp(*(beg+mid), key))
      {
         down = mid + 1;
      }
      else
      {
         up = mid;
      }
   }
   return beg + down;
}

////////////////////////////////////////////////////////////////////////////////
// Memory allocation

static void* VmaMalloc(const VkAllocationCallbacks* pAllocationCallbacks, size_t size, size_t alignment)
{
    if((pAllocationCallbacks != VMA_NULL) &&
        (pAllocationCallbacks->pfnAllocation != VMA_NULL))
    {
        return (*pAllocationCallbacks->pfnAllocation)(
            pAllocationCallbacks->pUserData,
            size,
            alignment,
            VK_SYSTEM_ALLOCATION_SCOPE_OBJECT);
    }
    else
    {
        return VMA_SYSTEM_ALIGNED_MALLOC(size, alignment);
    }
}

static void VmaFree(const VkAllocationCallbacks* pAllocationCallbacks, void* ptr)
{
    if((pAllocationCallbacks != VMA_NULL) &&
        (pAllocationCallbacks->pfnFree != VMA_NULL))
    {
        (*pAllocationCallbacks->pfnFree)(pAllocationCallbacks->pUserData, ptr);
    }
    else
    {
        VMA_SYSTEM_FREE(ptr);
    }
}

template<typename T>
static T* VmaAllocate(const VkAllocationCallbacks* pAllocationCallbacks)
{
    return (T*)VmaMalloc(pAllocationCallbacks, sizeof(T), VMA_ALIGN_OF(T));
}

template<typename T>
static T* VmaAllocateArray(const VkAllocationCallbacks* pAllocationCallbacks, size_t count)
{
    return (T*)VmaMalloc(pAllocationCallbacks, sizeof(T) * count, VMA_ALIGN_OF(T));
}

#define vma_new(allocator, type)   new(VmaAllocate<type>(allocator))(type)

#define vma_new_array(allocator, type, count)   new(VmaAllocateArray<type>((allocator), (count)))(type)

template<typename T>
static void vma_delete(const VkAllocationCallbacks* pAllocationCallbacks, T* ptr)
{
    ptr->~T();
    VmaFree(pAllocationCallbacks, ptr);
}

template<typename T>
static void vma_delete_array(const VkAllocationCallbacks* pAllocationCallbacks, T* ptr, size_t count)
{
    if(ptr != VMA_NULL)
    {
        for(size_t i = count; i--; )
        {
            ptr[i].~T();
        }
        VmaFree(pAllocationCallbacks, ptr);
    }
}

// STL-compatible allocator.
template<typename T>
class VmaStlAllocator
{
public:
    const VkAllocationCallbacks* const m_pCallbacks;
    typedef T value_type;
    
    VmaStlAllocator(const VkAllocationCallbacks* pCallbacks) : m_pCallbacks(pCallbacks) { }
    template<typename U> VmaStlAllocator(const VmaStlAllocator<U>& src) : m_pCallbacks(src.m_pCallbacks) { }

    T* allocate(size_t n) { return VmaAllocateArray<T>(m_pCallbacks, n); }
    void deallocate(T* p, size_t n) { VmaFree(m_pCallbacks, p); }

    template<typename U>
    bool operator==(const VmaStlAllocator<U>& rhs) const
    {
        return m_pCallbacks == rhs.m_pCallbacks;
    }
    template<typename U>
    bool operator!=(const VmaStlAllocator<U>& rhs) const
    {
        return m_pCallbacks != rhs.m_pCallbacks;
    }

    VmaStlAllocator& operator=(const VmaStlAllocator& x) = delete;
};

#if VMA_USE_STL_VECTOR

#define VmaVector std::vector

template<typename T, typename allocatorT>
static void VmaVectorInsert(std::vector<T, allocatorT>& vec, size_t index, const T& item)
{
    vec.insert(vec.begin() + index, item);
}

template<typename T, typename allocatorT>
static void VmaVectorRemove(std::vector<T, allocatorT>& vec, size_t index)
{
    vec.erase(vec.begin() + index);
}

#else // #if VMA_USE_STL_VECTOR

/* Class with interface compatible with subset of std::vector.
T must be POD because constructors and destructors are not called and memcpy is
used for these objects. */
template<typename T, typename AllocatorT>
class VmaVector
{
public:
    typedef T value_type;

    VmaVector(const AllocatorT& allocator) :
        m_Allocator(allocator),
        m_pArray(VMA_NULL),
        m_Count(0),
        m_Capacity(0)
    {
    }

    VmaVector(size_t count, const AllocatorT& allocator) :
        m_Allocator(allocator),
        m_pArray(count ? (T*)VmaAllocateArray<T>(allocator.m_pCallbacks, count) : VMA_NULL),
        m_Count(count),
        m_Capacity(count)
    {
    }
    
    VmaVector(const VmaVector<T, AllocatorT>& src) :
        m_Allocator(src.m_Allocator),
        m_pArray(src.m_Count ? (T*)VmaAllocateArray<T>(src.m_Allocator.m_pCallbacks, src.m_Count) : VMA_NULL),
        m_Count(src.m_Count),
        m_Capacity(src.m_Count)
    {
        if(m_Count != 0)
        {
            memcpy(m_pArray, src.m_pArray, m_Count * sizeof(T));
        }
    }
    
    ~VmaVector()
    {
        VmaFree(m_Allocator.m_pCallbacks, m_pArray);
    }

    VmaVector& operator=(const VmaVector<T, AllocatorT>& rhs)
    {
        if(&rhs != this)
        {
            resize(rhs.m_Count);
            if(m_Count != 0)
            {
                memcpy(m_pArray, rhs.m_pArray, m_Count * sizeof(T));
            }
        }
        return *this;
    }
    
    bool empty() const { return m_Count == 0; }
    size_t size() const { return m_Count; }
    T* data() { return m_pArray; }
    const T* data() const { return m_pArray; }
    
    T& operator[](size_t index)
    {
        VMA_HEAVY_ASSERT(index < m_Count);
        return m_pArray[index];
    }
    const T& operator[](size_t index) const
    {
        VMA_HEAVY_ASSERT(index < m_Count);
        return m_pArray[index];
    }

    T& front()
    {
        VMA_HEAVY_ASSERT(m_Count > 0);
        return m_pArray[0];
    }
    const T& front() const
    {
        VMA_HEAVY_ASSERT(m_Count > 0);
        return m_pArray[0];
    }
    T& back()
    {
        VMA_HEAVY_ASSERT(m_Count > 0);
        return m_pArray[m_Count - 1];
    }
    const T& back() const
    {
        VMA_HEAVY_ASSERT(m_Count > 0);
        return m_pArray[m_Count - 1];
    }

    void reserve(size_t newCapacity, bool freeMemory = false)
    {
        newCapacity = VMA_MAX(newCapacity, m_Count);
        
        if((newCapacity < m_Capacity) && !freeMemory)
        {
            newCapacity = m_Capacity;
        }
        
        if(newCapacity != m_Capacity)
        {
            T* const newArray = newCapacity ? VmaAllocateArray<T>(m_Allocator, newCapacity) : VMA_NULL;
            if(m_Count != 0)
            {
                memcpy(newArray, m_pArray, m_Count * sizeof(T));
            }
            VmaFree(m_Allocator.m_pCallbacks, m_pArray);
            m_Capacity = newCapacity;
            m_pArray = newArray;
        }
    }

    void resize(size_t newCount, bool freeMemory = false)
    {
        size_t newCapacity = m_Capacity;
        if(newCount > m_Capacity)
        {
            newCapacity = VMA_MAX(newCount, VMA_MAX(m_Capacity * 3 / 2, (size_t)8));
        }
        else if(freeMemory)
        {
            newCapacity = newCount;
        }

        if(newCapacity != m_Capacity)
        {
            T* const newArray = newCapacity ? VmaAllocateArray<T>(m_Allocator.m_pCallbacks, newCapacity) : VMA_NULL;
            const size_t elementsToCopy = VMA_MIN(m_Count, newCount);
            if(elementsToCopy != 0)
            {
                memcpy(newArray, m_pArray, elementsToCopy * sizeof(T));
            }
            VmaFree(m_Allocator.m_pCallbacks, m_pArray);
            m_Capacity = newCapacity;
            m_pArray = newArray;
        }

        m_Count = newCount;
    }

    void clear(bool freeMemory = false)
    {
        resize(0, freeMemory);
    }

    void insert(size_t index, const T& src)
    {
        VMA_HEAVY_ASSERT(index <= m_Count);
        const size_t oldCount = size();
        resize(oldCount + 1);
        if(index < oldCount)
        {
            memmove(m_pArray + (index + 1), m_pArray + index, (oldCount - index) * sizeof(T));
        }
        m_pArray[index] = src;
    }

    void remove(size_t index)
    {
        VMA_HEAVY_ASSERT(index < m_Count);
        const size_t oldCount = size();
        if(index < oldCount - 1)
        {
            memmove(m_pArray + index, m_pArray + (index + 1), (oldCount - index - 1) * sizeof(T));
        }
        resize(oldCount - 1);
    }

    void push_back(const T& src)
    {
        const size_t newIndex = size();
        resize(newIndex + 1);
        m_pArray[newIndex] = src;
    }

    void pop_back()
    {
        VMA_HEAVY_ASSERT(m_Count > 0);
        resize(size() - 1);
    }

    void push_front(const T& src)
    {
        insert(0, src);
    }

    void pop_front()
    {
        VMA_HEAVY_ASSERT(m_Count > 0);
        remove(0);
    }

    typedef T* iterator;

    iterator begin() { return m_pArray; }
    iterator end() { return m_pArray + m_Count; }

private:
    AllocatorT m_Allocator;
    T* m_pArray;
    size_t m_Count;
    size_t m_Capacity;
};

template<typename T, typename allocatorT>
static void VmaVectorInsert(VmaVector<T, allocatorT>& vec, size_t index, const T& item)
{
    vec.insert(index, item);
}

template<typename T, typename allocatorT>
static void VmaVectorRemove(VmaVector<T, allocatorT>& vec, size_t index)
{
    vec.remove(index);
}

#endif // #if VMA_USE_STL_VECTOR

template<typename CmpLess, typename VectorT>
size_t VmaVectorInsertSorted(VectorT& vector, const typename VectorT::value_type& value)
{
    const size_t indexToInsert = VmaBinaryFindFirstNotLess(
        vector.data(),
        vector.data() + vector.size(),
        value,
        CmpLess()) - vector.data();
    VmaVectorInsert(vector, indexToInsert, value);
    return indexToInsert;
}

template<typename CmpLess, typename VectorT>
bool VmaVectorRemoveSorted(VectorT& vector, const typename VectorT::value_type& value)
{
    CmpLess comparator;
    typename VectorT::iterator it = VmaBinaryFindFirstNotLess(
        vector.begin(),
        vector.end(),
        value,
        comparator);
    if((it != vector.end()) && !comparator(*it, value) && !comparator(value, *it))
    {
        size_t indexToRemove = it - vector.begin();
        VmaVectorRemove(vector, indexToRemove);
        return true;
    }
    return false;
}

template<typename CmpLess, typename VectorT>
size_t VmaVectorFindSorted(const VectorT& vector, const typename VectorT::value_type& value)
{
    CmpLess comparator;
    typename VectorT::iterator it = VmaBinaryFindFirstNotLess(
        vector.data(),
        vector.data() + vector.size(),
        value,
        comparator);
    if(it != vector.size() && !comparator(*it, value) && !comparator(value, *it))
    {
        return it - vector.begin();
    }
    else
    {
        return vector.size();
    }
}

////////////////////////////////////////////////////////////////////////////////
// class VmaPoolAllocator

/*
Allocator for objects of type T using a list of arrays (pools) to speed up
allocation. Number of elements that can be allocated is not bounded because
allocator can create multiple blocks.
*/
template<typename T>
class VmaPoolAllocator
{
public:
    VmaPoolAllocator(const VkAllocationCallbacks* pAllocationCallbacks, size_t itemsPerBlock);
    ~VmaPoolAllocator();
    void Clear();
    T* Alloc();
    void Free(T* ptr);

private:
    union Item
    {
        uint32_t NextFreeIndex;
        T Value;
    };

    struct ItemBlock
    {
        Item* pItems;
        uint32_t FirstFreeIndex;
    };
    
    const VkAllocationCallbacks* m_pAllocationCallbacks;
    size_t m_ItemsPerBlock;
    VmaVector< ItemBlock, VmaStlAllocator<ItemBlock> > m_ItemBlocks;

    ItemBlock& CreateNewBlock();
};

template<typename T>
VmaPoolAllocator<T>::VmaPoolAllocator(const VkAllocationCallbacks* pAllocationCallbacks, size_t itemsPerBlock) :
    m_pAllocationCallbacks(pAllocationCallbacks),
    m_ItemsPerBlock(itemsPerBlock),
    m_ItemBlocks(VmaStlAllocator<ItemBlock>(pAllocationCallbacks))
{
    VMA_ASSERT(itemsPerBlock > 0);
}

template<typename T>
VmaPoolAllocator<T>::~VmaPoolAllocator()
{
    Clear();
}

template<typename T>
void VmaPoolAllocator<T>::Clear()
{
    for(size_t i = m_ItemBlocks.size(); i--; )
        vma_delete_array(m_pAllocationCallbacks, m_ItemBlocks[i].pItems, m_ItemsPerBlock);
    m_ItemBlocks.clear();
}

template<typename T>
T* VmaPoolAllocator<T>::Alloc()
{
    for(size_t i = m_ItemBlocks.size(); i--; )
    {
        ItemBlock& block = m_ItemBlocks[i];
        // This block has some free items: Use first one.
        if(block.FirstFreeIndex != UINT32_MAX)
        {
            Item* const pItem = &block.pItems[block.FirstFreeIndex];
            block.FirstFreeIndex = pItem->NextFreeIndex;
            return &pItem->Value;
        }
    }

    // No block has free item: Create new one and use it.
    ItemBlock& newBlock = CreateNewBlock();
    Item* const pItem = &newBlock.pItems[0];
    newBlock.FirstFreeIndex = pItem->NextFreeIndex;
    return &pItem->Value;
}

template<typename T>
void VmaPoolAllocator<T>::Free(T* ptr)
{
    // Search all memory blocks to find ptr.
    for(size_t i = 0; i < m_ItemBlocks.size(); ++i)
    {
        ItemBlock& block = m_ItemBlocks[i];
        
        // Casting to union.
        Item* pItemPtr;
        memcpy(&pItemPtr, &ptr, sizeof(pItemPtr));
        
        // Check if pItemPtr is in address range of this block.
        if((pItemPtr >= block.pItems) && (pItemPtr < block.pItems + m_ItemsPerBlock))
        {
            const uint32_t index = static_cast<uint32_t>(pItemPtr - block.pItems);
            pItemPtr->NextFreeIndex = block.FirstFreeIndex;
            block.FirstFreeIndex = index;
            return;
        }
    }
    VMA_ASSERT(0 && "Pointer doesn't belong to this memory pool.");
}

template<typename T>
typename VmaPoolAllocator<T>::ItemBlock& VmaPoolAllocator<T>::CreateNewBlock()
{
    ItemBlock newBlock = {
        vma_new_array(m_pAllocationCallbacks, Item, m_ItemsPerBlock), 0 };

    m_ItemBlocks.push_back(newBlock);

    // Setup singly-linked list of all free items in this block.
    for(uint32_t i = 0; i < m_ItemsPerBlock - 1; ++i)
        newBlock.pItems[i].NextFreeIndex = i + 1;
    newBlock.pItems[m_ItemsPerBlock - 1].NextFreeIndex = UINT32_MAX;
    return m_ItemBlocks.back();
}

////////////////////////////////////////////////////////////////////////////////
// class VmaRawList, VmaList

#if VMA_USE_STL_LIST

#define VmaList std::list

#else // #if VMA_USE_STL_LIST

template<typename T>
struct VmaListItem
{
    VmaListItem* pPrev;
    VmaListItem* pNext;
    T Value;
};

// Doubly linked list.
template<typename T>
class VmaRawList
{
public:
    typedef VmaListItem<T> ItemType;

    VmaRawList(const VkAllocationCallbacks* pAllocationCallbacks);
    ~VmaRawList();
    void Clear();

    size_t GetCount() const { return m_Count; }
    bool IsEmpty() const { return m_Count == 0; }

    ItemType* Front() { return m_pFront; }
    const ItemType* Front() const { return m_pFront; }
    ItemType* Back() { return m_pBack; }
    const ItemType* Back() const { return m_pBack; }

    ItemType* PushBack();
    ItemType* PushFront();
    ItemType* PushBack(const T& value);
    ItemType* PushFront(const T& value);
    void PopBack();
    void PopFront();
    
    // Item can be null - it means PushBack.
    ItemType* InsertBefore(ItemType* pItem);
    // Item can be null - it means PushFront.
    ItemType* InsertAfter(ItemType* pItem);

    ItemType* InsertBefore(ItemType* pItem, const T& value);
    ItemType* InsertAfter(ItemType* pItem, const T& value);

    void Remove(ItemType* pItem);

private:
    const VkAllocationCallbacks* const m_pAllocationCallbacks;
    VmaPoolAllocator<ItemType> m_ItemAllocator;
    ItemType* m_pFront;
    ItemType* m_pBack;
    size_t m_Count;

    // Declared not defined, to block copy constructor and assignment operator.
    VmaRawList(const VmaRawList<T>& src);
    VmaRawList<T>& operator=(const VmaRawList<T>& rhs);
};

template<typename T>
VmaRawList<T>::VmaRawList(const VkAllocationCallbacks* pAllocationCallbacks) :
    m_pAllocationCallbacks(pAllocationCallbacks),
    m_ItemAllocator(pAllocationCallbacks, 128),
    m_pFront(VMA_NULL),
    m_pBack(VMA_NULL),
    m_Count(0)
{
}

template<typename T>
VmaRawList<T>::~VmaRawList()
{
    // Intentionally not calling Clear, because that would be unnecessary
    // computations to return all items to m_ItemAllocator as free.
}

template<typename T>
void VmaRawList<T>::Clear()
{
    if(IsEmpty() == false)
    {
        ItemType* pItem = m_pBack;
        while(pItem != VMA_NULL)
        {
            ItemType* const pPrevItem = pItem->pPrev;
            m_ItemAllocator.Free(pItem);
            pItem = pPrevItem;
        }
        m_pFront = VMA_NULL;
        m_pBack = VMA_NULL;
        m_Count = 0;
    }
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::PushBack()
{
    ItemType* const pNewItem = m_ItemAllocator.Alloc();
    pNewItem->pNext = VMA_NULL;
    if(IsEmpty())
    {
        pNewItem->pPrev = VMA_NULL;
        m_pFront = pNewItem;
        m_pBack = pNewItem;
        m_Count = 1;
    }
    else
    {
        pNewItem->pPrev = m_pBack;
        m_pBack->pNext = pNewItem;
        m_pBack = pNewItem;
        ++m_Count;
    }
    return pNewItem;
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::PushFront()
{
    ItemType* const pNewItem = m_ItemAllocator.Alloc();
    pNewItem->pPrev = VMA_NULL;
    if(IsEmpty())
    {
        pNewItem->pNext = VMA_NULL;
        m_pFront = pNewItem;
        m_pBack = pNewItem;
        m_Count = 1;
    }
    else
    {
        pNewItem->pNext = m_pFront;
        m_pFront->pPrev = pNewItem;
        m_pFront = pNewItem;
        ++m_Count;
    }
    return pNewItem;
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::PushBack(const T& value)
{
    ItemType* const pNewItem = PushBack();
    pNewItem->Value = value;
    return pNewItem;
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::PushFront(const T& value)
{
    ItemType* const pNewItem = PushFront();
    pNewItem->Value = value;
    return pNewItem;
}

template<typename T>
void VmaRawList<T>::PopBack()
{
    VMA_HEAVY_ASSERT(m_Count > 0);
    ItemType* const pBackItem = m_pBack;
    ItemType* const pPrevItem = pBackItem->pPrev;
    if(pPrevItem != VMA_NULL)
    {
        pPrevItem->pNext = VMA_NULL;
    }
    m_pBack = pPrevItem;
    m_ItemAllocator.Free(pBackItem);
    --m_Count;
}

template<typename T>
void VmaRawList<T>::PopFront()
{
    VMA_HEAVY_ASSERT(m_Count > 0);
    ItemType* const pFrontItem = m_pFront;
    ItemType* const pNextItem = pFrontItem->pNext;
    if(pNextItem != VMA_NULL)
    {
        pNextItem->pPrev = VMA_NULL;
    }
    m_pFront = pNextItem;
    m_ItemAllocator.Free(pFrontItem);
    --m_Count;
}

template<typename T>
void VmaRawList<T>::Remove(ItemType* pItem)
{
    VMA_HEAVY_ASSERT(pItem != VMA_NULL);
    VMA_HEAVY_ASSERT(m_Count > 0);

    if(pItem->pPrev != VMA_NULL)
    {
        pItem->pPrev->pNext = pItem->pNext;
    }
    else
    {
        VMA_HEAVY_ASSERT(m_pFront == pItem);
        m_pFront = pItem->pNext;
    }

    if(pItem->pNext != VMA_NULL)
    {
        pItem->pNext->pPrev = pItem->pPrev;
    }
    else
    {
        VMA_HEAVY_ASSERT(m_pBack == pItem);
        m_pBack = pItem->pPrev;
    }

    m_ItemAllocator.Free(pItem);
    --m_Count;
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::InsertBefore(ItemType* pItem)
{
    if(pItem != VMA_NULL)
    {
        ItemType* const prevItem = pItem->pPrev;
        ItemType* const newItem = m_ItemAllocator.Alloc();
        newItem->pPrev = prevItem;
        newItem->pNext = pItem;
        pItem->pPrev = newItem;
        if(prevItem != VMA_NULL)
        {
            prevItem->pNext = newItem;
        }
        else
        {
            VMA_HEAVY_ASSERT(m_pFront == pItem);
            m_pFront = newItem;
        }
        ++m_Count;
        return newItem;
    }
    else
        return PushBack();
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::InsertAfter(ItemType* pItem)
{
    if(pItem != VMA_NULL)
    {
        ItemType* const nextItem = pItem->pNext;
        ItemType* const newItem = m_ItemAllocator.Alloc();
        newItem->pNext = nextItem;
        newItem->pPrev = pItem;
        pItem->pNext = newItem;
        if(nextItem != VMA_NULL)
        {
            nextItem->pPrev = newItem;
        }
        else
        {
            VMA_HEAVY_ASSERT(m_pBack == pItem);
            m_pBack = newItem;
        }
        ++m_Count;
        return newItem;
    }
    else
        return PushFront();
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::InsertBefore(ItemType* pItem, const T& value)
{
    ItemType* const newItem = InsertBefore(pItem);
    newItem->Value = value;
    return newItem;
}

template<typename T>
VmaListItem<T>* VmaRawList<T>::InsertAfter(ItemType* pItem, const T& value)
{
    ItemType* const newItem = InsertAfter(pItem);
    newItem->Value = value;
    return newItem;
}

template<typename T, typename AllocatorT>
class VmaList
{
public:
    class iterator
    {
    public:
        iterator() :
            m_pList(VMA_NULL),
            m_pItem(VMA_NULL)
        {
        }

        T& operator*() const
        {
            VMA_HEAVY_ASSERT(m_pItem != VMA_NULL);
            return m_pItem->Value;
        }
        T* operator->() const
        {
            VMA_HEAVY_ASSERT(m_pItem != VMA_NULL);
            return &m_pItem->Value;
        }

        iterator& operator++()
        {
            VMA_HEAVY_ASSERT(m_pItem != VMA_NULL);
            m_pItem = m_pItem->pNext;
            return *this;
        }
        iterator& operator--()
        {
            if(m_pItem != VMA_NULL)
            {
                m_pItem = m_pItem->pPrev;
            }
            else
            {
                VMA_HEAVY_ASSERT(!m_pList->IsEmpty());
                m_pItem = m_pList->Back();
            }
            return *this;
        }

        iterator operator++(int)
        {
            iterator result = *this;
            ++*this;
            return result;
        }
        iterator operator--(int)
        {
            iterator result = *this;
            --*this;
            return result;
        }

        bool operator==(const iterator& rhs) const
        {
            VMA_HEAVY_ASSERT(m_pList == rhs.m_pList);
            return m_pItem == rhs.m_pItem;
        }
        bool operator!=(const iterator& rhs) const
        {
            VMA_HEAVY_ASSERT(m_pList == rhs.m_pList);
            return m_pItem != rhs.m_pItem;
        }
        
    private:
        VmaRawList<T>* m_pList;
        VmaListItem<T>* m_pItem;

        iterator(VmaRawList<T>* pList, VmaListItem<T>* pItem) :
            m_pList(pList),
            m_pItem(pItem)
        {
        }

        friend class VmaList<T, AllocatorT>;
    };

    class const_iterator
    {
    public:
        const_iterator() :
            m_pList(VMA_NULL),
            m_pItem(VMA_NULL)
        {
        }

        const_iterator(const iterator& src) :
            m_pList(src.m_pList),
            m_pItem(src.m_pItem)
        {
        }
        
        const T& operator*() const
        {
            VMA_HEAVY_ASSERT(m_pItem != VMA_NULL);
            return m_pItem->Value;
        }
        const T* operator->() const
        {
            VMA_HEAVY_ASSERT(m_pItem != VMA_NULL);
            return &m_pItem->Value;
        }

        const_iterator& operator++()
        {
            VMA_HEAVY_ASSERT(m_pItem != VMA_NULL);
            m_pItem = m_pItem->pNext;
            return *this;
        }
        const_iterator& operator--()
        {
            if(m_pItem != VMA_NULL)
            {
                m_pItem = m_pItem->pPrev;
            }
            else
            {
                VMA_HEAVY_ASSERT(!m_pList->IsEmpty());
                m_pItem = m_pList->Back();
            }
            return *this;
        }

        const_iterator operator++(int)
        {
            const_iterator result = *this;
            ++*this;
            return result;
        }
        const_iterator operator--(int)
        {
            const_iterator result = *this;
            --*this;
            return result;
        }

        bool operator==(const const_iterator& rhs) const
        {
            VMA_HEAVY_ASSERT(m_pList == rhs.m_pList);
            return m_pItem == rhs.m_pItem;
        }
        bool operator!=(const const_iterator& rhs) const
        {
            VMA_HEAVY_ASSERT(m_pList == rhs.m_pList);
            return m_pItem != rhs.m_pItem;
        }
        
    private:
        const_iterator(const VmaRawList<T>* pList, const VmaListItem<T>* pItem) :
            m_pList(pList),
            m_pItem(pItem)
        {
        }

        const VmaRawList<T>* m_pList;
        const VmaListItem<T>* m_pItem;

        friend class VmaList<T, AllocatorT>;
    };

    VmaList(const AllocatorT& allocator) : m_RawList(allocator.m_pCallbacks) { }

    bool empty() const { return m_RawList.IsEmpty(); }
    size_t size() const { return m_RawList.GetCount(); }

    iterator begin() { return iterator(&m_RawList, m_RawList.Front()); }
    iterator end() { return iterator(&m_RawList, VMA_NULL); }

    const_iterator cbegin() const { return const_iterator(&m_RawList, m_RawList.Front()); }
    const_iterator cend() const { return const_iterator(&m_RawList, VMA_NULL); }

    void clear() { m_RawList.Clear(); }
    void push_back(const T& value) { m_RawList.PushBack(value); }
    void erase(iterator it) { m_RawList.Remove(it.m_pItem); }
    iterator insert(iterator it, const T& value) { return iterator(&m_RawList, m_RawList.InsertBefore(it.m_pItem, value)); }

private:
    VmaRawList<T> m_RawList;
};

#endif // #if VMA_USE_STL_LIST

////////////////////////////////////////////////////////////////////////////////
// class VmaMap

// Unused in this version.
#if 0

#if VMA_USE_STL_UNORDERED_MAP

#define VmaPair std::pair

#define VMA_MAP_TYPE(KeyT, ValueT) \
    std::unordered_map< KeyT, ValueT, std::hash<KeyT>, std::equal_to<KeyT>, VmaStlAllocator< std::pair<KeyT, ValueT> > >

#else // #if VMA_USE_STL_UNORDERED_MAP

template<typename T1, typename T2>
struct VmaPair
{
    T1 first;
    T2 second;

    VmaPair() : first(), second() { }
    VmaPair(const T1& firstSrc, const T2& secondSrc) : first(firstSrc), second(secondSrc) { }
};

/* Class compatible with subset of interface of std::unordered_map.
KeyT, ValueT must be POD because they will be stored in VmaVector.
*/
template<typename KeyT, typename ValueT>
class VmaMap
{
public:
    typedef VmaPair<KeyT, ValueT> PairType;
    typedef PairType* iterator;

    VmaMap(const VmaStlAllocator<PairType>& allocator) : m_Vector(allocator) { }

    iterator begin() { return m_Vector.begin(); }
    iterator end() { return m_Vector.end(); }

    void insert(const PairType& pair);
    iterator find(const KeyT& key);
    void erase(iterator it);
    
private:
    VmaVector< PairType, VmaStlAllocator<PairType> > m_Vector;
};

#define VMA_MAP_TYPE(KeyT, ValueT) VmaMap<KeyT, ValueT>

template<typename FirstT, typename SecondT>
struct VmaPairFirstLess
{
    bool operator()(const VmaPair<FirstT, SecondT>& lhs, const VmaPair<FirstT, SecondT>& rhs) const
    {
        return lhs.first < rhs.first;
    }
    bool operator()(const VmaPair<FirstT, SecondT>& lhs, const FirstT& rhsFirst) const
    {
        return lhs.first < rhsFirst;
    }
};

template<typename KeyT, typename ValueT>
void VmaMap<KeyT, ValueT>::insert(const PairType& pair)
{
    const size_t indexToInsert = VmaBinaryFindFirstNotLess(
        m_Vector.data(),
        m_Vector.data() + m_Vector.size(),
        pair,
        VmaPairFirstLess<KeyT, ValueT>()) - m_Vector.data();
    VmaVectorInsert(m_Vector, indexToInsert, pair);
}

template<typename KeyT, typename ValueT>
VmaPair<KeyT, ValueT>* VmaMap<KeyT, ValueT>::find(const KeyT& key)
{
    PairType* it = VmaBinaryFindFirstNotLess(
        m_Vector.data(),
        m_Vector.data() + m_Vector.size(),
        key,
        VmaPairFirstLess<KeyT, ValueT>());
    if((it != m_Vector.end()) && (it->first == key))
    {
        return it;
    }
    else
    {
        return m_Vector.end();
    }
}

template<typename KeyT, typename ValueT>
void VmaMap<KeyT, ValueT>::erase(iterator it)
{
    VmaVectorRemove(m_Vector, it - m_Vector.begin());
}

#endif // #if VMA_USE_STL_UNORDERED_MAP

#endif // #if 0

////////////////////////////////////////////////////////////////////////////////

class VmaDeviceMemoryBlock;

struct VmaAllocation_T
{
private:
    static const uint8_t MAP_COUNT_FLAG_PERSISTENT_MAP = 0x80;

    enum FLAGS
    {
        FLAG_USER_DATA_STRING = 0x01,
    };

public:
    enum ALLOCATION_TYPE
    {
        ALLOCATION_TYPE_NONE,
        ALLOCATION_TYPE_BLOCK,
        ALLOCATION_TYPE_DEDICATED,
    };

    VmaAllocation_T(uint32_t currentFrameIndex, bool userDataString) :
        m_Alignment(1),
        m_Size(0),
        m_pUserData(VMA_NULL),
        m_LastUseFrameIndex(currentFrameIndex),
        m_Type((uint8_t)ALLOCATION_TYPE_NONE),
        m_SuballocationType((uint8_t)VMA_SUBALLOCATION_TYPE_UNKNOWN),
        m_MapCount(0),
        m_Flags(userDataString ? (uint8_t)FLAG_USER_DATA_STRING : 0)
    {
    }

    ~VmaAllocation_T()
    {
        VMA_ASSERT((m_MapCount & ~MAP_COUNT_FLAG_PERSISTENT_MAP) == 0 && "Allocation was not unmapped before destruction.");

        // Check if owned string was freed.
        VMA_ASSERT(m_pUserData == VMA_NULL);
    }

    void InitBlockAllocation(
        VmaPool hPool,
        VmaDeviceMemoryBlock* block,
        VkDeviceSize offset,
        VkDeviceSize alignment,
        VkDeviceSize size,
        VmaSuballocationType suballocationType,
        bool mapped,
        bool canBecomeLost)
    {
        VMA_ASSERT(m_Type == ALLOCATION_TYPE_NONE);
        VMA_ASSERT(block != VMA_NULL);
        m_Type = (uint8_t)ALLOCATION_TYPE_BLOCK;
        m_Alignment = alignment;
        m_Size = size;
        m_MapCount = mapped ? MAP_COUNT_FLAG_PERSISTENT_MAP : 0;
        m_SuballocationType = (uint8_t)suballocationType;
        m_BlockAllocation.m_hPool = hPool;
        m_BlockAllocation.m_Block = block;
        m_BlockAllocation.m_Offset = offset;
        m_BlockAllocation.m_CanBecomeLost = canBecomeLost;
    }

    void InitLost()
    {
        VMA_ASSERT(m_Type == ALLOCATION_TYPE_NONE);
        VMA_ASSERT(m_LastUseFrameIndex.load() == VMA_FRAME_INDEX_LOST);
        m_Type = (uint8_t)ALLOCATION_TYPE_BLOCK;
        m_BlockAllocation.m_hPool = VK_NULL_HANDLE;
        m_BlockAllocation.m_Block = VMA_NULL;
        m_BlockAllocation.m_Offset = 0;
        m_BlockAllocation.m_CanBecomeLost = true;
    }

    void ChangeBlockAllocation(
        VmaAllocator hAllocator,
        VmaDeviceMemoryBlock* block,
        VkDeviceSize offset);

    // pMappedData not null means allocation is created with MAPPED flag.
    void InitDedicatedAllocation(
        uint32_t memoryTypeIndex,
        VkDeviceMemory hMemory,
        VmaSuballocationType suballocationType,
        void* pMappedData,
        VkDeviceSize size)
    {
        VMA_ASSERT(m_Type == ALLOCATION_TYPE_NONE);
        VMA_ASSERT(hMemory != VK_NULL_HANDLE);
        m_Type = (uint8_t)ALLOCATION_TYPE_DEDICATED;
        m_Alignment = 0;
        m_Size = size;
        m_SuballocationType = (uint8_t)suballocationType;
        m_MapCount = (pMappedData != VMA_NULL) ? MAP_COUNT_FLAG_PERSISTENT_MAP : 0;
        m_DedicatedAllocation.m_MemoryTypeIndex = memoryTypeIndex;
        m_DedicatedAllocation.m_hMemory = hMemory;
        m_DedicatedAllocation.m_pMappedData = pMappedData;
    }

    ALLOCATION_TYPE GetType() const { return (ALLOCATION_TYPE)m_Type; }
    VkDeviceSize GetAlignment() const { return m_Alignment; }
    VkDeviceSize GetSize() const { return m_Size; }
    bool IsUserDataString() const { return (m_Flags & FLAG_USER_DATA_STRING) != 0; }
    void* GetUserData() const { return m_pUserData; }
    void SetUserData(VmaAllocator hAllocator, void* pUserData);
    VmaSuballocationType GetSuballocationType() const { return (VmaSuballocationType)m_SuballocationType; }

    VmaDeviceMemoryBlock* GetBlock() const
    {
        VMA_ASSERT(m_Type == ALLOCATION_TYPE_BLOCK);
        return m_BlockAllocation.m_Block;
    }
    VkDeviceSize GetOffset() const;
    VkDeviceMemory GetMemory() const;
    uint32_t GetMemoryTypeIndex() const;
    bool IsPersistentMap() const { return (m_MapCount & MAP_COUNT_FLAG_PERSISTENT_MAP) != 0; }
    void* GetMappedData() const;
    bool CanBecomeLost() const;
    VmaPool GetPool() const;
    
    uint32_t GetLastUseFrameIndex() const
    {
        return m_LastUseFrameIndex.load();
    }
    bool CompareExchangeLastUseFrameIndex(uint32_t& expected, uint32_t desired)
    {
        return m_LastUseFrameIndex.compare_exchange_weak(expected, desired);
    }
    /*
    - If hAllocation.LastUseFrameIndex + frameInUseCount < allocator.CurrentFrameIndex,
      makes it lost by setting LastUseFrameIndex = VMA_FRAME_INDEX_LOST and returns true.
    - Else, returns false.
    
    If hAllocation is already lost, assert - you should not call it then.
    If hAllocation was not created with CAN_BECOME_LOST_BIT, assert.
    */
    bool MakeLost(uint32_t currentFrameIndex, uint32_t frameInUseCount);

    void DedicatedAllocCalcStatsInfo(VmaStatInfo& outInfo)
    {
        VMA_ASSERT(m_Type == ALLOCATION_TYPE_DEDICATED);
        outInfo.blockCount = 1;
        outInfo.allocationCount = 1;
        outInfo.unusedRangeCount = 0;
        outInfo.usedBytes = m_Size;
        outInfo.unusedBytes = 0;
        outInfo.allocationSizeMin = outInfo.allocationSizeMax = m_Size;
        outInfo.unusedRangeSizeMin = UINT64_MAX;
        outInfo.unusedRangeSizeMax = 0;
    }

    void BlockAllocMap();
    void BlockAllocUnmap();
    VkResult DedicatedAllocMap(VmaAllocator hAllocator, void** ppData);
    void DedicatedAllocUnmap(VmaAllocator hAllocator);

private:
    VkDeviceSize m_Alignment;
    VkDeviceSize m_Size;
    void* m_pUserData;
    VMA_ATOMIC_UINT32 m_LastUseFrameIndex;
    uint8_t m_Type; // ALLOCATION_TYPE
    uint8_t m_SuballocationType; // VmaSuballocationType
    // Bit 0x80 is set when allocation was created with VMA_ALLOCATION_CREATE_MAPPED_BIT.
    // Bits with mask 0x7F are reference counter for vmaMapMemory()/vmaUnmapMemory().
    uint8_t m_MapCount;
    uint8_t m_Flags; // enum FLAGS

    // Allocation out of VmaDeviceMemoryBlock.
    struct BlockAllocation
    {
        VmaPool m_hPool; // Null if belongs to general memory.
        VmaDeviceMemoryBlock* m_Block;
        VkDeviceSize m_Offset;
        bool m_CanBecomeLost;
    };

    // Allocation for an object that has its own private VkDeviceMemory.
    struct DedicatedAllocation
    {
        uint32_t m_MemoryTypeIndex;
        VkDeviceMemory m_hMemory;
        void* m_pMappedData; // Not null means memory is mapped.
    };

    union
    {
        // Allocation out of VmaDeviceMemoryBlock.
        BlockAllocation m_BlockAllocation;
        // Allocation for an object that has its own private VkDeviceMemory.
        DedicatedAllocation m_DedicatedAllocation;
    };

    void FreeUserDataString(VmaAllocator hAllocator);
};

/*
Represents a region of VmaDeviceMemoryBlock that is either assigned and returned as
allocated memory block or free.
*/
struct VmaSuballocation
{
    VkDeviceSize offset;
    VkDeviceSize size;
    VmaAllocation hAllocation;
    VmaSuballocationType type;
};

typedef VmaList< VmaSuballocation, VmaStlAllocator<VmaSuballocation> > VmaSuballocationList;

// Cost of one additional allocation lost, as equivalent in bytes.
static const VkDeviceSize VMA_LOST_ALLOCATION_COST = 1048576;

/*
Parameters of planned allocation inside a VmaDeviceMemoryBlock.

If canMakeOtherLost was false:
- item points to a FREE suballocation.
- itemsToMakeLostCount is 0.

If canMakeOtherLost was true:
- item points to first of sequence of suballocations, which are either FREE,
  or point to VmaAllocations that can become lost.
- itemsToMakeLostCount is the number of VmaAllocations that need to be made lost for
  the requested allocation to succeed.
*/
struct VmaAllocationRequest
{
    VkDeviceSize offset;
    VkDeviceSize sumFreeSize; // Sum size of free items that overlap with proposed allocation.
    VkDeviceSize sumItemSize; // Sum size of items to make lost that overlap with proposed allocation.
    VmaSuballocationList::iterator item;
    size_t itemsToMakeLostCount;

    VkDeviceSize CalcCost() const
    {
        return sumItemSize + itemsToMakeLostCount * VMA_LOST_ALLOCATION_COST;
    }
};

/*
Data structure used for bookkeeping of allocations and unused ranges of memory
in a single VkDeviceMemory block.
*/
class VmaBlockMetadata
{
public:
    VmaBlockMetadata(VmaAllocator hAllocator);
    ~VmaBlockMetadata();
    void Init(VkDeviceSize size);

    // Validates all data structures inside this object. If not valid, returns false.
    bool Validate() const;
    VkDeviceSize GetSize() const { return m_Size; }
    size_t GetAllocationCount() const { return m_Suballocations.size() - m_FreeCount; }
    VkDeviceSize GetSumFreeSize() const { return m_SumFreeSize; }
    VkDeviceSize GetUnusedRangeSizeMax() const;
    // Returns true if this block is empty - contains only single free suballocation.
    bool IsEmpty() const;

    void CalcAllocationStatInfo(VmaStatInfo& outInfo) const;
    void AddPoolStats(VmaPoolStats& inoutStats) const;

#if VMA_STATS_STRING_ENABLED
    void PrintDetailedMap(class VmaJsonWriter& json) const;
#endif

    // Creates trivial request for case when block is empty.
    void CreateFirstAllocationRequest(VmaAllocationRequest* pAllocationRequest);

    // Tries to find a place for suballocation with given parameters inside this block.
    // If succeeded, fills pAllocationRequest and returns true.
    // If failed, returns false.
    bool CreateAllocationRequest(
        uint32_t currentFrameIndex,
        uint32_t frameInUseCount,
        VkDeviceSize bufferImageGranularity,
        VkDeviceSize allocSize,
        VkDeviceSize allocAlignment,
        VmaSuballocationType allocType,
        bool canMakeOtherLost,
        VmaAllocationRequest* pAllocationRequest);

    bool MakeRequestedAllocationsLost(
        uint32_t currentFrameIndex,
        uint32_t frameInUseCount,
        VmaAllocationRequest* pAllocationRequest);

    uint32_t MakeAllocationsLost(uint32_t currentFrameIndex, uint32_t frameInUseCount);

    // Makes actual allocation based on request. Request must already be checked and valid.
    void Alloc(
        const VmaAllocationRequest& request,
        VmaSuballocationType type,
        VkDeviceSize allocSize,
        VmaAllocation hAllocation);

    // Frees suballocation assigned to given memory region.
    void Free(const VmaAllocation allocation);
    void FreeAtOffset(VkDeviceSize offset);

private:
    VkDeviceSize m_Size;
    uint32_t m_FreeCount;
    VkDeviceSize m_SumFreeSize;
    VmaSuballocationList m_Suballocations;
    // Suballocations that are free and have size greater than certain threshold.
    // Sorted by size, ascending.
    VmaVector< VmaSuballocationList::iterator, VmaStlAllocator< VmaSuballocationList::iterator > > m_FreeSuballocationsBySize;

    bool ValidateFreeSuballocationList() const;

    // Checks if requested suballocation with given parameters can be placed in given pFreeSuballocItem.
    // If yes, fills pOffset and returns true. If no, returns false.
    bool CheckAllocation(
        uint32_t currentFrameIndex,
        uint32_t frameInUseCount,
        VkDeviceSize bufferImageGranularity,
        VkDeviceSize allocSize,
        VkDeviceSize allocAlignment,
        VmaSuballocationType allocType,
        VmaSuballocationList::const_iterator suballocItem,
        bool canMakeOtherLost,
        VkDeviceSize* pOffset,
        size_t* itemsToMakeLostCount,
        VkDeviceSize* pSumFreeSize,
        VkDeviceSize* pSumItemSize) const;
    // Given free suballocation, it merges it with following one, which must also be free.
    void MergeFreeWithNext(VmaSuballocationList::iterator item);
    // Releases given suballocation, making it free.
    // Merges it with adjacent free suballocations if applicable.
    // Returns iterator to new free suballocation at this place.
    VmaSuballocationList::iterator FreeSuballocation(VmaSuballocationList::iterator suballocItem);
    // Given free suballocation, it inserts it into sorted list of
    // m_FreeSuballocationsBySize if it's suitable.
    void RegisterFreeSuballocation(VmaSuballocationList::iterator item);
    // Given free suballocation, it removes it from sorted list of
    // m_FreeSuballocationsBySize if it's suitable.
    void UnregisterFreeSuballocation(VmaSuballocationList::iterator item);
};

/*
Represents a single block of device memory (`VkDeviceMemory`) with all the
data about its regions (aka suballocations, #VmaAllocation), assigned and free.

Thread-safety: This class must be externally synchronized.
*/
class VmaDeviceMemoryBlock
{
public:
    VmaBlockMetadata m_Metadata;

    VmaDeviceMemoryBlock(VmaAllocator hAllocator);

    ~VmaDeviceMemoryBlock()
    {
        VMA_ASSERT(m_MapCount == 0 && "VkDeviceMemory block is being destroyed while it is still mapped.");
        VMA_ASSERT(m_hMemory == VK_NULL_HANDLE);
    }

    // Always call after construction.
    void Init(
        uint32_t newMemoryTypeIndex,
        VkDeviceMemory newMemory,
        VkDeviceSize newSize);
    // Always call before destruction.
    void Destroy(VmaAllocator allocator);
    
    VkDeviceMemory GetDeviceMemory() const { return m_hMemory; }
    uint32_t GetMemoryTypeIndex() const { return m_MemoryTypeIndex; }
    void* GetMappedData() const { return m_pMappedData; }

    // Validates all data structures inside this object. If not valid, returns false.
    bool Validate() const;

    // ppData can be null.
    VkResult Map(VmaAllocator hAllocator, uint32_t count, void** ppData);
    void Unmap(VmaAllocator hAllocator, uint32_t count);

    VkResult BindBufferMemory(
        const VmaAllocator hAllocator,
        const VmaAllocation hAllocation,
        VkBuffer hBuffer);
    VkResult BindImageMemory(
        const VmaAllocator hAllocator,
        const VmaAllocation hAllocation,
        VkImage hImage);

private:
    uint32_t m_MemoryTypeIndex;
    VkDeviceMemory m_hMemory;

    // Protects access to m_hMemory so it's not used by multiple threads simultaneously, e.g. vkMapMemory, vkBindBufferMemory.
    // Also protects m_MapCount, m_pMappedData.
    VMA_MUTEX m_Mutex;
    uint32_t m_MapCount;
    void* m_pMappedData;
};

struct VmaPointerLess
{
    bool operator()(const void* lhs, const void* rhs) const
    {
        return lhs < rhs;
    }
};

class VmaDefragmentator;

/*
Sequence of VmaDeviceMemoryBlock. Represents memory blocks allocated for a specific
Vulkan memory type.

Synchronized internally with a mutex.
*/
struct VmaBlockVector
{
    VmaBlockVector(
        VmaAllocator hAllocator,
        uint32_t memoryTypeIndex,
        VkDeviceSize preferredBlockSize,
        size_t minBlockCount,
        size_t maxBlockCount,
        VkDeviceSize bufferImageGranularity,
        uint32_t frameInUseCount,
        bool isCustomPool);
    ~VmaBlockVector();

    VkResult CreateMinBlocks();

    uint32_t GetMemoryTypeIndex() const { return m_MemoryTypeIndex; }
    VkDeviceSize GetPreferredBlockSize() const { return m_PreferredBlockSize; }
    VkDeviceSize GetBufferImageGranularity() const { return m_BufferImageGranularity; }
    uint32_t GetFrameInUseCount() const { return m_FrameInUseCount; }

    void GetPoolStats(VmaPoolStats* pStats);

    bool IsEmpty() const { return m_Blocks.empty(); }

    VkResult Allocate(
        VmaPool hCurrentPool,
        uint32_t currentFrameIndex,
        const VkMemoryRequirements& vkMemReq,
        const VmaAllocationCreateInfo& createInfo,
        VmaSuballocationType suballocType,
        VmaAllocation* pAllocation);

    void Free(
        VmaAllocation hAllocation);

    // Adds statistics of this BlockVector to pStats.
    void AddStats(VmaStats* pStats);

#if VMA_STATS_STRING_ENABLED
    void PrintDetailedMap(class VmaJsonWriter& json);
#endif

    void MakePoolAllocationsLost(
        uint32_t currentFrameIndex,
        size_t* pLostAllocationCount);

    VmaDefragmentator* EnsureDefragmentator(
        VmaAllocator hAllocator,
        uint32_t currentFrameIndex);

    VkResult Defragment(
        VmaDefragmentationStats* pDefragmentationStats,
        VkDeviceSize& maxBytesToMove,
        uint32_t& maxAllocationsToMove);

    void DestroyDefragmentator();

private:
    friend class VmaDefragmentator;

    const VmaAllocator m_hAllocator;
    const uint32_t m_MemoryTypeIndex;
    const VkDeviceSize m_PreferredBlockSize;
    const size_t m_MinBlockCount;
    const size_t m_MaxBlockCount;
    const VkDeviceSize m_BufferImageGranularity;
    const uint32_t m_FrameInUseCount;
    const bool m_IsCustomPool;
    VMA_MUTEX m_Mutex;
    // Incrementally sorted by sumFreeSize, ascending.
    VmaVector< VmaDeviceMemoryBlock*, VmaStlAllocator<VmaDeviceMemoryBlock*> > m_Blocks;
    /* There can be at most one allocation that is completely empty - a
    hysteresis to avoid pessimistic case of alternating creation and destruction
    of a VkDeviceMemory. */
    bool m_HasEmptyBlock;
    VmaDefragmentator* m_pDefragmentator;

    size_t CalcMaxBlockSize() const;

    // Finds and removes given block from vector.
    void Remove(VmaDeviceMemoryBlock* pBlock);

    // Performs single step in sorting m_Blocks. They may not be fully sorted
    // after this call.
    void IncrementallySortBlocks();

    VkResult CreateBlock(VkDeviceSize blockSize, size_t* pNewBlockIndex);
};

struct VmaPool_T
{
public:
    VmaBlockVector m_BlockVector;

    // Takes ownership.
    VmaPool_T(
        VmaAllocator hAllocator,
        const VmaPoolCreateInfo& createInfo);
    ~VmaPool_T();

    VmaBlockVector& GetBlockVector() { return m_BlockVector; }

#if VMA_STATS_STRING_ENABLED
    //void PrintDetailedMap(class VmaStringBuilder& sb);
#endif
};

class VmaDefragmentator
{
    const VmaAllocator m_hAllocator;
    VmaBlockVector* const m_pBlockVector;
    uint32_t m_CurrentFrameIndex;
    VkDeviceSize m_BytesMoved;
    uint32_t m_AllocationsMoved;

    struct AllocationInfo
    {
        VmaAllocation m_hAllocation;
        VkBool32* m_pChanged;

        AllocationInfo() :
            m_hAllocation(VK_NULL_HANDLE),
            m_pChanged(VMA_NULL)
        {
        }
    };

    struct AllocationInfoSizeGreater
    {
        bool operator()(const AllocationInfo& lhs, const AllocationInfo& rhs) const
        {
            return lhs.m_hAllocation->GetSize() > rhs.m_hAllocation->GetSize();
        }
    };

    // Used between AddAllocation and Defragment.
    VmaVector< AllocationInfo, VmaStlAllocator<AllocationInfo> > m_Allocations;

    struct BlockInfo
    {
        VmaDeviceMemoryBlock* m_pBlock;
        bool m_HasNonMovableAllocations;
        VmaVector< AllocationInfo, VmaStlAllocator<AllocationInfo> > m_Allocations;

        BlockInfo(const VkAllocationCallbacks* pAllocationCallbacks) :
            m_pBlock(VMA_NULL),
            m_HasNonMovableAllocations(true),
            m_Allocations(pAllocationCallbacks),
            m_pMappedDataForDefragmentation(VMA_NULL)
        {
        }

        void CalcHasNonMovableAllocations()
        {
            const size_t blockAllocCount = m_pBlock->m_Metadata.GetAllocationCount();
            const size_t defragmentAllocCount = m_Allocations.size();
            m_HasNonMovableAllocations = blockAllocCount != defragmentAllocCount;
        }

        void SortAllocationsBySizeDescecnding()
        {
            VMA_SORT(m_Allocations.begin(), m_Allocations.end(), AllocationInfoSizeGreater());
        }

        VkResult EnsureMapping(VmaAllocator hAllocator, void** ppMappedData);
        void Unmap(VmaAllocator hAllocator);

    private:
        // Not null if mapped for defragmentation only, not originally mapped.
        void* m_pMappedDataForDefragmentation;
    };

    struct BlockPointerLess
    {
        bool operator()(const BlockInfo* pLhsBlockInfo, const VmaDeviceMemoryBlock* pRhsBlock) const
        {
            return pLhsBlockInfo->m_pBlock < pRhsBlock;
        }
        bool operator()(const BlockInfo* pLhsBlockInfo, const BlockInfo* pRhsBlockInfo) const
        {
            return pLhsBlockInfo->m_pBlock < pRhsBlockInfo->m_pBlock;
        }
    };

    // 1. Blocks with some non-movable allocations go first.
    // 2. Blocks with smaller sumFreeSize go first.
    struct BlockInfoCompareMoveDestination
    {
        bool operator()(const BlockInfo* pLhsBlockInfo, const BlockInfo* pRhsBlockInfo) const
        {
            if(pLhsBlockInfo->m_HasNonMovableAllocations && !pRhsBlockInfo->m_HasNonMovableAllocations)
            {
                return true;
            }
            if(!pLhsBlockInfo->m_HasNonMovableAllocations && pRhsBlockInfo->m_HasNonMovableAllocations)
            {
                return false;
            }
            if(pLhsBlockInfo->m_pBlock->m_Metadata.GetSumFreeSize() < pRhsBlockInfo->m_pBlock->m_Metadata.GetSumFreeSize())
            {
                return true;
            }
            return false;
        }
    };

    typedef VmaVector< BlockInfo*, VmaStlAllocator<BlockInfo*> > BlockInfoVector;
    BlockInfoVector m_Blocks;

    VkResult DefragmentRound(
        VkDeviceSize maxBytesToMove,
        uint32_t maxAllocationsToMove);

    static bool MoveMakesSense(
        size_t dstBlockIndex, VkDeviceSize dstOffset,
        size_t srcBlockIndex, VkDeviceSize srcOffset);

public:
    VmaDefragmentator(
        VmaAllocator hAllocator,
        VmaBlockVector* pBlockVector,
        uint32_t currentFrameIndex);

    ~VmaDefragmentator();

    VkDeviceSize GetBytesMoved() const { return m_BytesMoved; }
    uint32_t GetAllocationsMoved() const { return m_AllocationsMoved; }

    void AddAllocation(VmaAllocation hAlloc, VkBool32* pChanged);

    VkResult Defragment(
        VkDeviceSize maxBytesToMove,
        uint32_t maxAllocationsToMove);
};

// Main allocator object.
struct VmaAllocator_T
{
    bool m_UseMutex;
    bool m_UseKhrDedicatedAllocation;
    VkDevice m_hDevice;
    bool m_AllocationCallbacksSpecified;
    VkAllocationCallbacks m_AllocationCallbacks;
    VmaDeviceMemoryCallbacks m_DeviceMemoryCallbacks;
    
    // Number of bytes free out of limit, or VK_WHOLE_SIZE if not limit for that heap.
    VkDeviceSize m_HeapSizeLimit[VK_MAX_MEMORY_HEAPS];
    VMA_MUTEX m_HeapSizeLimitMutex;

    VkPhysicalDeviceProperties m_PhysicalDeviceProperties;
    VkPhysicalDeviceMemoryProperties m_MemProps;

    // Default pools.
    VmaBlockVector* m_pBlockVectors[VK_MAX_MEMORY_TYPES];

    // Each vector is sorted by memory (handle value).
    typedef VmaVector< VmaAllocation, VmaStlAllocator<VmaAllocation> > AllocationVectorType;
    AllocationVectorType* m_pDedicatedAllocations[VK_MAX_MEMORY_TYPES];
    VMA_MUTEX m_DedicatedAllocationsMutex[VK_MAX_MEMORY_TYPES];

    VmaAllocator_T(const VmaAllocatorCreateInfo* pCreateInfo);
    ~VmaAllocator_T();

    const VkAllocationCallbacks* GetAllocationCallbacks() const
    {
        return m_AllocationCallbacksSpecified ? &m_AllocationCallbacks : 0;
    }
    const VmaVulkanFunctions& GetVulkanFunctions() const
    {
        return m_VulkanFunctions;
    }

    VkDeviceSize GetBufferImageGranularity() const
    {
        return VMA_MAX(
            static_cast<VkDeviceSize>(VMA_DEBUG_MIN_BUFFER_IMAGE_GRANULARITY),
            m_PhysicalDeviceProperties.limits.bufferImageGranularity);
    }

    uint32_t GetMemoryHeapCount() const { return m_MemProps.memoryHeapCount; }
    uint32_t GetMemoryTypeCount() const { return m_MemProps.memoryTypeCount; }

    uint32_t MemoryTypeIndexToHeapIndex(uint32_t memTypeIndex) const
    {
        VMA_ASSERT(memTypeIndex < m_MemProps.memoryTypeCount);
        return m_MemProps.memoryTypes[memTypeIndex].heapIndex;
    }

    void GetBufferMemoryRequirements(
        VkBuffer hBuffer,
        VkMemoryRequirements& memReq,
        bool& requiresDedicatedAllocation,
        bool& prefersDedicatedAllocation) const;
    void GetImageMemoryRequirements(
        VkImage hImage,
        VkMemoryRequirements& memReq,
        bool& requiresDedicatedAllocation,
        bool& prefersDedicatedAllocation) const;

    // Main allocation function.
    VkResult AllocateMemory(
        const VkMemoryRequirements& vkMemReq,
        bool requiresDedicatedAllocation,
        bool prefersDedicatedAllocation,
        VkBuffer dedicatedBuffer,
        VkImage dedicatedImage,
        const VmaAllocationCreateInfo& createInfo,
        VmaSuballocationType suballocType,
        VmaAllocation* pAllocation);

    // Main deallocation function.
    void FreeMemory(const VmaAllocation allocation);

    void CalculateStats(VmaStats* pStats);

#if VMA_STATS_STRING_ENABLED
    void PrintDetailedMap(class VmaJsonWriter& json);
#endif

    VkResult Defragment(
        VmaAllocation* pAllocations,
        size_t allocationCount,
        VkBool32* pAllocationsChanged,
        const VmaDefragmentationInfo* pDefragmentationInfo,
        VmaDefragmentationStats* pDefragmentationStats);

    void GetAllocationInfo(VmaAllocation hAllocation, VmaAllocationInfo* pAllocationInfo);
    bool TouchAllocation(VmaAllocation hAllocation);

    VkResult CreatePool(const VmaPoolCreateInfo* pCreateInfo, VmaPool* pPool);
    void DestroyPool(VmaPool pool);
    void GetPoolStats(VmaPool pool, VmaPoolStats* pPoolStats);

    void SetCurrentFrameIndex(uint32_t frameIndex);

    void MakePoolAllocationsLost(
        VmaPool hPool,
        size_t* pLostAllocationCount);

    void CreateLostAllocation(VmaAllocation* pAllocation);

    VkResult AllocateVulkanMemory(const VkMemoryAllocateInfo* pAllocateInfo, VkDeviceMemory* pMemory);
    void FreeVulkanMemory(uint32_t memoryType, VkDeviceSize size, VkDeviceMemory hMemory);

    VkResult Map(VmaAllocation hAllocation, void** ppData);
    void Unmap(VmaAllocation hAllocation);

    VkResult BindBufferMemory(VmaAllocation hAllocation, VkBuffer hBuffer);
    VkResult BindImageMemory(VmaAllocation hAllocation, VkImage hImage);

private:
    VkDeviceSize m_PreferredLargeHeapBlockSize;

    VkPhysicalDevice m_PhysicalDevice;
    VMA_ATOMIC_UINT32 m_CurrentFrameIndex;
    
    VMA_MUTEX m_PoolsMutex;
    // Protected by m_PoolsMutex. Sorted by pointer value.
    VmaVector<VmaPool, VmaStlAllocator<VmaPool> > m_Pools;

    VmaVulkanFunctions m_VulkanFunctions;

    void ImportVulkanFunctions(const VmaVulkanFunctions* pVulkanFunctions);

    VkDeviceSize CalcPreferredBlockSize(uint32_t memTypeIndex);

    VkResult AllocateMemoryOfType(
        const VkMemoryRequirements& vkMemReq,
        bool dedicatedAllocation,
        VkBuffer dedicatedBuffer,
        VkImage dedicatedImage,
        const VmaAllocationCreateInfo& createInfo,
        uint32_t memTypeIndex,
        VmaSuballocationType suballocType,
        VmaAllocation* pAllocation);

    // Allocates and registers new VkDeviceMemory specifically for single allocation.
    VkResult AllocateDedicatedMemory(
        VkDeviceSize size,
        VmaSuballocationType suballocType,
        uint32_t memTypeIndex,
        bool map,
        bool isUserDataString,
        void* pUserData,
        VkBuffer dedicatedBuffer,
        VkImage dedicatedImage,
        VmaAllocation* pAllocation);

    // Tries to free pMemory as Dedicated Memory. Returns true if found and freed.
    void FreeDedicatedMemory(VmaAllocation allocation);
};

////////////////////////////////////////////////////////////////////////////////
// Memory allocation #2 after VmaAllocator_T definition

static void* VmaMalloc(VmaAllocator hAllocator, size_t size, size_t alignment)
{
    return VmaMalloc(&hAllocator->m_AllocationCallbacks, size, alignment);
}

static void VmaFree(VmaAllocator hAllocator, void* ptr)
{
    VmaFree(&hAllocator->m_AllocationCallbacks, ptr);
}

template<typename T>
static T* VmaAllocate(VmaAllocator hAllocator)
{
    return (T*)VmaMalloc(hAllocator, sizeof(T), VMA_ALIGN_OF(T));
}

template<typename T>
static T* VmaAllocateArray(VmaAllocator hAllocator, size_t count)
{
    return (T*)VmaMalloc(hAllocator, sizeof(T) * count, VMA_ALIGN_OF(T));
}

template<typename T>
static void vma_delete(VmaAllocator hAllocator, T* ptr)
{
    if(ptr != VMA_NULL)
    {
        ptr->~T();
        VmaFree(hAllocator, ptr);
    }
}

template<typename T>
static void vma_delete_array(VmaAllocator hAllocator, T* ptr, size_t count)
{
    if(ptr != VMA_NULL)
    {
        for(size_t i = count; i--; )
            ptr[i].~T();
        VmaFree(hAllocator, ptr);
    }
}

////////////////////////////////////////////////////////////////////////////////
// VmaStringBuilder

#if VMA_STATS_STRING_ENABLED

class VmaStringBuilder
{
public:
    VmaStringBuilder(VmaAllocator alloc) : m_Data(VmaStlAllocator<char>(alloc->GetAllocationCallbacks())) { }
    size_t GetLength() const { return m_Data.size(); }
    const char* GetData() const { return m_Data.data(); }

    void Add(char ch) { m_Data.push_back(ch); }
    void Add(const char* pStr);
    void AddNewLine() { Add('\n'); }
    void AddNumber(uint32_t num);
    void AddNumber(uint64_t num);
    void AddPointer(const void* ptr);

private:
    VmaVector< char, VmaStlAllocator<char> > m_Data;
};

void VmaStringBuilder::Add(const char* pStr)
{
    const size_t strLen = strlen(pStr);
    if(strLen > 0)
    {
        const size_t oldCount = m_Data.size();
        m_Data.resize(oldCount + strLen);
        memcpy(m_Data.data() + oldCount, pStr, strLen);
    }
}

void VmaStringBuilder::AddNumber(uint32_t num)
{
    char buf[11];
    VmaUint32ToStr(buf, sizeof(buf), num);
    Add(buf);
}

void VmaStringBuilder::AddNumber(uint64_t num)
{
    char buf[21];
    VmaUint64ToStr(buf, sizeof(buf), num);
    Add(buf);
}

void VmaStringBuilder::AddPointer(const void* ptr)
{
    char buf[21];
    VmaPtrToStr(buf, sizeof(buf), ptr);
    Add(buf);
}

#endif // #if VMA_STATS_STRING_ENABLED

////////////////////////////////////////////////////////////////////////////////
// VmaJsonWriter

#if VMA_STATS_STRING_ENABLED

class VmaJsonWriter
{
public:
    VmaJsonWriter(const VkAllocationCallbacks* pAllocationCallbacks, VmaStringBuilder& sb);
    ~VmaJsonWriter();

    void BeginObject(bool singleLine = false);
    void EndObject();
    
    void BeginArray(bool singleLine = false);
    void EndArray();
    
    void WriteString(const char* pStr);
    void BeginString(const char* pStr = VMA_NULL);
    void ContinueString(const char* pStr);
    void ContinueString(uint32_t n);
    void ContinueString(uint64_t n);
    void ContinueString_Pointer(const void* ptr);
    void EndString(const char* pStr = VMA_NULL);
    
    void WriteNumber(uint32_t n);
    void WriteNumber(uint64_t n);
    void WriteBool(bool b);
    void WriteNull();

private:
    static const char* const INDENT;

    enum COLLECTION_TYPE
    {
        COLLECTION_TYPE_OBJECT,
        COLLECTION_TYPE_ARRAY,
    };
    struct StackItem
    {
        COLLECTION_TYPE type;
        uint32_t valueCount;
        bool singleLineMode;
    };

    VmaStringBuilder& m_SB;
    VmaVector< StackItem, VmaStlAllocator<StackItem> > m_Stack;
    bool m_InsideString;

    void BeginValue(bool isString);
    void WriteIndent(bool oneLess = false);
};

const char* const VmaJsonWriter::INDENT = "  ";

VmaJsonWriter::VmaJsonWriter(const VkAllocationCallbacks* pAllocationCallbacks, VmaStringBuilder& sb) :
    m_SB(sb),
    m_Stack(VmaStlAllocator<StackItem>(pAllocationCallbacks)),
    m_InsideString(false)
{
}

VmaJsonWriter::~VmaJsonWriter()
{
    VMA_ASSERT(!m_InsideString);
    VMA_ASSERT(m_Stack.empty());
}

void VmaJsonWriter::BeginObject(bool singleLine)
{
    VMA_ASSERT(!m_InsideString);

    BeginValue(false);
    m_SB.Add('{');

    StackItem item;
    item.type = COLLECTION_TYPE_OBJECT;
    item.valueCount = 0;
    item.singleLineMode = singleLine;
    m_Stack.push_back(item);
}

void VmaJsonWriter::EndObject()
{
    VMA_ASSERT(!m_InsideString);

    WriteIndent(true);
    m_SB.Add('}');

    VMA_ASSERT(!m_Stack.empty() && m_Stack.back().type == COLLECTION_TYPE_OBJECT);
    m_Stack.pop_back();
}

void VmaJsonWriter::BeginArray(bool singleLine)
{
    VMA_ASSERT(!m_InsideString);

    BeginValue(false);
    m_SB.Add('[');

    StackItem item;
    item.type = COLLECTION_TYPE_ARRAY;
    item.valueCount = 0;
    item.singleLineMode = singleLine;
    m_Stack.push_back(item);
}

void VmaJsonWriter::EndArray()
{
    VMA_ASSERT(!m_InsideString);

    WriteIndent(true);
    m_SB.Add(']');

    VMA_ASSERT(!m_Stack.empty() && m_Stack.back().type == COLLECTION_TYPE_ARRAY);
    m_Stack.pop_back();
}

void VmaJsonWriter::WriteString(const char* pStr)
{
    BeginString(pStr);
    EndString();
}

void VmaJsonWriter::BeginString(const char* pStr)
{
    VMA_ASSERT(!m_InsideString);

    BeginValue(true);
    m_SB.Add('"');
    m_InsideString = true;
    if(pStr != VMA_NULL && pStr[0] != '\0')
    {
        ContinueString(pStr);
    }
}

void VmaJsonWriter::ContinueString(const char* pStr)
{
    VMA_ASSERT(m_InsideString);

    const size_t strLen = strlen(pStr);
    for(size_t i = 0; i < strLen; ++i)
    {
        char ch = pStr[i];
        if(ch == '\'')
        {
            m_SB.Add("\\\\");
        }
        else if(ch == '"')
        {
            m_SB.Add("\\\"");
        }
        else if(ch >= 32)
        {
            m_SB.Add(ch);
        }
        else switch(ch)
        {
        case '\b':
            m_SB.Add("\\b");
            break;
        case '\f':
            m_SB.Add("\\f");
            break;
        case '\n':
            m_SB.Add("\\n");
            break;
        case '\r':
            m_SB.Add("\\r");
            break;
        case '\t':
            m_SB.Add("\\t");
            break;
        default:
            VMA_ASSERT(0 && "Character not currently supported.");
            break;
        }
    }
}

void VmaJsonWriter::ContinueString(uint32_t n)
{
    VMA_ASSERT(m_InsideString);
    m_SB.AddNumber(n);
}

void VmaJsonWriter::ContinueString(uint64_t n)
{
    VMA_ASSERT(m_InsideString);
    m_SB.AddNumber(n);
}

void VmaJsonWriter::ContinueString_Pointer(const void* ptr)
{
    VMA_ASSERT(m_InsideString);
    m_SB.AddPointer(ptr);
}

void VmaJsonWriter::EndString(const char* pStr)
{
    VMA_ASSERT(m_InsideString);
    if(pStr != VMA_NULL && pStr[0] != '\0')
    {
        ContinueString(pStr);
    }
    m_SB.Add('"');
    m_InsideString = false;
}

void VmaJsonWriter::WriteNumber(uint32_t n)
{
    VMA_ASSERT(!m_InsideString);
    BeginValue(false);
    m_SB.AddNumber(n);
}

void VmaJsonWriter::WriteNumber(uint64_t n)
{
    VMA_ASSERT(!m_InsideString);
    BeginValue(false);
    m_SB.AddNumber(n);
}

void VmaJsonWriter::WriteBool(bool b)
{
    VMA_ASSERT(!m_InsideString);
    BeginValue(false);
    m_SB.Add(b ? "true" : "false");
}

void VmaJsonWriter::WriteNull()
{
    VMA_ASSERT(!m_InsideString);
    BeginValue(false);
    m_SB.Add("null");
}

void VmaJsonWriter::BeginValue(bool isString)
{
    if(!m_Stack.empty())
    {
        StackItem& currItem = m_Stack.back();
        if(currItem.type == COLLECTION_TYPE_OBJECT &&
            currItem.valueCount % 2 == 0)
        {
            VMA_ASSERT(isString);
        }

        if(currItem.type == COLLECTION_TYPE_OBJECT &&
            currItem.valueCount % 2 != 0)
        {
            m_SB.Add(": ");
        }
        else if(currItem.valueCount > 0)
        {
            m_SB.Add(", ");
            WriteIndent();
        }
        else
        {
            WriteIndent();
        }
        ++currItem.valueCount;
    }
}

void VmaJsonWriter::WriteIndent(bool oneLess)
{
    if(!m_Stack.empty() && !m_Stack.back().singleLineMode)
    {
        m_SB.AddNewLine();
        
        size_t count = m_Stack.size();
        if(count > 0 && oneLess)
        {
            --count;
        }
        for(size_t i = 0; i < count; ++i)
        {
            m_SB.Add(INDENT);
        }
    }
}

#endif // #if VMA_STATS_STRING_ENABLED

////////////////////////////////////////////////////////////////////////////////

void VmaAllocation_T::SetUserData(VmaAllocator hAllocator, void* pUserData)
{
    if(IsUserDataString())
    {
        VMA_ASSERT(pUserData == VMA_NULL || pUserData != m_pUserData);

        FreeUserDataString(hAllocator);

        if(pUserData != VMA_NULL)
        {
            const char* const newStrSrc = (char*)pUserData;
            const size_t newStrLen = strlen(newStrSrc);
            char* const newStrDst = vma_new_array(hAllocator, char, newStrLen + 1);
            memcpy(newStrDst, newStrSrc, newStrLen + 1);
            m_pUserData = newStrDst;
        }
    }
    else
    {
        m_pUserData = pUserData;
    }
}

void VmaAllocation_T::ChangeBlockAllocation(
    VmaAllocator hAllocator,
    VmaDeviceMemoryBlock* block,
    VkDeviceSize offset)
{
    VMA_ASSERT(block != VMA_NULL);
    VMA_ASSERT(m_Type == ALLOCATION_TYPE_BLOCK);

    // Move mapping reference counter from old block to new block.
    if(block != m_BlockAllocation.m_Block)
    {
        uint32_t mapRefCount = m_MapCount & ~MAP_COUNT_FLAG_PERSISTENT_MAP;
        if(IsPersistentMap())
            ++mapRefCount;
        m_BlockAllocation.m_Block->Unmap(hAllocator, mapRefCount);
        block->Map(hAllocator, mapRefCount, VMA_NULL);
    }

    m_BlockAllocation.m_Block = block;
    m_BlockAllocation.m_Offset = offset;
}

VkDeviceSize VmaAllocation_T::GetOffset() const
{
    switch(m_Type)
    {
    case ALLOCATION_TYPE_BLOCK:
        return m_BlockAllocation.m_Offset;
    case ALLOCATION_TYPE_DEDICATED:
        return 0;
    default:
        VMA_ASSERT(0);
        return 0;
    }
}

VkDeviceMemory VmaAllocation_T::GetMemory() const
{
    switch(m_Type)
    {
    case ALLOCATION_TYPE_BLOCK:
        return m_BlockAllocation.m_Block->GetDeviceMemory();
    case ALLOCATION_TYPE_DEDICATED:
        return m_DedicatedAllocation.m_hMemory;
    default:
        VMA_ASSERT(0);
        return VK_NULL_HANDLE;
    }
}

uint32_t VmaAllocation_T::GetMemoryTypeIndex() const
{
    switch(m_Type)
    {
    case ALLOCATION_TYPE_BLOCK:
        return m_BlockAllocation.m_Block->GetMemoryTypeIndex();
    case ALLOCATION_TYPE_DEDICATED:
        return m_DedicatedAllocation.m_MemoryTypeIndex;
    default:
        VMA_ASSERT(0);
        return UINT32_MAX;
    }
}

void* VmaAllocation_T::GetMappedData() const
{
    switch(m_Type)
    {
    case ALLOCATION_TYPE_BLOCK:
        if(m_MapCount != 0)
        {
            void* pBlockData = m_BlockAllocation.m_Block->GetMappedData();
            VMA_ASSERT(pBlockData != VMA_NULL);
            return (char*)pBlockData + m_BlockAllocation.m_Offset;
        }
        else
        {
            return VMA_NULL;
        }
        break;
    case ALLOCATION_TYPE_DEDICATED:
        VMA_ASSERT((m_DedicatedAllocation.m_pMappedData != VMA_NULL) == (m_MapCount != 0));
        return m_DedicatedAllocation.m_pMappedData;
    default:
        VMA_ASSERT(0);
        return VMA_NULL;
    }
}

bool VmaAllocation_T::CanBecomeLost() const
{
    switch(m_Type)
    {
    case ALLOCATION_TYPE_BLOCK:
        return m_BlockAllocation.m_CanBecomeLost;
    case ALLOCATION_TYPE_DEDICATED:
        return false;
    default:
        VMA_ASSERT(0);
        return false;
    }
}

VmaPool VmaAllocation_T::GetPool() const
{
    VMA_ASSERT(m_Type == ALLOCATION_TYPE_BLOCK);
    return m_BlockAllocation.m_hPool;
}

bool VmaAllocation_T::MakeLost(uint32_t currentFrameIndex, uint32_t frameInUseCount)
{
    VMA_ASSERT(CanBecomeLost());

    /*
    Warning: This is a carefully designed algorithm.
    Do not modify unless you really know what you're doing :)
    */
    uint32_t localLastUseFrameIndex = GetLastUseFrameIndex();
    for(;;)
    {
        if(localLastUseFrameIndex == VMA_FRAME_INDEX_LOST)
        {
            VMA_ASSERT(0);
            return false;
        }
        else if(localLastUseFrameIndex + frameInUseCount >= currentFrameIndex)
        {
            return false;
        }
        else // Last use time earlier than current time.
        {
            if(CompareExchangeLastUseFrameIndex(localLastUseFrameIndex, VMA_FRAME_INDEX_LOST))
            {
                // Setting hAllocation.LastUseFrameIndex atomic to VMA_FRAME_INDEX_LOST is enough to mark it as LOST.
                // Calling code just needs to unregister this allocation in owning VmaDeviceMemoryBlock.
                return true;
            }
        }
    }
}

void VmaAllocation_T::FreeUserDataString(VmaAllocator hAllocator)
{
    VMA_ASSERT(IsUserDataString());
    if(m_pUserData != VMA_NULL)
    {
        char* const oldStr = (char*)m_pUserData;
        const size_t oldStrLen = strlen(oldStr);
        vma_delete_array(hAllocator, oldStr, oldStrLen + 1);
        m_pUserData = VMA_NULL;
    }
}

void VmaAllocation_T::BlockAllocMap()
{
    VMA_ASSERT(GetType() == ALLOCATION_TYPE_BLOCK);

    if((m_MapCount & ~MAP_COUNT_FLAG_PERSISTENT_MAP) < 0x7F)
    {
        ++m_MapCount;
    }
    else
    {
        VMA_ASSERT(0 && "Allocation mapped too many times simultaneously.");
    }
}

void VmaAllocation_T::BlockAllocUnmap()
{
    VMA_ASSERT(GetType() == ALLOCATION_TYPE_BLOCK);

    if((m_MapCount & ~MAP_COUNT_FLAG_PERSISTENT_MAP) != 0)
    {
        --m_MapCount;
    }
    else
    {
        VMA_ASSERT(0 && "Unmapping allocation not previously mapped.");
    }
}

VkResult VmaAllocation_T::DedicatedAllocMap(VmaAllocator hAllocator, void** ppData)
{
    VMA_ASSERT(GetType() == ALLOCATION_TYPE_DEDICATED);

    if(m_MapCount != 0)
    {
        if((m_MapCount & ~MAP_COUNT_FLAG_PERSISTENT_MAP) < 0x7F)
        {
            VMA_ASSERT(m_DedicatedAllocation.m_pMappedData != VMA_NULL);
            *ppData = m_DedicatedAllocation.m_pMappedData;
            ++m_MapCount;
            return VK_SUCCESS;
        }
        else
        {
            VMA_ASSERT(0 && "Dedicated allocation mapped too many times simultaneously.");
            return VK_ERROR_MEMORY_MAP_FAILED;
        }
    }
    else
    {
        VkResult result = (*hAllocator->GetVulkanFunctions().vkMapMemory)(
            hAllocator->m_hDevice,
            m_DedicatedAllocation.m_hMemory,
            0, // offset
            VK_WHOLE_SIZE,
            0, // flags
            ppData);
        if(result == VK_SUCCESS)
        {
            m_DedicatedAllocation.m_pMappedData = *ppData;
            m_MapCount = 1;
        }
        return result;
    }
}

void VmaAllocation_T::DedicatedAllocUnmap(VmaAllocator hAllocator)
{
    VMA_ASSERT(GetType() == ALLOCATION_TYPE_DEDICATED);

    if((m_MapCount & ~MAP_COUNT_FLAG_PERSISTENT_MAP) != 0)
    {
        --m_MapCount;
        if(m_MapCount == 0)
        {
            m_DedicatedAllocation.m_pMappedData = VMA_NULL;
            (*hAllocator->GetVulkanFunctions().vkUnmapMemory)(
                hAllocator->m_hDevice,
                m_DedicatedAllocation.m_hMemory);
        }
    }
    else
    {
        VMA_ASSERT(0 && "Unmapping dedicated allocation not previously mapped.");
    }
}

#if VMA_STATS_STRING_ENABLED

// Correspond to values of enum VmaSuballocationType.
static const char* VMA_SUBALLOCATION_TYPE_NAMES[] = {
    "FREE",
    "UNKNOWN",
    "BUFFER",
    "IMAGE_UNKNOWN",
    "IMAGE_LINEAR",
    "IMAGE_OPTIMAL",
};

static void VmaPrintStatInfo(VmaJsonWriter& json, const VmaStatInfo& stat)
{
    json.BeginObject();

    json.WriteString("Blocks");
    json.WriteNumber(stat.blockCount);

    json.WriteString("Allocations");
    json.WriteNumber(stat.allocationCount);

    json.WriteString("UnusedRanges");
    json.WriteNumber(stat.unusedRangeCount);

    json.WriteString("UsedBytes");
    json.WriteNumber(stat.usedBytes);

    json.WriteString("UnusedBytes");
    json.WriteNumber(stat.unusedBytes);

    if(stat.allocationCount > 1)
    {
        json.WriteString("AllocationSize");
        json.BeginObject(true);
        json.WriteString("Min");
        json.WriteNumber(stat.allocationSizeMin);
        json.WriteString("Avg");
        json.WriteNumber(stat.allocationSizeAvg);
        json.WriteString("Max");
        json.WriteNumber(stat.allocationSizeMax);
        json.EndObject();
    }

    if(stat.unusedRangeCount > 1)
    {
        json.WriteString("UnusedRangeSize");
        json.BeginObject(true);
        json.WriteString("Min");
        json.WriteNumber(stat.unusedRangeSizeMin);
        json.WriteString("Avg");
        json.WriteNumber(stat.unusedRangeSizeAvg);
        json.WriteString("Max");
        json.WriteNumber(stat.unusedRangeSizeMax);
        json.EndObject();
    }

    json.EndObject();
}

#endif // #if VMA_STATS_STRING_ENABLED

struct VmaSuballocationItemSizeLess
{
    bool operator()(
        const VmaSuballocationList::iterator lhs,
        const VmaSuballocationList::iterator rhs) const
    {
        return lhs->size < rhs->size;
    }
    bool operator()(
        const VmaSuballocationList::iterator lhs,
        VkDeviceSize rhsSize) const
    {
        return lhs->size < rhsSize;
    }
};

////////////////////////////////////////////////////////////////////////////////
// class VmaBlockMetadata

VmaBlockMetadata::VmaBlockMetadata(VmaAllocator hAllocator) :
    m_Size(0),
    m_FreeCount(0),
    m_SumFreeSize(0),
    m_Suballocations(VmaStlAllocator<VmaSuballocation>(hAllocator->GetAllocationCallbacks())),
    m_FreeSuballocationsBySize(VmaStlAllocator<VmaSuballocationList::iterator>(hAllocator->GetAllocationCallbacks()))
{
}

VmaBlockMetadata::~VmaBlockMetadata()
{
}

void VmaBlockMetadata::Init(VkDeviceSize size)
{
    m_Size = size;
    m_FreeCount = 1;
    m_SumFreeSize = size;

    VmaSuballocation suballoc = {};
    suballoc.offset = 0;
    suballoc.size = size;
    suballoc.type = VMA_SUBALLOCATION_TYPE_FREE;
    suballoc.hAllocation = VK_NULL_HANDLE;

    m_Suballocations.push_back(suballoc);
    VmaSuballocationList::iterator suballocItem = m_Suballocations.end();
    --suballocItem;
    m_FreeSuballocationsBySize.push_back(suballocItem);
}

bool VmaBlockMetadata::Validate() const
{
    if(m_Suballocations.empty())
    {
        return false;
    }
    
    // Expected offset of new suballocation as calculates from previous ones.
    VkDeviceSize calculatedOffset = 0;
    // Expected number of free suballocations as calculated from traversing their list.
    uint32_t calculatedFreeCount = 0;
    // Expected sum size of free suballocations as calculated from traversing their list.
    VkDeviceSize calculatedSumFreeSize = 0;
    // Expected number of free suballocations that should be registered in
    // m_FreeSuballocationsBySize calculated from traversing their list.
    size_t freeSuballocationsToRegister = 0;
    // True if previous visisted suballocation was free.
    bool prevFree = false;

    for(VmaSuballocationList::const_iterator suballocItem = m_Suballocations.cbegin();
        suballocItem != m_Suballocations.cend();
        ++suballocItem)
    {
        const VmaSuballocation& subAlloc = *suballocItem;
        
        // Actual offset of this suballocation doesn't match expected one.
        if(subAlloc.offset != calculatedOffset)
        {
            return false;
        }

        const bool currFree = (subAlloc.type == VMA_SUBALLOCATION_TYPE_FREE);
        // Two adjacent free suballocations are invalid. They should be merged.
        if(prevFree && currFree)
        {
            return false;
        }

        if(currFree != (subAlloc.hAllocation == VK_NULL_HANDLE))
        {
            return false;
        }

        if(currFree)
        {
            calculatedSumFreeSize += subAlloc.size;
            ++calculatedFreeCount;
            if(subAlloc.size >= VMA_MIN_FREE_SUBALLOCATION_SIZE_TO_REGISTER)
            {
                ++freeSuballocationsToRegister;
            }
        }
        else
        {
            if(subAlloc.hAllocation->GetOffset() != subAlloc.offset)
            {
                return false;
            }
            if(subAlloc.hAllocation->GetSize() != subAlloc.size)
            {
                return false;
            }
        }

        calculatedOffset += subAlloc.size;
        prevFree = currFree;
    }

    // Number of free suballocations registered in m_FreeSuballocationsBySize doesn't
    // match expected one.
    if(m_FreeSuballocationsBySize.size() != freeSuballocationsToRegister)
    {
        return false;
    }

    VkDeviceSize lastSize = 0;
    for(size_t i = 0; i < m_FreeSuballocationsBySize.size(); ++i)
    {
        VmaSuballocationList::iterator suballocItem = m_FreeSuballocationsBySize[i];
        
        // Only free suballocations can be registered in m_FreeSuballocationsBySize.
        if(suballocItem->type != VMA_SUBALLOCATION_TYPE_FREE)
        {
            return false;
        }
        // They must be sorted by size ascending.
        if(suballocItem->size < lastSize)
        {
            return false;
        }

        lastSize = suballocItem->size;
    }

    // Check if totals match calculacted values.
    if(!ValidateFreeSuballocationList() ||
        (calculatedOffset != m_Size) ||
        (calculatedSumFreeSize != m_SumFreeSize) ||
        (calculatedFreeCount != m_FreeCount))
    {
        return false;
    }

    return true;
}

VkDeviceSize VmaBlockMetadata::GetUnusedRangeSizeMax() const
{
    if(!m_FreeSuballocationsBySize.empty())
    {
        return m_FreeSuballocationsBySize.back()->size;
    }
    else
    {
        return 0;
    }
}

bool VmaBlockMetadata::IsEmpty() const
{
    return (m_Suballocations.size() == 1) && (m_FreeCount == 1);
}

void VmaBlockMetadata::CalcAllocationStatInfo(VmaStatInfo& outInfo) const
{
    outInfo.blockCount = 1;

    const uint32_t rangeCount = (uint32_t)m_Suballocations.size();
    outInfo.allocationCount = rangeCount - m_FreeCount;
    outInfo.unusedRangeCount = m_FreeCount;
    
    outInfo.unusedBytes = m_SumFreeSize;
    outInfo.usedBytes = m_Size - outInfo.unusedBytes;

    outInfo.allocationSizeMin = UINT64_MAX;
    outInfo.allocationSizeMax = 0;
    outInfo.unusedRangeSizeMin = UINT64_MAX;
    outInfo.unusedRangeSizeMax = 0;

    for(VmaSuballocationList::const_iterator suballocItem = m_Suballocations.cbegin();
        suballocItem != m_Suballocations.cend();
        ++suballocItem)
    {
        const VmaSuballocation& suballoc = *suballocItem;
        if(suballoc.type != VMA_SUBALLOCATION_TYPE_FREE)
        {
            outInfo.allocationSizeMin = VMA_MIN(outInfo.allocationSizeMin, suballoc.size);
            outInfo.allocationSizeMax = VMA_MAX(outInfo.allocationSizeMax, suballoc.size);
        }
        else
        {
            outInfo.unusedRangeSizeMin = VMA_MIN(outInfo.unusedRangeSizeMin, suballoc.size);
            outInfo.unusedRangeSizeMax = VMA_MAX(outInfo.unusedRangeSizeMax, suballoc.size);
        }
    }
}

void VmaBlockMetadata::AddPoolStats(VmaPoolStats& inoutStats) const
{
    const uint32_t rangeCount = (uint32_t)m_Suballocations.size();

    inoutStats.size += m_Size;
    inoutStats.unusedSize += m_SumFreeSize;
    inoutStats.allocationCount += rangeCount - m_FreeCount;
    inoutStats.unusedRangeCount += m_FreeCount;
    inoutStats.unusedRangeSizeMax = VMA_MAX(inoutStats.unusedRangeSizeMax, GetUnusedRangeSizeMax());
}

#if VMA_STATS_STRING_ENABLED

void VmaBlockMetadata::PrintDetailedMap(class VmaJsonWriter& json) const
{
    json.BeginObject();

    json.WriteString("TotalBytes");
    json.WriteNumber(m_Size);

    json.WriteString("UnusedBytes");
    json.WriteNumber(m_SumFreeSize);

    json.WriteString("Allocations");
    json.WriteNumber((uint64_t)m_Suballocations.size() - m_FreeCount);

    json.WriteString("UnusedRanges");
    json.WriteNumber(m_FreeCount);

    json.WriteString("Suballocations");
    json.BeginArray();
    size_t i = 0;
    for(VmaSuballocationList::const_iterator suballocItem = m_Suballocations.cbegin();
        suballocItem != m_Suballocations.cend();
        ++suballocItem, ++i)
    {
        json.BeginObject(true);
        
        json.WriteString("Type");
        json.WriteString(VMA_SUBALLOCATION_TYPE_NAMES[suballocItem->type]);

        json.WriteString("Size");
        json.WriteNumber(suballocItem->size);

        json.WriteString("Offset");
        json.WriteNumber(suballocItem->offset);

        if(suballocItem->type != VMA_SUBALLOCATION_TYPE_FREE)
        {
            const void* pUserData = suballocItem->hAllocation->GetUserData();
            if(pUserData != VMA_NULL)
            {
                json.WriteString("UserData");
                if(suballocItem->hAllocation->IsUserDataString())
                {
                    json.WriteString((const char*)pUserData);
                }
                else
                {
                    json.BeginString();
                    json.ContinueString_Pointer(pUserData);
                    json.EndString();
                }
            }
        }

        json.EndObject();
    }
    json.EndArray();

    json.EndObject();
}

#endif // #if VMA_STATS_STRING_ENABLED

/*
How many suitable free suballocations to analyze before choosing best one.
- Set to 1 to use First-Fit algorithm - first suitable free suballocation will
  be chosen.
- Set to UINT32_MAX to use Best-Fit/Worst-Fit algorithm - all suitable free
  suballocations will be analized and best one will be chosen.
- Any other value is also acceptable.
*/
//static const uint32_t MAX_SUITABLE_SUBALLOCATIONS_TO_CHECK = 8;

void VmaBlockMetadata::CreateFirstAllocationRequest(VmaAllocationRequest* pAllocationRequest)
{
    VMA_ASSERT(IsEmpty());
    pAllocationRequest->offset = 0;
    pAllocationRequest->sumFreeSize = m_SumFreeSize;
    pAllocationRequest->sumItemSize = 0;
    pAllocationRequest->item = m_Suballocations.begin();
    pAllocationRequest->itemsToMakeLostCount = 0;
}

bool VmaBlockMetadata::CreateAllocationRequest(
    uint32_t currentFrameIndex,
    uint32_t frameInUseCount,
    VkDeviceSize bufferImageGranularity,
    VkDeviceSize allocSize,
    VkDeviceSize allocAlignment,
    VmaSuballocationType allocType,
    bool canMakeOtherLost,
    VmaAllocationRequest* pAllocationRequest)
{
    VMA_ASSERT(allocSize > 0);
    VMA_ASSERT(allocType != VMA_SUBALLOCATION_TYPE_FREE);
    VMA_ASSERT(pAllocationRequest != VMA_NULL);
    VMA_HEAVY_ASSERT(Validate());

    // There is not enough total free space in this block to fullfill the request: Early return.
    if(canMakeOtherLost == false && m_SumFreeSize < allocSize)
    {
        return false;
    }

    // New algorithm, efficiently searching freeSuballocationsBySize.
    const size_t freeSuballocCount = m_FreeSuballocationsBySize.size();
    if(freeSuballocCount > 0)
    {
        if(VMA_BEST_FIT)
        {
            // Find first free suballocation with size not less than allocSize.
            VmaSuballocationList::iterator* const it = VmaBinaryFindFirstNotLess(
                m_FreeSuballocationsBySize.data(),
                m_FreeSuballocationsBySize.data() + freeSuballocCount,
                allocSize,
                VmaSuballocationItemSizeLess());
            size_t index = it - m_FreeSuballocationsBySize.data();
            for(; index < freeSuballocCount; ++index)
            {
                if(CheckAllocation(
                    currentFrameIndex,
                    frameInUseCount,
                    bufferImageGranularity,
                    allocSize,
                    allocAlignment,
                    allocType,
                    m_FreeSuballocationsBySize[index],
                    false, // canMakeOtherLost
                    &pAllocationRequest->offset,
                    &pAllocationRequest->itemsToMakeLostCount,
                    &pAllocationRequest->sumFreeSize,
                    &pAllocationRequest->sumItemSize))
                {
                    pAllocationRequest->item = m_FreeSuballocationsBySize[index];
                    return true;
                }
            }
        }
        else
        {
            // Search staring from biggest suballocations.
            for(size_t index = freeSuballocCount; index--; )
            {
                if(CheckAllocation(
                    currentFrameIndex,
                    frameInUseCount,
                    bufferImageGranularity,
                    allocSize,
                    allocAlignment,
                    allocType,
                    m_FreeSuballocationsBySize[index],
                    false, // canMakeOtherLost
                    &pAllocationRequest->offset,
                    &pAllocationRequest->itemsToMakeLostCount,
                    &pAllocationRequest->sumFreeSize,
                    &pAllocationRequest->sumItemSize))
                {
                    pAllocationRequest->item = m_FreeSuballocationsBySize[index];
                    return true;
                }
            }
        }
    }

    if(canMakeOtherLost)
    {
        // Brute-force algorithm. TODO: Come up with something better.

        pAllocationRequest->sumFreeSize = VK_WHOLE_SIZE;
        pAllocationRequest->sumItemSize = VK_WHOLE_SIZE;

        VmaAllocationRequest tmpAllocRequest = {};
        for(VmaSuballocationList::iterator suballocIt = m_Suballocations.begin();
            suballocIt != m_Suballocations.end();
            ++suballocIt)
        {
            if(suballocIt->type == VMA_SUBALLOCATION_TYPE_FREE ||
                suballocIt->hAllocation->CanBecomeLost())
            {
                if(CheckAllocation(
                    currentFrameIndex,
                    frameInUseCount,
                    bufferImageGranularity,
                    allocSize,
                    allocAlignment,
                    allocType,
                    suballocIt,
                    canMakeOtherLost,
                    &tmpAllocRequest.offset,
                    &tmpAllocRequest.itemsToMakeLostCount,
                    &tmpAllocRequest.sumFreeSize,
                    &tmpAllocRequest.sumItemSize))
                {
                    tmpAllocRequest.item = suballocIt;

                    if(tmpAllocRequest.CalcCost() < pAllocationRequest->CalcCost())
                    {
                        *pAllocationRequest = tmpAllocRequest;
                    }
                }
            }
        }

        if(pAllocationRequest->sumItemSize != VK_WHOLE_SIZE)
        {
            return true;
        }
    }

    return false;
}

bool VmaBlockMetadata::MakeRequestedAllocationsLost(
    uint32_t currentFrameIndex,
    uint32_t frameInUseCount,
    VmaAllocationRequest* pAllocationRequest)
{
    while(pAllocationRequest->itemsToMakeLostCount > 0)
    {
        if(pAllocationRequest->item->type == VMA_SUBALLOCATION_TYPE_FREE)
        {
            ++pAllocationRequest->item;
        }
        VMA_ASSERT(pAllocationRequest->item != m_Suballocations.end());
        VMA_ASSERT(pAllocationRequest->item->hAllocation != VK_NULL_HANDLE);
        VMA_ASSERT(pAllocationRequest->item->hAllocation->CanBecomeLost());
        if(pAllocationRequest->item->hAllocation->MakeLost(currentFrameIndex, frameInUseCount))
        {
            pAllocationRequest->item = FreeSuballocation(pAllocationRequest->item);
            --pAllocationRequest->itemsToMakeLostCount;
        }
        else
        {
            return false;
        }
    }

    VMA_HEAVY_ASSERT(Validate());
    VMA_ASSERT(pAllocationRequest->item != m_Suballocations.end());
    VMA_ASSERT(pAllocationRequest->item->type == VMA_SUBALLOCATION_TYPE_FREE);
    
    return true;
}

uint32_t VmaBlockMetadata::MakeAllocationsLost(uint32_t currentFrameIndex, uint32_t frameInUseCount)
{
    uint32_t lostAllocationCount = 0;
    for(VmaSuballocationList::iterator it = m_Suballocations.begin();
        it != m_Suballocations.end();
        ++it)
    {
        if(it->type != VMA_SUBALLOCATION_TYPE_FREE &&
            it->hAllocation->CanBecomeLost() &&
            it->hAllocation->MakeLost(currentFrameIndex, frameInUseCount))
        {
            it = FreeSuballocation(it);
            ++lostAllocationCount;
        }
    }
    return lostAllocationCount;
}

void VmaBlockMetadata::Alloc(
    const VmaAllocationRequest& request,
    VmaSuballocationType type,
    VkDeviceSize allocSize,
    VmaAllocation hAllocation)
{
    VMA_ASSERT(request.item != m_Suballocations.end());
    VmaSuballocation& suballoc = *request.item;
    // Given suballocation is a free block.
    VMA_ASSERT(suballoc.type == VMA_SUBALLOCATION_TYPE_FREE);
    // Given offset is inside this suballocation.
    VMA_ASSERT(request.offset >= suballoc.offset);
    const VkDeviceSize paddingBegin = request.offset - suballoc.offset;
    VMA_ASSERT(suballoc.size >= paddingBegin + allocSize);
    const VkDeviceSize paddingEnd = suballoc.size - paddingBegin - allocSize;

    // Unregister this free suballocation from m_FreeSuballocationsBySize and update
    // it to become used.
    UnregisterFreeSuballocation(request.item);

    suballoc.offset = request.offset;
    suballoc.size = allocSize;
    suballoc.type = type;
    suballoc.hAllocation = hAllocation;

    // If there are any free bytes remaining at the end, insert new free suballocation after current one.
    if(paddingEnd)
    {
        VmaSuballocation paddingSuballoc = {};
        paddingSuballoc.offset = request.offset + allocSize;
        paddingSuballoc.size = paddingEnd;
        paddingSuballoc.type = VMA_SUBALLOCATION_TYPE_FREE;
        VmaSuballocationList::iterator next = request.item;
        ++next;
        const VmaSuballocationList::iterator paddingEndItem =
            m_Suballocations.insert(next, paddingSuballoc);
        RegisterFreeSuballocation(paddingEndItem);
    }

    // If there are any free bytes remaining at the beginning, insert new free suballocation before current one.
    if(paddingBegin)
    {
        VmaSuballocation paddingSuballoc = {};
        paddingSuballoc.offset = request.offset - paddingBegin;
        paddingSuballoc.size = paddingBegin;
        paddingSuballoc.type = VMA_SUBALLOCATION_TYPE_FREE;
        const VmaSuballocationList::iterator paddingBeginItem =
            m_Suballocations.insert(request.item, paddingSuballoc);
        RegisterFreeSuballocation(paddingBeginItem);
    }

    // Update totals.
    m_FreeCount = m_FreeCount - 1;
    if(paddingBegin > 0)
    {
        ++m_FreeCount;
    }
    if(paddingEnd > 0)
    {
        ++m_FreeCount;
    }
    m_SumFreeSize -= allocSize;
}

void VmaBlockMetadata::Free(const VmaAllocation allocation)
{
    for(VmaSuballocationList::iterator suballocItem = m_Suballocations.begin();
        suballocItem != m_Suballocations.end();
        ++suballocItem)
    {
        VmaSuballocation& suballoc = *suballocItem;
        if(suballoc.hAllocation == allocation)
        {
            FreeSuballocation(suballocItem);
            VMA_HEAVY_ASSERT(Validate());
            return;
        }
    }
    VMA_ASSERT(0 && "Not found!");
}

void VmaBlockMetadata::FreeAtOffset(VkDeviceSize offset)
{
    for(VmaSuballocationList::iterator suballocItem = m_Suballocations.begin();
        suballocItem != m_Suballocations.end();
        ++suballocItem)
    {
        VmaSuballocation& suballoc = *suballocItem;
        if(suballoc.offset == offset)
        {
            FreeSuballocation(suballocItem);
            return;
        }
    }
    VMA_ASSERT(0 && "Not found!");
}

bool VmaBlockMetadata::ValidateFreeSuballocationList() const
{
    VkDeviceSize lastSize = 0;
    for(size_t i = 0, count = m_FreeSuballocationsBySize.size(); i < count; ++i)
    {
        const VmaSuballocationList::iterator it = m_FreeSuballocationsBySize[i];

        if(it->type != VMA_SUBALLOCATION_TYPE_FREE)
        {
            VMA_ASSERT(0);
            return false;
        }
        if(it->size < VMA_MIN_FREE_SUBALLOCATION_SIZE_TO_REGISTER)
        {
            VMA_ASSERT(0);
            return false;
        }
        if(it->size < lastSize)
        {
            VMA_ASSERT(0);
            return false;
        }

        lastSize = it->size;
    }
    return true;
}

bool VmaBlockMetadata::CheckAllocation(
    uint32_t currentFrameIndex,
    uint32_t frameInUseCount,
    VkDeviceSize bufferImageGranularity,
    VkDeviceSize allocSize,
    VkDeviceSize allocAlignment,
    VmaSuballocationType allocType,
    VmaSuballocationList::const_iterator suballocItem,
    bool canMakeOtherLost,
    VkDeviceSize* pOffset,
    size_t* itemsToMakeLostCount,
    VkDeviceSize* pSumFreeSize,
    VkDeviceSize* pSumItemSize) const
{
    VMA_ASSERT(allocSize > 0);
    VMA_ASSERT(allocType != VMA_SUBALLOCATION_TYPE_FREE);
    VMA_ASSERT(suballocItem != m_Suballocations.cend());
    VMA_ASSERT(pOffset != VMA_NULL);
    
    *itemsToMakeLostCount = 0;
    *pSumFreeSize = 0;
    *pSumItemSize = 0;

    if(canMakeOtherLost)
    {
        if(suballocItem->type == VMA_SUBALLOCATION_TYPE_FREE)
        {
            *pSumFreeSize = suballocItem->size;
        }
        else
        {
            if(suballocItem->hAllocation->CanBecomeLost() &&
                suballocItem->hAllocation->GetLastUseFrameIndex() + frameInUseCount < currentFrameIndex)
            {
                ++*itemsToMakeLostCount;
                *pSumItemSize = suballocItem->size;
            }
            else
            {
                return false;
            }
        }

        // Remaining size is too small for this request: Early return.
        if(m_Size - suballocItem->offset < allocSize)
        {
            return false;
        }

        // Start from offset equal to beginning of this suballocation.
        *pOffset = suballocItem->offset;
    
        // Apply VMA_DEBUG_MARGIN at the beginning.
        if((VMA_DEBUG_MARGIN > 0) && suballocItem != m_Suballocations.cbegin())
        {
            *pOffset += VMA_DEBUG_MARGIN;
        }
    
        // Apply alignment.
        const VkDeviceSize alignment = VMA_MAX(allocAlignment, static_cast<VkDeviceSize>(VMA_DEBUG_ALIGNMENT));
        *pOffset = VmaAlignUp(*pOffset, alignment);

        // Check previous suballocations for BufferImageGranularity conflicts.
        // Make bigger alignment if necessary.
        if(bufferImageGranularity > 1)
        {
            bool bufferImageGranularityConflict = false;
            VmaSuballocationList::const_iterator prevSuballocItem = suballocItem;
            while(prevSuballocItem != m_Suballocations.cbegin())
            {
                --prevSuballocItem;
                const VmaSuballocation& prevSuballoc = *prevSuballocItem;
                if(VmaBlocksOnSamePage(prevSuballoc.offset, prevSuballoc.size, *pOffset, bufferImageGranularity))
                {
                    if(VmaIsBufferImageGranularityConflict(prevSuballoc.type, allocType))
                    {
                        bufferImageGranularityConflict = true;
                        break;
                    }
                }
                else
                    // Already on previous page.
                    break;
            }
            if(bufferImageGranularityConflict)
            {
                *pOffset = VmaAlignUp(*pOffset, bufferImageGranularity);
            }
        }
    
        // Now that we have final *pOffset, check if we are past suballocItem.
        // If yes, return false - this function should be called for another suballocItem as starting point.
        if(*pOffset >= suballocItem->offset + suballocItem->size)
        {
            return false;
        }
    
        // Calculate padding at the beginning based on current offset.
        const VkDeviceSize paddingBegin = *pOffset - suballocItem->offset;

        // Calculate required margin at the end if this is not last suballocation.
        VmaSuballocationList::const_iterator next = suballocItem;
        ++next;
        const VkDeviceSize requiredEndMargin =
            (next != m_Suballocations.cend()) ? VMA_DEBUG_MARGIN : 0;

        const VkDeviceSize totalSize = paddingBegin + allocSize + requiredEndMargin;
        // Another early return check.
        if(suballocItem->offset + totalSize > m_Size)
        {
            return false;
        }

        // Advance lastSuballocItem until desired size is reached.
        // Update itemsToMakeLostCount.
        VmaSuballocationList::const_iterator lastSuballocItem = suballocItem;
        if(totalSize > suballocItem->size)
        {
            VkDeviceSize remainingSize = totalSize - suballocItem->size;
            while(remainingSize > 0)
            {
                ++lastSuballocItem;
                if(lastSuballocItem == m_Suballocations.cend())
                {
                    return false;
                }
                if(lastSuballocItem->type == VMA_SUBALLOCATION_TYPE_FREE)
                {
                    *pSumFreeSize += lastSuballocItem->size;
                }
                else
                {
                    VMA_ASSERT(lastSuballocItem->hAllocation != VK_NULL_HANDLE);
                    if(lastSuballocItem->hAllocation->CanBecomeLost() &&
                        lastSuballocItem->hAllocation->GetLastUseFrameIndex() + frameInUseCount < currentFrameIndex)
                    {
                        ++*itemsToMakeLostCount;
                        *pSumItemSize += lastSuballocItem->size;
                    }
                    else
                    {
                        return false;
                    }
                }
                remainingSize = (lastSuballocItem->size < remainingSize) ?
                    remainingSize - lastSuballocItem->size : 0;
            }
        }

        // Check next suballocations for BufferImageGranularity conflicts.
        // If conflict exists, we must mark more allocations lost or fail.
        if(bufferImageGranularity > 1)
        {
            VmaSuballocationList::const_iterator nextSuballocItem = lastSuballocItem;
            ++nextSuballocItem;
            while(nextSuballocItem != m_Suballocations.cend())
            {
                const VmaSuballocation& nextSuballoc = *nextSuballocItem;
                if(VmaBlocksOnSamePage(*pOffset, allocSize, nextSuballoc.offset, bufferImageGranularity))
                {
                    if(VmaIsBufferImageGranularityConflict(allocType, nextSuballoc.type))
                    {
                        VMA_ASSERT(nextSuballoc.hAllocation != VK_NULL_HANDLE);
                        if(nextSuballoc.hAllocation->CanBecomeLost() &&
                            nextSuballoc.hAllocation->GetLastUseFrameIndex() + frameInUseCount < currentFrameIndex)
                        {
                            ++*itemsToMakeLostCount;
                        }
                        else
                        {
                            return false;
                        }
                    }
                }
                else
                {
                    // Already on next page.
                    break;
                }
                ++nextSuballocItem;
            }
        }
    }
    else
    {
        const VmaSuballocation& suballoc = *suballocItem;
        VMA_ASSERT(suballoc.type == VMA_SUBALLOCATION_TYPE_FREE);

        *pSumFreeSize = suballoc.size;

        // Size of this suballocation is too small for this request: Early return.
        if(suballoc.size < allocSize)
        {
            return false;
        }

        // Start from offset equal to beginning of this suballocation.
        *pOffset = suballoc.offset;
    
        // Apply VMA_DEBUG_MARGIN at the beginning.
        if((VMA_DEBUG_MARGIN > 0) && suballocItem != m_Suballocations.cbegin())
        {
            *pOffset += VMA_DEBUG_MARGIN;
        }
    
        // Apply alignment.
        const VkDeviceSize alignment = VMA_MAX(allocAlignment, static_cast<VkDeviceSize>(VMA_DEBUG_ALIGNMENT));
        *pOffset = VmaAlignUp(*pOffset, alignment);
    
        // Check previous suballocations for BufferImageGranularity conflicts.
        // Make bigger alignment if necessary.
        if(bufferImageGranularity > 1)
        {
            bool bufferImageGranularityConflict = false;
            VmaSuballocationList::const_iterator prevSuballocItem = suballocItem;
            while(prevSuballocItem != m_Suballocations.cbegin())
            {
                --prevSuballocItem;
                const VmaSuballocation& prevSuballoc = *prevSuballocItem;
                if(VmaBlocksOnSamePage(prevSuballoc.offset, prevSuballoc.size, *pOffset, bufferImageGranularity))
                {
                    if(VmaIsBufferImageGranularityConflict(prevSuballoc.type, allocType))
                    {
                        bufferImageGranularityConflict = true;
                        break;
                    }
                }
                else
                    // Already on previous page.
                    break;
            }
            if(bufferImageGranularityConflict)
            {
                *pOffset = VmaAlignUp(*pOffset, bufferImageGranularity);
            }
        }
    
        // Calculate padding at the beginning based on current offset.
        const VkDeviceSize paddingBegin = *pOffset - suballoc.offset;

        // Calculate required margin at the end if this is not last suballocation.
        VmaSuballocationList::const_iterator next = suballocItem;
        ++next;
        const VkDeviceSize requiredEndMargin =
            (next != m_Suballocations.cend()) ? VMA_DEBUG_MARGIN : 0;

        // Fail if requested size plus margin before and after is bigger than size of this suballocation.
        if(paddingBegin + allocSize + requiredEndMargin > suballoc.size)
        {
            return false;
        }

        // Check next suballocations for BufferImageGranularity conflicts.
        // If conflict exists, allocation cannot be made here.
        if(bufferImageGranularity > 1)
        {
            VmaSuballocationList::const_iterator nextSuballocItem = suballocItem;
            ++nextSuballocItem;
            while(nextSuballocItem != m_Suballocations.cend())
            {
                const VmaSuballocation& nextSuballoc = *nextSuballocItem;
                if(VmaBlocksOnSamePage(*pOffset, allocSize, nextSuballoc.offset, bufferImageGranularity))
                {
                    if(VmaIsBufferImageGranularityConflict(allocType, nextSuballoc.type))
                    {
                        return false;
                    }
                }
                else
                {
                    // Already on next page.
                    break;
                }
                ++nextSuballocItem;
            }
        }
    }

    // All tests passed: Success. pOffset is already filled.
    return true;
}

void VmaBlockMetadata::MergeFreeWithNext(VmaSuballocationList::iterator item)
{
    VMA_ASSERT(item != m_Suballocations.end());
    VMA_ASSERT(item->type == VMA_SUBALLOCATION_TYPE_FREE);
    
    VmaSuballocationList::iterator nextItem = item;
    ++nextItem;
    VMA_ASSERT(nextItem != m_Suballocations.end());
    VMA_ASSERT(nextItem->type == VMA_SUBALLOCATION_TYPE_FREE);

    item->size += nextItem->size;
    --m_FreeCount;
    m_Suballocations.erase(nextItem);
}

VmaSuballocationList::iterator VmaBlockMetadata::FreeSuballocation(VmaSuballocationList::iterator suballocItem)
{
    // Change this suballocation to be marked as free.
    VmaSuballocation& suballoc = *suballocItem;
    suballoc.type = VMA_SUBALLOCATION_TYPE_FREE;
    suballoc.hAllocation = VK_NULL_HANDLE;
    
    // Update totals.
    ++m_FreeCount;
    m_SumFreeSize += suballoc.size;

    // Merge with previous and/or next suballocation if it's also free.
    bool mergeWithNext = false;
    bool mergeWithPrev = false;
    
    VmaSuballocationList::iterator nextItem = suballocItem;
    ++nextItem;
    if((nextItem != m_Suballocations.end()) && (nextItem->type == VMA_SUBALLOCATION_TYPE_FREE))
    {
        mergeWithNext = true;
    }

    VmaSuballocationList::iterator prevItem = suballocItem;
    if(suballocItem != m_Suballocations.begin())
    {
        --prevItem;
        if(prevItem->type == VMA_SUBALLOCATION_TYPE_FREE)
        {
            mergeWithPrev = true;
        }
    }

    if(mergeWithNext)
    {
        UnregisterFreeSuballocation(nextItem);
        MergeFreeWithNext(suballocItem);
    }

    if(mergeWithPrev)
    {
        UnregisterFreeSuballocation(prevItem);
        MergeFreeWithNext(prevItem);
        RegisterFreeSuballocation(prevItem);
        return prevItem;
    }
    else
    {
        RegisterFreeSuballocation(suballocItem);
        return suballocItem;
    }
}

void VmaBlockMetadata::RegisterFreeSuballocation(VmaSuballocationList::iterator item)
{
    VMA_ASSERT(item->type == VMA_SUBALLOCATION_TYPE_FREE);
    VMA_ASSERT(item->size > 0);

    // You may want to enable this validation at the beginning or at the end of
    // this function, depending on what do you want to check.
    VMA_HEAVY_ASSERT(ValidateFreeSuballocationList());

    if(item->size >= VMA_MIN_FREE_SUBALLOCATION_SIZE_TO_REGISTER)
    {
        if(m_FreeSuballocationsBySize.empty())
        {
            m_FreeSuballocationsBySize.push_back(item);
        }
        else
        {
            VmaVectorInsertSorted<VmaSuballocationItemSizeLess>(m_FreeSuballocationsBySize, item);
        }
    }

    //VMA_HEAVY_ASSERT(ValidateFreeSuballocationList());
}


void VmaBlockMetadata::UnregisterFreeSuballocation(VmaSuballocationList::iterator item)
{
    VMA_ASSERT(item->type == VMA_SUBALLOCATION_TYPE_FREE);
    VMA_ASSERT(item->size > 0);

    // You may want to enable this validation at the beginning or at the end of
    // this function, depending on what do you want to check.
    VMA_HEAVY_ASSERT(ValidateFreeSuballocationList());

    if(item->size >= VMA_MIN_FREE_SUBALLOCATION_SIZE_TO_REGISTER)
    {
        VmaSuballocationList::iterator* const it = VmaBinaryFindFirstNotLess(
            m_FreeSuballocationsBySize.data(),
            m_FreeSuballocationsBySize.data() + m_FreeSuballocationsBySize.size(),
            item,
            VmaSuballocationItemSizeLess());
        for(size_t index = it - m_FreeSuballocationsBySize.data();
            index < m_FreeSuballocationsBySize.size();
            ++index)
        {
            if(m_FreeSuballocationsBySize[index] == item)
            {
                VmaVectorRemove(m_FreeSuballocationsBySize, index);
                return;
            }
            VMA_ASSERT((m_FreeSuballocationsBySize[index]->size == item->size) && "Not found.");
        }
        VMA_ASSERT(0 && "Not found.");
    }

    //VMA_HEAVY_ASSERT(ValidateFreeSuballocationList());
}

////////////////////////////////////////////////////////////////////////////////
// class VmaDeviceMemoryBlock

VmaDeviceMemoryBlock::VmaDeviceMemoryBlock(VmaAllocator hAllocator) :
    m_Metadata(hAllocator),
    m_MemoryTypeIndex(UINT32_MAX),
    m_hMemory(VK_NULL_HANDLE),
    m_MapCount(0),
    m_pMappedData(VMA_NULL)
{
}

void VmaDeviceMemoryBlock::Init(
    uint32_t newMemoryTypeIndex,
    VkDeviceMemory newMemory,
    VkDeviceSize newSize)
{
    VMA_ASSERT(m_hMemory == VK_NULL_HANDLE);

    m_MemoryTypeIndex = newMemoryTypeIndex;
    m_hMemory = newMemory;

    m_Metadata.Init(newSize);
}

void VmaDeviceMemoryBlock::Destroy(VmaAllocator allocator)
{
    // This is the most important assert in the entire library.
    // Hitting it means you have some memory leak - unreleased VmaAllocation objects.
    VMA_ASSERT(m_Metadata.IsEmpty() && "Some allocations were not freed before destruction of this memory block!");
    
    VMA_ASSERT(m_hMemory != VK_NULL_HANDLE);
    allocator->FreeVulkanMemory(m_MemoryTypeIndex, m_Metadata.GetSize(), m_hMemory);
    m_hMemory = VK_NULL_HANDLE;
}

bool VmaDeviceMemoryBlock::Validate() const
{
    if((m_hMemory == VK_NULL_HANDLE) ||
        (m_Metadata.GetSize() == 0))
    {
        return false;
    }
    
    return m_Metadata.Validate();
}

VkResult VmaDeviceMemoryBlock::Map(VmaAllocator hAllocator, uint32_t count, void** ppData)
{
    if(count == 0)
    {
        return VK_SUCCESS;
    }

    VmaMutexLock lock(m_Mutex, hAllocator->m_UseMutex);
    if(m_MapCount != 0)
    {
        m_MapCount += count;
        VMA_ASSERT(m_pMappedData != VMA_NULL);
        if(ppData != VMA_NULL)
        {
            *ppData = m_pMappedData;
        }
        return VK_SUCCESS;
    }
    else
    {
        VkResult result = (*hAllocator->GetVulkanFunctions().vkMapMemory)(
            hAllocator->m_hDevice,
            m_hMemory,
            0, // offset
            VK_WHOLE_SIZE,
            0, // flags
            &m_pMappedData);
        if(result == VK_SUCCESS)
        {
            if(ppData != VMA_NULL)
            {
                *ppData = m_pMappedData;
            }
            m_MapCount = count;
        }
        return result;
    }
}

void VmaDeviceMemoryBlock::Unmap(VmaAllocator hAllocator, uint32_t count)
{
    if(count == 0)
    {
        return;
    }

    VmaMutexLock lock(m_Mutex, hAllocator->m_UseMutex);
    if(m_MapCount >= count)
    {
        m_MapCount -= count;
        if(m_MapCount == 0)
        {
            m_pMappedData = VMA_NULL;
            (*hAllocator->GetVulkanFunctions().vkUnmapMemory)(hAllocator->m_hDevice, m_hMemory);
        }
    }
    else
    {
        VMA_ASSERT(0 && "VkDeviceMemory block is being unmapped while it was not previously mapped.");
    }
}

VkResult VmaDeviceMemoryBlock::BindBufferMemory(
    const VmaAllocator hAllocator,
    const VmaAllocation hAllocation,
    VkBuffer hBuffer)
{
    VMA_ASSERT(hAllocation->GetType() == VmaAllocation_T::ALLOCATION_TYPE_BLOCK &&
        hAllocation->GetBlock() == this);
    // This lock is important so that we don't call vkBind... and/or vkMap... simultaneously on the same VkDeviceMemory from multiple threads.
    VmaMutexLock lock(m_Mutex, hAllocator->m_UseMutex);
    return hAllocator->GetVulkanFunctions().vkBindBufferMemory(
        hAllocator->m_hDevice,
        hBuffer,
        m_hMemory,
        hAllocation->GetOffset());
}

VkResult VmaDeviceMemoryBlock::BindImageMemory(
    const VmaAllocator hAllocator,
    const VmaAllocation hAllocation,
    VkImage hImage)
{
    VMA_ASSERT(hAllocation->GetType() == VmaAllocation_T::ALLOCATION_TYPE_BLOCK &&
        hAllocation->GetBlock() == this);
    // This lock is important so that we don't call vkBind... and/or vkMap... simultaneously on the same VkDeviceMemory from multiple threads.
    VmaMutexLock lock(m_Mutex, hAllocator->m_UseMutex);
    return hAllocator->GetVulkanFunctions().vkBindImageMemory(
        hAllocator->m_hDevice,
        hImage,
        m_hMemory,
        hAllocation->GetOffset());
}

static void InitStatInfo(VmaStatInfo& outInfo)
{
    memset(&outInfo, 0, sizeof(outInfo));
    outInfo.allocationSizeMin = UINT64_MAX;
    outInfo.unusedRangeSizeMin = UINT64_MAX;
}

// Adds statistics srcInfo into inoutInfo, like: inoutInfo += srcInfo.
static void VmaAddStatInfo(VmaStatInfo& inoutInfo, const VmaStatInfo& srcInfo)
{
    inoutInfo.blockCount += srcInfo.blockCount;
    inoutInfo.allocationCount += srcInfo.allocationCount;
    inoutInfo.unusedRangeCount += srcInfo.unusedRangeCount;
    inoutInfo.usedBytes += srcInfo.usedBytes;
    inoutInfo.unusedBytes += srcInfo.unusedBytes;
    inoutInfo.allocationSizeMin = VMA_MIN(inoutInfo.allocationSizeMin, srcInfo.allocationSizeMin);
    inoutInfo.allocationSizeMax = VMA_MAX(inoutInfo.allocationSizeMax, srcInfo.allocationSizeMax);
    inoutInfo.unusedRangeSizeMin = VMA_MIN(inoutInfo.unusedRangeSizeMin, srcInfo.unusedRangeSizeMin);
    inoutInfo.unusedRangeSizeMax = VMA_MAX(inoutInfo.unusedRangeSizeMax, srcInfo.unusedRangeSizeMax);
}

static void VmaPostprocessCalcStatInfo(VmaStatInfo& inoutInfo)
{
    inoutInfo.allocationSizeAvg = (inoutInfo.allocationCount > 0) ?
        VmaRoundDiv<VkDeviceSize>(inoutInfo.usedBytes, inoutInfo.allocationCount) : 0;
    inoutInfo.unusedRangeSizeAvg = (inoutInfo.unusedRangeCount > 0) ?
        VmaRoundDiv<VkDeviceSize>(inoutInfo.unusedBytes, inoutInfo.unusedRangeCount) : 0;
}

VmaPool_T::VmaPool_T(
    VmaAllocator hAllocator,
    const VmaPoolCreateInfo& createInfo) :
    m_BlockVector(
        hAllocator,
        createInfo.memoryTypeIndex,
        createInfo.blockSize,
        createInfo.minBlockCount,
        createInfo.maxBlockCount,
        (createInfo.flags & VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT) != 0 ? 1 : hAllocator->GetBufferImageGranularity(),
        createInfo.frameInUseCount,
        true) // isCustomPool
{
}

VmaPool_T::~VmaPool_T()
{
}

#if VMA_STATS_STRING_ENABLED

#endif // #if VMA_STATS_STRING_ENABLED

VmaBlockVector::VmaBlockVector(
    VmaAllocator hAllocator,
    uint32_t memoryTypeIndex,
    VkDeviceSize preferredBlockSize,
    size_t minBlockCount,
    size_t maxBlockCount,
    VkDeviceSize bufferImageGranularity,
    uint32_t frameInUseCount,
    bool isCustomPool) :
    m_hAllocator(hAllocator),
    m_MemoryTypeIndex(memoryTypeIndex),
    m_PreferredBlockSize(preferredBlockSize),
    m_MinBlockCount(minBlockCount),
    m_MaxBlockCount(maxBlockCount),
    m_BufferImageGranularity(bufferImageGranularity),
    m_FrameInUseCount(frameInUseCount),
    m_IsCustomPool(isCustomPool),
    m_Blocks(VmaStlAllocator<VmaDeviceMemoryBlock*>(hAllocator->GetAllocationCallbacks())),
    m_HasEmptyBlock(false),
    m_pDefragmentator(VMA_NULL)
{
}

VmaBlockVector::~VmaBlockVector()
{
    VMA_ASSERT(m_pDefragmentator == VMA_NULL);

    for(size_t i = m_Blocks.size(); i--; )
    {
        m_Blocks[i]->Destroy(m_hAllocator);
        vma_delete(m_hAllocator, m_Blocks[i]);
    }
}

VkResult VmaBlockVector::CreateMinBlocks()
{
    for(size_t i = 0; i < m_MinBlockCount; ++i)
    {
        VkResult res = CreateBlock(m_PreferredBlockSize, VMA_NULL);
        if(res != VK_SUCCESS)
        {
            return res;
        }
    }
    return VK_SUCCESS;
}

void VmaBlockVector::GetPoolStats(VmaPoolStats* pStats)
{
    pStats->size = 0;
    pStats->unusedSize = 0;
    pStats->allocationCount = 0;
    pStats->unusedRangeCount = 0;
    pStats->unusedRangeSizeMax = 0;

    VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);

    for(uint32_t blockIndex = 0; blockIndex < m_Blocks.size(); ++blockIndex)
    {
        const VmaDeviceMemoryBlock* const pBlock = m_Blocks[blockIndex];
        VMA_ASSERT(pBlock);
        VMA_HEAVY_ASSERT(pBlock->Validate());
        pBlock->m_Metadata.AddPoolStats(*pStats);
    }
}

static const uint32_t VMA_ALLOCATION_TRY_COUNT = 32;

VkResult VmaBlockVector::Allocate(
    VmaPool hCurrentPool,
    uint32_t currentFrameIndex,
    const VkMemoryRequirements& vkMemReq,
    const VmaAllocationCreateInfo& createInfo,
    VmaSuballocationType suballocType,
    VmaAllocation* pAllocation)
{
    const bool mapped = (createInfo.flags & VMA_ALLOCATION_CREATE_MAPPED_BIT) != 0;
    const bool isUserDataString = (createInfo.flags & VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT) != 0;

    VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);

    // 1. Search existing allocations. Try to allocate without making other allocations lost.
    // Forward order in m_Blocks - prefer blocks with smallest amount of free space.
    for(size_t blockIndex = 0; blockIndex < m_Blocks.size(); ++blockIndex )
    {
        VmaDeviceMemoryBlock* const pCurrBlock = m_Blocks[blockIndex];
        VMA_ASSERT(pCurrBlock);
        VmaAllocationRequest currRequest = {};
        if(pCurrBlock->m_Metadata.CreateAllocationRequest(
            currentFrameIndex,
            m_FrameInUseCount,
            m_BufferImageGranularity,
            vkMemReq.size,
            vkMemReq.alignment,
            suballocType,
            false, // canMakeOtherLost
            &currRequest))
        {
            // Allocate from pCurrBlock.
            VMA_ASSERT(currRequest.itemsToMakeLostCount == 0);

            if(mapped)
            {
                VkResult res = pCurrBlock->Map(m_hAllocator, 1, VMA_NULL);
                if(res != VK_SUCCESS)
                {
                    return res;
                }
            }
            
            // We no longer have an empty Allocation.
            if(pCurrBlock->m_Metadata.IsEmpty())
            {
                m_HasEmptyBlock = false;
            }
            
            *pAllocation = vma_new(m_hAllocator, VmaAllocation_T)(currentFrameIndex, isUserDataString);
            pCurrBlock->m_Metadata.Alloc(currRequest, suballocType, vkMemReq.size, *pAllocation);
            (*pAllocation)->InitBlockAllocation(
                hCurrentPool,
                pCurrBlock,
                currRequest.offset,
                vkMemReq.alignment,
                vkMemReq.size,
                suballocType,
                mapped,
                (createInfo.flags & VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT) != 0);
            VMA_HEAVY_ASSERT(pCurrBlock->Validate());
            VMA_DEBUG_LOG("    Returned from existing allocation #%u", (uint32_t)blockIndex);
            (*pAllocation)->SetUserData(m_hAllocator, createInfo.pUserData);
            return VK_SUCCESS;
        }
    }

    const bool canCreateNewBlock =
        ((createInfo.flags & VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT) == 0) &&
        (m_Blocks.size() < m_MaxBlockCount);

    // 2. Try to create new block.
    if(canCreateNewBlock)
    {
        // Calculate optimal size for new block.
        VkDeviceSize newBlockSize = m_PreferredBlockSize;
        uint32_t newBlockSizeShift = 0;
        const uint32_t NEW_BLOCK_SIZE_SHIFT_MAX = 3;

        // Allocating blocks of other sizes is allowed only in default pools.
        // In custom pools block size is fixed.
        if(m_IsCustomPool == false)
        {
            // Allocate 1/8, 1/4, 1/2 as first blocks.
            const VkDeviceSize maxExistingBlockSize = CalcMaxBlockSize();
            for(uint32_t i = 0; i < NEW_BLOCK_SIZE_SHIFT_MAX; ++i)
            {
                const VkDeviceSize smallerNewBlockSize = newBlockSize / 2;
                if(smallerNewBlockSize > maxExistingBlockSize && smallerNewBlockSize >= vkMemReq.size * 2)
                {
                    newBlockSize = smallerNewBlockSize;
                    ++newBlockSizeShift;
                }
                else
                {
                    break;
                }
            }
        }

        size_t newBlockIndex = 0;
        VkResult res = CreateBlock(newBlockSize, &newBlockIndex);
        // Allocation of this size failed? Try 1/2, 1/4, 1/8 of m_PreferredBlockSize.
        if(m_IsCustomPool == false)
        {
            while(res < 0 && newBlockSizeShift < NEW_BLOCK_SIZE_SHIFT_MAX)
            {
                const VkDeviceSize smallerNewBlockSize = newBlockSize / 2;
                if(smallerNewBlockSize >= vkMemReq.size)
                {
                    newBlockSize = smallerNewBlockSize;
                    ++newBlockSizeShift;
                    res = CreateBlock(newBlockSize, &newBlockIndex);
                }
                else
                {
                    break;
                }
            }
        }

        if(res == VK_SUCCESS)
        {
            VmaDeviceMemoryBlock* const pBlock = m_Blocks[newBlockIndex];
            VMA_ASSERT(pBlock->m_Metadata.GetSize() >= vkMemReq.size);

            if(mapped)
            {
                res = pBlock->Map(m_hAllocator, 1, VMA_NULL);
                if(res != VK_SUCCESS)
                {
                    return res;
                }
            }

            // Allocate from pBlock. Because it is empty, dstAllocRequest can be trivially filled.
            VmaAllocationRequest allocRequest;
            pBlock->m_Metadata.CreateFirstAllocationRequest(&allocRequest);
            *pAllocation = vma_new(m_hAllocator, VmaAllocation_T)(currentFrameIndex, isUserDataString);
            pBlock->m_Metadata.Alloc(allocRequest, suballocType, vkMemReq.size, *pAllocation);
            (*pAllocation)->InitBlockAllocation(
                hCurrentPool,
                pBlock,
                allocRequest.offset,
                vkMemReq.alignment,
                vkMemReq.size,
                suballocType,
                mapped,
                (createInfo.flags & VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT) != 0);
            VMA_HEAVY_ASSERT(pBlock->Validate());
            VMA_DEBUG_LOG("    Created new allocation Size=%llu", allocInfo.allocationSize);
            (*pAllocation)->SetUserData(m_hAllocator, createInfo.pUserData);
            return VK_SUCCESS;
        }
    }

    const bool canMakeOtherLost = (createInfo.flags & VMA_ALLOCATION_CREATE_CAN_MAKE_OTHER_LOST_BIT) != 0;

    // 3. Try to allocate from existing blocks with making other allocations lost.
    if(canMakeOtherLost)
    {
        uint32_t tryIndex = 0;
        for(; tryIndex < VMA_ALLOCATION_TRY_COUNT; ++tryIndex)
        {
            VmaDeviceMemoryBlock* pBestRequestBlock = VMA_NULL;
            VmaAllocationRequest bestRequest = {};
            VkDeviceSize bestRequestCost = VK_WHOLE_SIZE;

            // 1. Search existing allocations.
            // Forward order in m_Blocks - prefer blocks with smallest amount of free space.
            for(size_t blockIndex = 0; blockIndex < m_Blocks.size(); ++blockIndex )
            {
                VmaDeviceMemoryBlock* const pCurrBlock = m_Blocks[blockIndex];
                VMA_ASSERT(pCurrBlock);
                VmaAllocationRequest currRequest = {};
                if(pCurrBlock->m_Metadata.CreateAllocationRequest(
                    currentFrameIndex,
                    m_FrameInUseCount,
                    m_BufferImageGranularity,
                    vkMemReq.size,
                    vkMemReq.alignment,
                    suballocType,
                    canMakeOtherLost,
                    &currRequest))
                {
                    const VkDeviceSize currRequestCost = currRequest.CalcCost();
                    if(pBestRequestBlock == VMA_NULL ||
                        currRequestCost < bestRequestCost)
                    {
                        pBestRequestBlock = pCurrBlock;
                        bestRequest = currRequest;
                        bestRequestCost = currRequestCost;

                        if(bestRequestCost == 0)
                        {
                            break;
                        }
                    }
                }
            }

            if(pBestRequestBlock != VMA_NULL)
            {
                if(mapped)
                {
                    VkResult res = pBestRequestBlock->Map(m_hAllocator, 1, VMA_NULL);
                    if(res != VK_SUCCESS)
                    {
                        return res;
                    }
                }

                if(pBestRequestBlock->m_Metadata.MakeRequestedAllocationsLost(
                    currentFrameIndex,
                    m_FrameInUseCount,
                    &bestRequest))
                {
                    // We no longer have an empty Allocation.
                    if(pBestRequestBlock->m_Metadata.IsEmpty())
                    {
                        m_HasEmptyBlock = false;
                    }
                    // Allocate from this pBlock.
                    *pAllocation = vma_new(m_hAllocator, VmaAllocation_T)(currentFrameIndex, isUserDataString);
                    pBestRequestBlock->m_Metadata.Alloc(bestRequest, suballocType, vkMemReq.size, *pAllocation);
                    (*pAllocation)->InitBlockAllocation(
                        hCurrentPool,
                        pBestRequestBlock,
                        bestRequest.offset,
                        vkMemReq.alignment,
                        vkMemReq.size,
                        suballocType,
                        mapped,
                        (createInfo.flags & VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT) != 0);
                    VMA_HEAVY_ASSERT(pBestRequestBlock->Validate());
                    VMA_DEBUG_LOG("    Returned from existing allocation #%u", (uint32_t)blockIndex);
                    (*pAllocation)->SetUserData(m_hAllocator, createInfo.pUserData);
                    return VK_SUCCESS;
                }
                // else: Some allocations must have been touched while we are here. Next try.
            }
            else
            {
                // Could not find place in any of the blocks - break outer loop.
                break;
            }
        }
        /* Maximum number of tries exceeded - a very unlike event when many other
        threads are simultaneously touching allocations making it impossible to make
        lost at the same time as we try to allocate. */
        if(tryIndex == VMA_ALLOCATION_TRY_COUNT)
        {
            return VK_ERROR_TOO_MANY_OBJECTS;
        }
    }

    return VK_ERROR_OUT_OF_DEVICE_MEMORY;
}

void VmaBlockVector::Free(
    VmaAllocation hAllocation)
{
    VmaDeviceMemoryBlock* pBlockToDelete = VMA_NULL;

    // Scope for lock.
    {
        VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);

        VmaDeviceMemoryBlock* pBlock = hAllocation->GetBlock();

        if(hAllocation->IsPersistentMap())
        {
            pBlock->Unmap(m_hAllocator, 1);
        }

        pBlock->m_Metadata.Free(hAllocation);
        VMA_HEAVY_ASSERT(pBlock->Validate());

        VMA_DEBUG_LOG("  Freed from MemoryTypeIndex=%u", memTypeIndex);

        // pBlock became empty after this deallocation.
        if(pBlock->m_Metadata.IsEmpty())
        {
            // Already has empty Allocation. We don't want to have two, so delete this one.
            if(m_HasEmptyBlock && m_Blocks.size() > m_MinBlockCount)
            {
                pBlockToDelete = pBlock;
                Remove(pBlock);
            }
            // We now have first empty Allocation.
            else
            {
                m_HasEmptyBlock = true;
            }
        }
        // pBlock didn't become empty, but we have another empty block - find and free that one.
        // (This is optional, heuristics.)
        else if(m_HasEmptyBlock)
        {
            VmaDeviceMemoryBlock* pLastBlock = m_Blocks.back();
            if(pLastBlock->m_Metadata.IsEmpty() && m_Blocks.size() > m_MinBlockCount)
            {
                pBlockToDelete = pLastBlock;
                m_Blocks.pop_back();
                m_HasEmptyBlock = false;
            }
        }

        IncrementallySortBlocks();
    }

    // Destruction of a free Allocation. Deferred until this point, outside of mutex
    // lock, for performance reason.
    if(pBlockToDelete != VMA_NULL)
    {
        VMA_DEBUG_LOG("    Deleted empty allocation");
        pBlockToDelete->Destroy(m_hAllocator);
        vma_delete(m_hAllocator, pBlockToDelete);
    }
}

size_t VmaBlockVector::CalcMaxBlockSize() const
{
    size_t result = 0;
    for(size_t i = m_Blocks.size(); i--; )
    {
        result = VMA_MAX((uint64_t)result, (uint64_t)m_Blocks[i]->m_Metadata.GetSize());
        if(result >= m_PreferredBlockSize)
        {
            break;
        }
    }
    return result;
}

void VmaBlockVector::Remove(VmaDeviceMemoryBlock* pBlock)
{
    for(uint32_t blockIndex = 0; blockIndex < m_Blocks.size(); ++blockIndex)
    {
        if(m_Blocks[blockIndex] == pBlock)
        {
            VmaVectorRemove(m_Blocks, blockIndex);
            return;
        }
    }
    VMA_ASSERT(0);
}

void VmaBlockVector::IncrementallySortBlocks()
{
    // Bubble sort only until first swap.
    for(size_t i = 1; i < m_Blocks.size(); ++i)
    {
        if(m_Blocks[i - 1]->m_Metadata.GetSumFreeSize() > m_Blocks[i]->m_Metadata.GetSumFreeSize())
        {
            VMA_SWAP(m_Blocks[i - 1], m_Blocks[i]);
            return;
        }
    }
}

VkResult VmaBlockVector::CreateBlock(VkDeviceSize blockSize, size_t* pNewBlockIndex)
{
    VkMemoryAllocateInfo allocInfo = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    allocInfo.memoryTypeIndex = m_MemoryTypeIndex;
    allocInfo.allocationSize = blockSize;
    VkDeviceMemory mem = VK_NULL_HANDLE;
    VkResult res = m_hAllocator->AllocateVulkanMemory(&allocInfo, &mem);
    if(res < 0)
    {
        return res;
    }

    // New VkDeviceMemory successfully created.

    // Create new Allocation for it.
    VmaDeviceMemoryBlock* const pBlock = vma_new(m_hAllocator, VmaDeviceMemoryBlock)(m_hAllocator);
    pBlock->Init(
        m_MemoryTypeIndex,
        mem,
        allocInfo.allocationSize);

    m_Blocks.push_back(pBlock);
    if(pNewBlockIndex != VMA_NULL)
    {
        *pNewBlockIndex = m_Blocks.size() - 1;
    }

    return VK_SUCCESS;
}

#if VMA_STATS_STRING_ENABLED

void VmaBlockVector::PrintDetailedMap(class VmaJsonWriter& json)
{
    VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);

    json.BeginObject();

    if(m_IsCustomPool)
    {
        json.WriteString("MemoryTypeIndex");
        json.WriteNumber(m_MemoryTypeIndex);

        json.WriteString("BlockSize");
        json.WriteNumber(m_PreferredBlockSize);

        json.WriteString("BlockCount");
        json.BeginObject(true);
        if(m_MinBlockCount > 0)
        {
            json.WriteString("Min");
            json.WriteNumber((uint64_t)m_MinBlockCount);
        }
        if(m_MaxBlockCount < SIZE_MAX)
        {
            json.WriteString("Max");
            json.WriteNumber((uint64_t)m_MaxBlockCount);
        }
        json.WriteString("Cur");
        json.WriteNumber((uint64_t)m_Blocks.size());
        json.EndObject();

        if(m_FrameInUseCount > 0)
        {
            json.WriteString("FrameInUseCount");
            json.WriteNumber(m_FrameInUseCount);
        }
    }
    else
    {
        json.WriteString("PreferredBlockSize");
        json.WriteNumber(m_PreferredBlockSize);
    }

    json.WriteString("Blocks");
    json.BeginArray();
    for(size_t i = 0; i < m_Blocks.size(); ++i)
    {
        m_Blocks[i]->m_Metadata.PrintDetailedMap(json);
    }
    json.EndArray();

    json.EndObject();
}

#endif // #if VMA_STATS_STRING_ENABLED

VmaDefragmentator* VmaBlockVector::EnsureDefragmentator(
    VmaAllocator hAllocator,
    uint32_t currentFrameIndex)
{
    if(m_pDefragmentator == VMA_NULL)
    {
        m_pDefragmentator = vma_new(m_hAllocator, VmaDefragmentator)(
            hAllocator,
            this,
            currentFrameIndex);
    }

    return m_pDefragmentator;
}

VkResult VmaBlockVector::Defragment(
    VmaDefragmentationStats* pDefragmentationStats,
    VkDeviceSize& maxBytesToMove,
    uint32_t& maxAllocationsToMove)
{
    if(m_pDefragmentator == VMA_NULL)
    {
        return VK_SUCCESS;
    }

    VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);

    // Defragment.
    VkResult result = m_pDefragmentator->Defragment(maxBytesToMove, maxAllocationsToMove);

    // Accumulate statistics.
    if(pDefragmentationStats != VMA_NULL)
    {
        const VkDeviceSize bytesMoved = m_pDefragmentator->GetBytesMoved();
        const uint32_t allocationsMoved = m_pDefragmentator->GetAllocationsMoved();
        pDefragmentationStats->bytesMoved += bytesMoved;
        pDefragmentationStats->allocationsMoved += allocationsMoved;
        VMA_ASSERT(bytesMoved <= maxBytesToMove);
        VMA_ASSERT(allocationsMoved <= maxAllocationsToMove);
        maxBytesToMove -= bytesMoved;
        maxAllocationsToMove -= allocationsMoved;
    }
    
    // Free empty blocks.
    m_HasEmptyBlock = false;
    for(size_t blockIndex = m_Blocks.size(); blockIndex--; )
    {
        VmaDeviceMemoryBlock* pBlock = m_Blocks[blockIndex];
        if(pBlock->m_Metadata.IsEmpty())
        {
            if(m_Blocks.size() > m_MinBlockCount)
            {
                if(pDefragmentationStats != VMA_NULL)
                {
                    ++pDefragmentationStats->deviceMemoryBlocksFreed;
                    pDefragmentationStats->bytesFreed += pBlock->m_Metadata.GetSize();
                }

                VmaVectorRemove(m_Blocks, blockIndex);
                pBlock->Destroy(m_hAllocator);
                vma_delete(m_hAllocator, pBlock);
            }
            else
            {
                m_HasEmptyBlock = true;
            }
        }
    }

    return result;
}

void VmaBlockVector::DestroyDefragmentator()
{
    if(m_pDefragmentator != VMA_NULL)
    {
        vma_delete(m_hAllocator, m_pDefragmentator);
        m_pDefragmentator = VMA_NULL;
    }
}

void VmaBlockVector::MakePoolAllocationsLost(
    uint32_t currentFrameIndex,
    size_t* pLostAllocationCount)
{
    VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);
    size_t lostAllocationCount = 0;
    for(uint32_t blockIndex = 0; blockIndex < m_Blocks.size(); ++blockIndex)
    {
        VmaDeviceMemoryBlock* const pBlock = m_Blocks[blockIndex];
        VMA_ASSERT(pBlock);
        lostAllocationCount += pBlock->m_Metadata.MakeAllocationsLost(currentFrameIndex, m_FrameInUseCount);
    }
    if(pLostAllocationCount != VMA_NULL)
    {
        *pLostAllocationCount = lostAllocationCount;
    }
}

void VmaBlockVector::AddStats(VmaStats* pStats)
{
    const uint32_t memTypeIndex = m_MemoryTypeIndex;
    const uint32_t memHeapIndex = m_hAllocator->MemoryTypeIndexToHeapIndex(memTypeIndex);

    VmaMutexLock lock(m_Mutex, m_hAllocator->m_UseMutex);

    for(uint32_t blockIndex = 0; blockIndex < m_Blocks.size(); ++blockIndex)
    {
        const VmaDeviceMemoryBlock* const pBlock = m_Blocks[blockIndex];
        VMA_ASSERT(pBlock);
        VMA_HEAVY_ASSERT(pBlock->Validate());
        VmaStatInfo allocationStatInfo;
        pBlock->m_Metadata.CalcAllocationStatInfo(allocationStatInfo);
        VmaAddStatInfo(pStats->total, allocationStatInfo);
        VmaAddStatInfo(pStats->memoryType[memTypeIndex], allocationStatInfo);
        VmaAddStatInfo(pStats->memoryHeap[memHeapIndex], allocationStatInfo);
    }
}

////////////////////////////////////////////////////////////////////////////////
// VmaDefragmentator members definition

VmaDefragmentator::VmaDefragmentator(
    VmaAllocator hAllocator,
    VmaBlockVector* pBlockVector,
    uint32_t currentFrameIndex) :
    m_hAllocator(hAllocator),
    m_pBlockVector(pBlockVector),
    m_CurrentFrameIndex(currentFrameIndex),
    m_BytesMoved(0),
    m_AllocationsMoved(0),
    m_Allocations(VmaStlAllocator<AllocationInfo>(hAllocator->GetAllocationCallbacks())),
    m_Blocks(VmaStlAllocator<BlockInfo*>(hAllocator->GetAllocationCallbacks()))
{
}

VmaDefragmentator::~VmaDefragmentator()
{
    for(size_t i = m_Blocks.size(); i--; )
    {
        vma_delete(m_hAllocator, m_Blocks[i]);
    }
}

void VmaDefragmentator::AddAllocation(VmaAllocation hAlloc, VkBool32* pChanged)
{
    AllocationInfo allocInfo;
    allocInfo.m_hAllocation = hAlloc;
    allocInfo.m_pChanged = pChanged;
    m_Allocations.push_back(allocInfo);
}

VkResult VmaDefragmentator::BlockInfo::EnsureMapping(VmaAllocator hAllocator, void** ppMappedData)
{
    // It has already been mapped for defragmentation.
    if(m_pMappedDataForDefragmentation)
    {
        *ppMappedData = m_pMappedDataForDefragmentation;
        return VK_SUCCESS;
    }
            
    // It is originally mapped.
    if(m_pBlock->GetMappedData())
    {
        *ppMappedData = m_pBlock->GetMappedData();
        return VK_SUCCESS;
    }
            
    // Map on first usage.
    VkResult res = m_pBlock->Map(hAllocator, 1, &m_pMappedDataForDefragmentation);
    *ppMappedData = m_pMappedDataForDefragmentation;
    return res;
}

void VmaDefragmentator::BlockInfo::Unmap(VmaAllocator hAllocator)
{
    if(m_pMappedDataForDefragmentation != VMA_NULL)
    {
        m_pBlock->Unmap(hAllocator, 1);
    }
}

VkResult VmaDefragmentator::DefragmentRound(
    VkDeviceSize maxBytesToMove,
    uint32_t maxAllocationsToMove)
{
    if(m_Blocks.empty())
    {
        return VK_SUCCESS;
    }

    size_t srcBlockIndex = m_Blocks.size() - 1;
    size_t srcAllocIndex = SIZE_MAX;
    for(;;)
    {
        // 1. Find next allocation to move.
        // 1.1. Start from last to first m_Blocks - they are sorted from most "destination" to most "source".
        // 1.2. Then start from last to first m_Allocations - they are sorted from largest to smallest.
        while(srcAllocIndex >= m_Blocks[srcBlockIndex]->m_Allocations.size())
        {
            if(m_Blocks[srcBlockIndex]->m_Allocations.empty())
            {
                // Finished: no more allocations to process.
                if(srcBlockIndex == 0)
                {
                    return VK_SUCCESS;
                }
                else
                {
                    --srcBlockIndex;
                    srcAllocIndex = SIZE_MAX;
                }
            }
            else
            {
                srcAllocIndex = m_Blocks[srcBlockIndex]->m_Allocations.size() - 1;
            }
        }
        
        BlockInfo* pSrcBlockInfo = m_Blocks[srcBlockIndex];
        AllocationInfo& allocInfo = pSrcBlockInfo->m_Allocations[srcAllocIndex];

        const VkDeviceSize size = allocInfo.m_hAllocation->GetSize();
        const VkDeviceSize srcOffset = allocInfo.m_hAllocation->GetOffset();
        const VkDeviceSize alignment = allocInfo.m_hAllocation->GetAlignment();
        const VmaSuballocationType suballocType = allocInfo.m_hAllocation->GetSuballocationType();

        // 2. Try to find new place for this allocation in preceding or current block.
        for(size_t dstBlockIndex = 0; dstBlockIndex <= srcBlockIndex; ++dstBlockIndex)
        {
            BlockInfo* pDstBlockInfo = m_Blocks[dstBlockIndex];
            VmaAllocationRequest dstAllocRequest;
            if(pDstBlockInfo->m_pBlock->m_Metadata.CreateAllocationRequest(
                m_CurrentFrameIndex,
                m_pBlockVector->GetFrameInUseCount(),
                m_pBlockVector->GetBufferImageGranularity(),
                size,
                alignment,
                suballocType,
                false, // canMakeOtherLost
                &dstAllocRequest) &&
            MoveMakesSense(
                dstBlockIndex, dstAllocRequest.offset, srcBlockIndex, srcOffset))
            {
                VMA_ASSERT(dstAllocRequest.itemsToMakeLostCount == 0);

                // Reached limit on number of allocations or bytes to move.
                if((m_AllocationsMoved + 1 > maxAllocationsToMove) ||
                    (m_BytesMoved + size > maxBytesToMove))
                {
                    return VK_INCOMPLETE;
                }

                void* pDstMappedData = VMA_NULL;
                VkResult res = pDstBlockInfo->EnsureMapping(m_hAllocator, &pDstMappedData);
                if(res != VK_SUCCESS)
                {
                    return res;
                }

                void* pSrcMappedData = VMA_NULL;
                res = pSrcBlockInfo->EnsureMapping(m_hAllocator, &pSrcMappedData);
                if(res != VK_SUCCESS)
                {
                    return res;
                }
                
                // THE PLACE WHERE ACTUAL DATA COPY HAPPENS.
                memcpy(
                    reinterpret_cast<char*>(pDstMappedData) + dstAllocRequest.offset,
                    reinterpret_cast<char*>(pSrcMappedData) + srcOffset,
                    static_cast<size_t>(size));
                
                pDstBlockInfo->m_pBlock->m_Metadata.Alloc(dstAllocRequest, suballocType, size, allocInfo.m_hAllocation);
                pSrcBlockInfo->m_pBlock->m_Metadata.FreeAtOffset(srcOffset);
                
                allocInfo.m_hAllocation->ChangeBlockAllocation(m_hAllocator, pDstBlockInfo->m_pBlock, dstAllocRequest.offset);

                if(allocInfo.m_pChanged != VMA_NULL)
                {
                    *allocInfo.m_pChanged = VK_TRUE;
                }

                ++m_AllocationsMoved;
                m_BytesMoved += size;

                VmaVectorRemove(pSrcBlockInfo->m_Allocations, srcAllocIndex);

                break;
            }
        }

        // If not processed, this allocInfo remains in pBlockInfo->m_Allocations for next round.

        if(srcAllocIndex > 0)
        {
            --srcAllocIndex;
        }
        else
        {
            if(srcBlockIndex > 0)
            {
                --srcBlockIndex;
                srcAllocIndex = SIZE_MAX;
            }
            else
            {
                return VK_SUCCESS;
            }
        }
    }
}

VkResult VmaDefragmentator::Defragment(
    VkDeviceSize maxBytesToMove,
    uint32_t maxAllocationsToMove)
{
    if(m_Allocations.empty())
    {
        return VK_SUCCESS;
    }

    // Create block info for each block.
    const size_t blockCount = m_pBlockVector->m_Blocks.size();
    for(size_t blockIndex = 0; blockIndex < blockCount; ++blockIndex)
    {
        BlockInfo* pBlockInfo = vma_new(m_hAllocator, BlockInfo)(m_hAllocator->GetAllocationCallbacks());
        pBlockInfo->m_pBlock = m_pBlockVector->m_Blocks[blockIndex];
        m_Blocks.push_back(pBlockInfo);
    }

    // Sort them by m_pBlock pointer value.
    VMA_SORT(m_Blocks.begin(), m_Blocks.end(), BlockPointerLess());

    // Move allocation infos from m_Allocations to appropriate m_Blocks[memTypeIndex].m_Allocations.
    for(size_t blockIndex = 0, allocCount = m_Allocations.size(); blockIndex < allocCount; ++blockIndex)
    {
        AllocationInfo& allocInfo = m_Allocations[blockIndex];
        // Now as we are inside VmaBlockVector::m_Mutex, we can make final check if this allocation was not lost.
        if(allocInfo.m_hAllocation->GetLastUseFrameIndex() != VMA_FRAME_INDEX_LOST)
        {
            VmaDeviceMemoryBlock* pBlock = allocInfo.m_hAllocation->GetBlock();
            BlockInfoVector::iterator it = VmaBinaryFindFirstNotLess(m_Blocks.begin(), m_Blocks.end(), pBlock, BlockPointerLess());
            if(it != m_Blocks.end() && (*it)->m_pBlock == pBlock)
            {
                (*it)->m_Allocations.push_back(allocInfo);
            }
            else
            {
                VMA_ASSERT(0);
            }
        }
    }
    m_Allocations.clear();

    for(size_t blockIndex = 0; blockIndex < blockCount; ++blockIndex)
    {
        BlockInfo* pBlockInfo = m_Blocks[blockIndex];
        pBlockInfo->CalcHasNonMovableAllocations();
        pBlockInfo->SortAllocationsBySizeDescecnding();
    }

    // Sort m_Blocks this time by the main criterium, from most "destination" to most "source" blocks.
    VMA_SORT(m_Blocks.begin(), m_Blocks.end(), BlockInfoCompareMoveDestination());

    // Execute defragmentation rounds (the main part).
    VkResult result = VK_SUCCESS;
    for(size_t round = 0; (round < 2) && (result == VK_SUCCESS); ++round)
    {
        result = DefragmentRound(maxBytesToMove, maxAllocationsToMove);
    }

    // Unmap blocks that were mapped for defragmentation.
    for(size_t blockIndex = 0; blockIndex < blockCount; ++blockIndex)
    {
        m_Blocks[blockIndex]->Unmap(m_hAllocator);
    }

    return result;
}

bool VmaDefragmentator::MoveMakesSense(
        size_t dstBlockIndex, VkDeviceSize dstOffset,
        size_t srcBlockIndex, VkDeviceSize srcOffset)
{
    if(dstBlockIndex < srcBlockIndex)
    {
        return true;
    }
    if(dstBlockIndex > srcBlockIndex)
    {
        return false;
    }
    if(dstOffset < srcOffset)
    {
        return true;
    }
    return false;
}

////////////////////////////////////////////////////////////////////////////////
// VmaAllocator_T

VmaAllocator_T::VmaAllocator_T(const VmaAllocatorCreateInfo* pCreateInfo) :
    m_UseMutex((pCreateInfo->flags & VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT) == 0),
    m_UseKhrDedicatedAllocation((pCreateInfo->flags & VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT) != 0),
    m_hDevice(pCreateInfo->device),
    m_AllocationCallbacksSpecified(pCreateInfo->pAllocationCallbacks != VMA_NULL),
    m_AllocationCallbacks(pCreateInfo->pAllocationCallbacks ?
        *pCreateInfo->pAllocationCallbacks : VmaEmptyAllocationCallbacks),
    m_PreferredLargeHeapBlockSize(0),
    m_PhysicalDevice(pCreateInfo->physicalDevice),
    m_CurrentFrameIndex(0),
    m_Pools(VmaStlAllocator<VmaPool>(GetAllocationCallbacks()))
{
    VMA_ASSERT(pCreateInfo->physicalDevice && pCreateInfo->device);    

    memset(&m_DeviceMemoryCallbacks, 0 ,sizeof(m_DeviceMemoryCallbacks));
    memset(&m_MemProps, 0, sizeof(m_MemProps));
    memset(&m_PhysicalDeviceProperties, 0, sizeof(m_PhysicalDeviceProperties));
        
    memset(&m_pBlockVectors, 0, sizeof(m_pBlockVectors));
    memset(&m_pDedicatedAllocations, 0, sizeof(m_pDedicatedAllocations));

    for(uint32_t i = 0; i < VK_MAX_MEMORY_HEAPS; ++i)
    {
        m_HeapSizeLimit[i] = VK_WHOLE_SIZE;
    }

    if(pCreateInfo->pDeviceMemoryCallbacks != VMA_NULL)
    {
        m_DeviceMemoryCallbacks.pfnAllocate = pCreateInfo->pDeviceMemoryCallbacks->pfnAllocate;
        m_DeviceMemoryCallbacks.pfnFree = pCreateInfo->pDeviceMemoryCallbacks->pfnFree;
    }

    ImportVulkanFunctions(pCreateInfo->pVulkanFunctions);

    (*m_VulkanFunctions.vkGetPhysicalDeviceProperties)(m_PhysicalDevice, &m_PhysicalDeviceProperties);
    (*m_VulkanFunctions.vkGetPhysicalDeviceMemoryProperties)(m_PhysicalDevice, &m_MemProps);

    m_PreferredLargeHeapBlockSize = (pCreateInfo->preferredLargeHeapBlockSize != 0) ?
        pCreateInfo->preferredLargeHeapBlockSize : static_cast<VkDeviceSize>(VMA_DEFAULT_LARGE_HEAP_BLOCK_SIZE);

    if(pCreateInfo->pHeapSizeLimit != VMA_NULL)
    {
        for(uint32_t heapIndex = 0; heapIndex < GetMemoryHeapCount(); ++heapIndex)
        {
            const VkDeviceSize limit = pCreateInfo->pHeapSizeLimit[heapIndex];
            if(limit != VK_WHOLE_SIZE)
            {
                m_HeapSizeLimit[heapIndex] = limit;
                if(limit < m_MemProps.memoryHeaps[heapIndex].size)
                {
                    m_MemProps.memoryHeaps[heapIndex].size = limit;
                }
            }
        }
    }

    for(uint32_t memTypeIndex = 0; memTypeIndex < GetMemoryTypeCount(); ++memTypeIndex)
    {
        const VkDeviceSize preferredBlockSize = CalcPreferredBlockSize(memTypeIndex);

        m_pBlockVectors[memTypeIndex] = vma_new(this, VmaBlockVector)(
            this,
            memTypeIndex,
            preferredBlockSize,
            0,
            SIZE_MAX,
            GetBufferImageGranularity(),
            pCreateInfo->frameInUseCount,
            false); // isCustomPool
        // No need to call m_pBlockVectors[memTypeIndex][blockVectorTypeIndex]->CreateMinBlocks here,
        // becase minBlockCount is 0.
        m_pDedicatedAllocations[memTypeIndex] = vma_new(this, AllocationVectorType)(VmaStlAllocator<VmaAllocation>(GetAllocationCallbacks()));
    }
}

VmaAllocator_T::~VmaAllocator_T()
{
    VMA_ASSERT(m_Pools.empty());

    for(size_t i = GetMemoryTypeCount(); i--; )
    {
        vma_delete(this, m_pDedicatedAllocations[i]);
        vma_delete(this, m_pBlockVectors[i]);
    }
}

void VmaAllocator_T::ImportVulkanFunctions(const VmaVulkanFunctions* pVulkanFunctions)
{
#if VMA_STATIC_VULKAN_FUNCTIONS == 1
    m_VulkanFunctions.vkGetPhysicalDeviceProperties = &vkGetPhysicalDeviceProperties;
    m_VulkanFunctions.vkGetPhysicalDeviceMemoryProperties = &vkGetPhysicalDeviceMemoryProperties;
    m_VulkanFunctions.vkAllocateMemory = &vkAllocateMemory;
    m_VulkanFunctions.vkFreeMemory = &vkFreeMemory;
    m_VulkanFunctions.vkMapMemory = &vkMapMemory;
    m_VulkanFunctions.vkUnmapMemory = &vkUnmapMemory;
    m_VulkanFunctions.vkBindBufferMemory = &vkBindBufferMemory;
    m_VulkanFunctions.vkBindImageMemory = &vkBindImageMemory;
    m_VulkanFunctions.vkGetBufferMemoryRequirements = &vkGetBufferMemoryRequirements;
    m_VulkanFunctions.vkGetImageMemoryRequirements = &vkGetImageMemoryRequirements;
    m_VulkanFunctions.vkCreateBuffer = &vkCreateBuffer;
    m_VulkanFunctions.vkDestroyBuffer = &vkDestroyBuffer;
    m_VulkanFunctions.vkCreateImage = &vkCreateImage;
    m_VulkanFunctions.vkDestroyImage = &vkDestroyImage;
    if(m_UseKhrDedicatedAllocation)
    {
        m_VulkanFunctions.vkGetBufferMemoryRequirements2KHR =
            (PFN_vkGetBufferMemoryRequirements2KHR)vkGetDeviceProcAddr(m_hDevice, "vkGetBufferMemoryRequirements2KHR");
        m_VulkanFunctions.vkGetImageMemoryRequirements2KHR =
            (PFN_vkGetImageMemoryRequirements2KHR)vkGetDeviceProcAddr(m_hDevice, "vkGetImageMemoryRequirements2KHR");
    }
#endif // #if VMA_STATIC_VULKAN_FUNCTIONS == 1

#define VMA_COPY_IF_NOT_NULL(funcName) \
    if(pVulkanFunctions->funcName != VMA_NULL) m_VulkanFunctions.funcName = pVulkanFunctions->funcName;

    if(pVulkanFunctions != VMA_NULL)
    {
        VMA_COPY_IF_NOT_NULL(vkGetPhysicalDeviceProperties);
        VMA_COPY_IF_NOT_NULL(vkGetPhysicalDeviceMemoryProperties);
        VMA_COPY_IF_NOT_NULL(vkAllocateMemory);
        VMA_COPY_IF_NOT_NULL(vkFreeMemory);
        VMA_COPY_IF_NOT_NULL(vkMapMemory);
        VMA_COPY_IF_NOT_NULL(vkUnmapMemory);
        VMA_COPY_IF_NOT_NULL(vkBindBufferMemory);
        VMA_COPY_IF_NOT_NULL(vkBindImageMemory);
        VMA_COPY_IF_NOT_NULL(vkGetBufferMemoryRequirements);
        VMA_COPY_IF_NOT_NULL(vkGetImageMemoryRequirements);
        VMA_COPY_IF_NOT_NULL(vkCreateBuffer);
        VMA_COPY_IF_NOT_NULL(vkDestroyBuffer);
        VMA_COPY_IF_NOT_NULL(vkCreateImage);
        VMA_COPY_IF_NOT_NULL(vkDestroyImage);
        VMA_COPY_IF_NOT_NULL(vkGetBufferMemoryRequirements2KHR);
        VMA_COPY_IF_NOT_NULL(vkGetImageMemoryRequirements2KHR);
    }

#undef VMA_COPY_IF_NOT_NULL

    // If these asserts are hit, you must either #define VMA_STATIC_VULKAN_FUNCTIONS 1
    // or pass valid pointers as VmaAllocatorCreateInfo::pVulkanFunctions.
    VMA_ASSERT(m_VulkanFunctions.vkGetPhysicalDeviceProperties != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkGetPhysicalDeviceMemoryProperties != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkAllocateMemory != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkFreeMemory != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkMapMemory != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkUnmapMemory != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkBindBufferMemory != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkBindImageMemory != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkGetBufferMemoryRequirements != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkGetImageMemoryRequirements != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkCreateBuffer != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkDestroyBuffer != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkCreateImage != VMA_NULL);
    VMA_ASSERT(m_VulkanFunctions.vkDestroyImage != VMA_NULL);
    if(m_UseKhrDedicatedAllocation)
    {
        VMA_ASSERT(m_VulkanFunctions.vkGetBufferMemoryRequirements2KHR != VMA_NULL);
        VMA_ASSERT(m_VulkanFunctions.vkGetImageMemoryRequirements2KHR != VMA_NULL);
    }
}

VkDeviceSize VmaAllocator_T::CalcPreferredBlockSize(uint32_t memTypeIndex)
{
    const uint32_t heapIndex = MemoryTypeIndexToHeapIndex(memTypeIndex);
    const VkDeviceSize heapSize = m_MemProps.memoryHeaps[heapIndex].size;
    const bool isSmallHeap = heapSize <= VMA_SMALL_HEAP_MAX_SIZE;
    return isSmallHeap ? (heapSize / 8) : m_PreferredLargeHeapBlockSize;
}

VkResult VmaAllocator_T::AllocateMemoryOfType(
    const VkMemoryRequirements& vkMemReq,
    bool dedicatedAllocation,
    VkBuffer dedicatedBuffer,
    VkImage dedicatedImage,
    const VmaAllocationCreateInfo& createInfo,
    uint32_t memTypeIndex,
    VmaSuballocationType suballocType,
    VmaAllocation* pAllocation)
{
    VMA_ASSERT(pAllocation != VMA_NULL);
    VMA_DEBUG_LOG("  AllocateMemory: MemoryTypeIndex=%u, Size=%llu", memTypeIndex, vkMemReq.size);

    VmaAllocationCreateInfo finalCreateInfo = createInfo;

    // If memory type is not HOST_VISIBLE, disable MAPPED.
    if((finalCreateInfo.flags & VMA_ALLOCATION_CREATE_MAPPED_BIT) != 0 &&
        (m_MemProps.memoryTypes[memTypeIndex].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) == 0)
    {
        finalCreateInfo.flags &= ~VMA_ALLOCATION_CREATE_MAPPED_BIT;
    }

    VmaBlockVector* const blockVector = m_pBlockVectors[memTypeIndex];
    VMA_ASSERT(blockVector);

    const VkDeviceSize preferredBlockSize = blockVector->GetPreferredBlockSize();
    bool preferDedicatedMemory =
        VMA_DEBUG_ALWAYS_DEDICATED_MEMORY ||
        dedicatedAllocation ||
        // Heuristics: Allocate dedicated memory if requested size if greater than half of preferred block size.
        vkMemReq.size > preferredBlockSize / 2;

    if(preferDedicatedMemory &&
        (finalCreateInfo.flags & VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT) == 0 &&
        finalCreateInfo.pool == VK_NULL_HANDLE)
    {
        finalCreateInfo.flags |= VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
    }

    if((finalCreateInfo.flags & VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT) != 0)
    {
        if((finalCreateInfo.flags & VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT) != 0)
        {
            return VK_ERROR_OUT_OF_DEVICE_MEMORY;
        }
        else
        {
            return AllocateDedicatedMemory(
                vkMemReq.size,
                suballocType,
                memTypeIndex,
                (finalCreateInfo.flags & VMA_ALLOCATION_CREATE_MAPPED_BIT) != 0,
                (finalCreateInfo.flags & VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT) != 0,
                finalCreateInfo.pUserData,
                dedicatedBuffer,
                dedicatedImage,
                pAllocation);
        }
    }
    else
    {
        VkResult res = blockVector->Allocate(
            VK_NULL_HANDLE, // hCurrentPool
            m_CurrentFrameIndex.load(),
            vkMemReq,
            finalCreateInfo,
            suballocType,
            pAllocation);
        if(res == VK_SUCCESS)
        {
            return res;
        }

        // 5. Try dedicated memory.
        if((finalCreateInfo.flags & VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT) != 0)
        {
            return VK_ERROR_OUT_OF_DEVICE_MEMORY;
        }
        else
        {
            res = AllocateDedicatedMemory(
                vkMemReq.size,
                suballocType,
                memTypeIndex,
                (finalCreateInfo.flags & VMA_ALLOCATION_CREATE_MAPPED_BIT) != 0,
                (finalCreateInfo.flags & VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT) != 0,
                finalCreateInfo.pUserData,
                dedicatedBuffer,
                dedicatedImage,
                pAllocation);
            if(res == VK_SUCCESS)
            {
                // Succeeded: AllocateDedicatedMemory function already filld pMemory, nothing more to do here.
                VMA_DEBUG_LOG("    Allocated as DedicatedMemory");
                return VK_SUCCESS;
            }
            else
            {
                // Everything failed: Return error code.
                VMA_DEBUG_LOG("    vkAllocateMemory FAILED");
                return res;
            }
        }
    }
}

VkResult VmaAllocator_T::AllocateDedicatedMemory(
    VkDeviceSize size,
    VmaSuballocationType suballocType,
    uint32_t memTypeIndex,
    bool map,
    bool isUserDataString,
    void* pUserData,
    VkBuffer dedicatedBuffer,
    VkImage dedicatedImage,
    VmaAllocation* pAllocation)
{
    VMA_ASSERT(pAllocation);

    VkMemoryAllocateInfo allocInfo = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO };
    allocInfo.memoryTypeIndex = memTypeIndex;
    allocInfo.allocationSize = size;

    VkMemoryDedicatedAllocateInfoKHR dedicatedAllocInfo = { VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO_KHR };
    if(m_UseKhrDedicatedAllocation)
    {
        if(dedicatedBuffer != VK_NULL_HANDLE)
        {
            VMA_ASSERT(dedicatedImage == VK_NULL_HANDLE);
            dedicatedAllocInfo.buffer = dedicatedBuffer;
            allocInfo.pNext = &dedicatedAllocInfo;
        }
        else if(dedicatedImage != VK_NULL_HANDLE)
        {
            dedicatedAllocInfo.image = dedicatedImage;
            allocInfo.pNext = &dedicatedAllocInfo;
        }
    }

    // Allocate VkDeviceMemory.
    VkDeviceMemory hMemory = VK_NULL_HANDLE;
    VkResult res = AllocateVulkanMemory(&allocInfo, &hMemory);
    if(res < 0)
    {
        VMA_DEBUG_LOG("    vkAllocateMemory FAILED");
        return res;
    }

    void* pMappedData = VMA_NULL;
    if(map)
    {
        res = (*m_VulkanFunctions.vkMapMemory)(
            m_hDevice,
            hMemory,
            0,
            VK_WHOLE_SIZE,
            0,
            &pMappedData);
        if(res < 0)
        {
            VMA_DEBUG_LOG("    vkMapMemory FAILED");
            FreeVulkanMemory(memTypeIndex, size, hMemory);
            return res;
        }
    }

    *pAllocation = vma_new(this, VmaAllocation_T)(m_CurrentFrameIndex.load(), isUserDataString);
    (*pAllocation)->InitDedicatedAllocation(memTypeIndex, hMemory, suballocType, pMappedData, size);
    (*pAllocation)->SetUserData(this, pUserData);

    // Register it in m_pDedicatedAllocations.
    {
        VmaMutexLock lock(m_DedicatedAllocationsMutex[memTypeIndex], m_UseMutex);
        AllocationVectorType* pDedicatedAllocations = m_pDedicatedAllocations[memTypeIndex];
        VMA_ASSERT(pDedicatedAllocations);
        VmaVectorInsertSorted<VmaPointerLess>(*pDedicatedAllocations, *pAllocation);
    }

    VMA_DEBUG_LOG("    Allocated DedicatedMemory MemoryTypeIndex=#%u", memTypeIndex);

    return VK_SUCCESS;
}

void VmaAllocator_T::GetBufferMemoryRequirements(
    VkBuffer hBuffer,
    VkMemoryRequirements& memReq,
    bool& requiresDedicatedAllocation,
    bool& prefersDedicatedAllocation) const
{
    if(m_UseKhrDedicatedAllocation)
    {
        VkBufferMemoryRequirementsInfo2KHR memReqInfo = { VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2_KHR };
        memReqInfo.buffer = hBuffer;

        VkMemoryDedicatedRequirementsKHR memDedicatedReq = { VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS_KHR };

        VkMemoryRequirements2KHR memReq2 = { VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2_KHR };
        memReq2.pNext = &memDedicatedReq;

        (*m_VulkanFunctions.vkGetBufferMemoryRequirements2KHR)(m_hDevice, &memReqInfo, &memReq2);

        memReq = memReq2.memoryRequirements;
        requiresDedicatedAllocation = (memDedicatedReq.requiresDedicatedAllocation != VK_FALSE);
        prefersDedicatedAllocation  = (memDedicatedReq.prefersDedicatedAllocation  != VK_FALSE);
    }
    else
    {
        (*m_VulkanFunctions.vkGetBufferMemoryRequirements)(m_hDevice, hBuffer, &memReq);
        requiresDedicatedAllocation = false;
        prefersDedicatedAllocation  = false;
    }
}

void VmaAllocator_T::GetImageMemoryRequirements(
    VkImage hImage,
    VkMemoryRequirements& memReq,
    bool& requiresDedicatedAllocation,
    bool& prefersDedicatedAllocation) const
{
    if(m_UseKhrDedicatedAllocation)
    {
        VkImageMemoryRequirementsInfo2KHR memReqInfo = { VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2_KHR };
        memReqInfo.image = hImage;

        VkMemoryDedicatedRequirementsKHR memDedicatedReq = { VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS_KHR };

        VkMemoryRequirements2KHR memReq2 = { VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2_KHR };
        memReq2.pNext = &memDedicatedReq;

        (*m_VulkanFunctions.vkGetImageMemoryRequirements2KHR)(m_hDevice, &memReqInfo, &memReq2);

        memReq = memReq2.memoryRequirements;
        requiresDedicatedAllocation = (memDedicatedReq.requiresDedicatedAllocation != VK_FALSE);
        prefersDedicatedAllocation  = (memDedicatedReq.prefersDedicatedAllocation  != VK_FALSE);
    }
    else
    {
        (*m_VulkanFunctions.vkGetImageMemoryRequirements)(m_hDevice, hImage, &memReq);
        requiresDedicatedAllocation = false;
        prefersDedicatedAllocation  = false;
    }
}

VkResult VmaAllocator_T::AllocateMemory(
    const VkMemoryRequirements& vkMemReq,
    bool requiresDedicatedAllocation,
    bool prefersDedicatedAllocation,
    VkBuffer dedicatedBuffer,
    VkImage dedicatedImage,
    const VmaAllocationCreateInfo& createInfo,
    VmaSuballocationType suballocType,
    VmaAllocation* pAllocation)
{
    if((createInfo.flags & VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT) != 0 &&
        (createInfo.flags & VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT) != 0)
    {
        VMA_ASSERT(0 && "Specifying VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT together with VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT makes no sense.");
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    if((createInfo.flags & VMA_ALLOCATION_CREATE_MAPPED_BIT) != 0 &&
        (createInfo.flags & VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT) != 0)
    {
        VMA_ASSERT(0 && "Specifying VMA_ALLOCATION_CREATE_MAPPED_BIT together with VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT is invalid.");
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }
    if(requiresDedicatedAllocation)
    {
        if((createInfo.flags & VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT) != 0)
        {
            VMA_ASSERT(0 && "VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT specified while dedicated allocation is required.");
            return VK_ERROR_OUT_OF_DEVICE_MEMORY;
        }
        if(createInfo.pool != VK_NULL_HANDLE)
        {
            VMA_ASSERT(0 && "Pool specified while dedicated allocation is required.");
            return VK_ERROR_OUT_OF_DEVICE_MEMORY;
        }
    }
    if((createInfo.pool != VK_NULL_HANDLE) &&
        ((createInfo.flags & (VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT)) != 0))
    {
        VMA_ASSERT(0 && "Specifying VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT when pool != null is invalid.");
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }

    if(createInfo.pool != VK_NULL_HANDLE)
    {
        return createInfo.pool->m_BlockVector.Allocate(
            createInfo.pool,
            m_CurrentFrameIndex.load(),
            vkMemReq,
            createInfo,
            suballocType,
            pAllocation);
    }
    else
    {
        // Bit mask of memory Vulkan types acceptable for this allocation.
        uint32_t memoryTypeBits = vkMemReq.memoryTypeBits;
        uint32_t memTypeIndex = UINT32_MAX;
        VkResult res = vmaFindMemoryTypeIndex(this, memoryTypeBits, &createInfo, &memTypeIndex);
        if(res == VK_SUCCESS)
        {
            res = AllocateMemoryOfType(
                vkMemReq,
                requiresDedicatedAllocation || prefersDedicatedAllocation,
                dedicatedBuffer,
                dedicatedImage,
                createInfo,
                memTypeIndex,
                suballocType,
                pAllocation);
            // Succeeded on first try.
            if(res == VK_SUCCESS)
            {
                return res;
            }
            // Allocation from this memory type failed. Try other compatible memory types.
            else
            {
                for(;;)
                {
                    // Remove old memTypeIndex from list of possibilities.
                    memoryTypeBits &= ~(1u << memTypeIndex);
                    // Find alternative memTypeIndex.
                    res = vmaFindMemoryTypeIndex(this, memoryTypeBits, &createInfo, &memTypeIndex);
                    if(res == VK_SUCCESS)
                    {
                        res = AllocateMemoryOfType(
                            vkMemReq,
                            requiresDedicatedAllocation || prefersDedicatedAllocation,
                            dedicatedBuffer,
                            dedicatedImage,
                            createInfo,
                            memTypeIndex,
                            suballocType,
                            pAllocation);
                        // Allocation from this alternative memory type succeeded.
                        if(res == VK_SUCCESS)
                        {
                            return res;
                        }
                        // else: Allocation from this memory type failed. Try next one - next loop iteration.
                    }
                    // No other matching memory type index could be found.
                    else
                    {
                        // Not returning res, which is VK_ERROR_FEATURE_NOT_PRESENT, because we already failed to allocate once.
                        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
                    }
                }
            }
        }
        // Can't find any single memory type maching requirements. res is VK_ERROR_FEATURE_NOT_PRESENT.
        else
            return res;
    }
}

void VmaAllocator_T::FreeMemory(const VmaAllocation allocation)
{
    VMA_ASSERT(allocation);

    if(allocation->CanBecomeLost() == false ||
        allocation->GetLastUseFrameIndex() != VMA_FRAME_INDEX_LOST)
    {
        switch(allocation->GetType())
        {
        case VmaAllocation_T::ALLOCATION_TYPE_BLOCK:
            {
                VmaBlockVector* pBlockVector = VMA_NULL;
                VmaPool hPool = allocation->GetPool();
                if(hPool != VK_NULL_HANDLE)
                {
                    pBlockVector = &hPool->m_BlockVector;
                }
                else
                {
                    const uint32_t memTypeIndex = allocation->GetMemoryTypeIndex();
                    pBlockVector = m_pBlockVectors[memTypeIndex];
                }
                pBlockVector->Free(allocation);
            }
            break;
        case VmaAllocation_T::ALLOCATION_TYPE_DEDICATED:
            FreeDedicatedMemory(allocation);
            break;
        default:
            VMA_ASSERT(0);
        }
    }

    allocation->SetUserData(this, VMA_NULL);
    vma_delete(this, allocation);
}

void VmaAllocator_T::CalculateStats(VmaStats* pStats)
{
    // Initialize.
    InitStatInfo(pStats->total);
    for(size_t i = 0; i < VK_MAX_MEMORY_TYPES; ++i)
        InitStatInfo(pStats->memoryType[i]);
    for(size_t i = 0; i < VK_MAX_MEMORY_HEAPS; ++i)
        InitStatInfo(pStats->memoryHeap[i]);
    
    // Process default pools.
    for(uint32_t memTypeIndex = 0; memTypeIndex < GetMemoryTypeCount(); ++memTypeIndex)
    {
        VmaBlockVector* const pBlockVector = m_pBlockVectors[memTypeIndex];
        VMA_ASSERT(pBlockVector);
        pBlockVector->AddStats(pStats);
    }

    // Process custom pools.
    {
        VmaMutexLock lock(m_PoolsMutex, m_UseMutex);
        for(size_t poolIndex = 0, poolCount = m_Pools.size(); poolIndex < poolCount; ++poolIndex)
        {
            m_Pools[poolIndex]->GetBlockVector().AddStats(pStats);
        }
    }

    // Process dedicated allocations.
    for(uint32_t memTypeIndex = 0; memTypeIndex < GetMemoryTypeCount(); ++memTypeIndex)
    {
        const uint32_t memHeapIndex = MemoryTypeIndexToHeapIndex(memTypeIndex);
        VmaMutexLock dedicatedAllocationsLock(m_DedicatedAllocationsMutex[memTypeIndex], m_UseMutex);
        AllocationVectorType* const pDedicatedAllocVector = m_pDedicatedAllocations[memTypeIndex];
        VMA_ASSERT(pDedicatedAllocVector);
        for(size_t allocIndex = 0, allocCount = pDedicatedAllocVector->size(); allocIndex < allocCount; ++allocIndex)
        {
            VmaStatInfo allocationStatInfo;
            (*pDedicatedAllocVector)[allocIndex]->DedicatedAllocCalcStatsInfo(allocationStatInfo);
            VmaAddStatInfo(pStats->total, allocationStatInfo);
            VmaAddStatInfo(pStats->memoryType[memTypeIndex], allocationStatInfo);
            VmaAddStatInfo(pStats->memoryHeap[memHeapIndex], allocationStatInfo);
        }
    }

    // Postprocess.
    VmaPostprocessCalcStatInfo(pStats->total);
    for(size_t i = 0; i < GetMemoryTypeCount(); ++i)
        VmaPostprocessCalcStatInfo(pStats->memoryType[i]);
    for(size_t i = 0; i < GetMemoryHeapCount(); ++i)
        VmaPostprocessCalcStatInfo(pStats->memoryHeap[i]);
}

static const uint32_t VMA_VENDOR_ID_AMD = 4098;

VkResult VmaAllocator_T::Defragment(
    VmaAllocation* pAllocations,
    size_t allocationCount,
    VkBool32* pAllocationsChanged,
    const VmaDefragmentationInfo* pDefragmentationInfo,
    VmaDefragmentationStats* pDefragmentationStats)
{
    if(pAllocationsChanged != VMA_NULL)
    {
        memset(pAllocationsChanged, 0, sizeof(*pAllocationsChanged));
    }
    if(pDefragmentationStats != VMA_NULL)
    {
        memset(pDefragmentationStats, 0, sizeof(*pDefragmentationStats));
    }

    const uint32_t currentFrameIndex = m_CurrentFrameIndex.load();

    VmaMutexLock poolsLock(m_PoolsMutex, m_UseMutex);

    const size_t poolCount = m_Pools.size();

    // Dispatch pAllocations among defragmentators. Create them in BlockVectors when necessary.
    for(size_t allocIndex = 0; allocIndex < allocationCount; ++allocIndex)
    {
        VmaAllocation hAlloc = pAllocations[allocIndex];
        VMA_ASSERT(hAlloc);
        const uint32_t memTypeIndex = hAlloc->GetMemoryTypeIndex();
        // DedicatedAlloc cannot be defragmented.
        if((hAlloc->GetType() == VmaAllocation_T::ALLOCATION_TYPE_BLOCK) &&
            // Only HOST_VISIBLE memory types can be defragmented.
            ((m_MemProps.memoryTypes[memTypeIndex].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0) &&
            // Lost allocation cannot be defragmented.
            (hAlloc->GetLastUseFrameIndex() != VMA_FRAME_INDEX_LOST))
        {
            VmaBlockVector* pAllocBlockVector = VMA_NULL;

            const VmaPool hAllocPool = hAlloc->GetPool();
            // This allocation belongs to custom pool.
            if(hAllocPool != VK_NULL_HANDLE)
            {
                pAllocBlockVector = &hAllocPool->GetBlockVector();
            }
            // This allocation belongs to general pool.
            else
            {
                pAllocBlockVector = m_pBlockVectors[memTypeIndex];
            }

            VmaDefragmentator* const pDefragmentator = pAllocBlockVector->EnsureDefragmentator(this, currentFrameIndex);

            VkBool32* const pChanged = (pAllocationsChanged != VMA_NULL) ?
                &pAllocationsChanged[allocIndex] : VMA_NULL;
            pDefragmentator->AddAllocation(hAlloc, pChanged);
        }
    }

    VkResult result = VK_SUCCESS;

    // ======== Main processing.

    VkDeviceSize maxBytesToMove = SIZE_MAX;
    uint32_t maxAllocationsToMove = UINT32_MAX;
    if(pDefragmentationInfo != VMA_NULL)
    {
        maxBytesToMove = pDefragmentationInfo->maxBytesToMove;
        maxAllocationsToMove = pDefragmentationInfo->maxAllocationsToMove;
    }

    // Process standard memory.
    for(uint32_t memTypeIndex = 0;
        (memTypeIndex < GetMemoryTypeCount()) && (result == VK_SUCCESS);
        ++memTypeIndex)
    {
        // Only HOST_VISIBLE memory types can be defragmented.
        if((m_MemProps.memoryTypes[memTypeIndex].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0)
        {
            result = m_pBlockVectors[memTypeIndex]->Defragment(
                pDefragmentationStats,
                maxBytesToMove,
                maxAllocationsToMove);
        }
    }

    // Process custom pools.
    for(size_t poolIndex = 0; (poolIndex < poolCount) && (result == VK_SUCCESS); ++poolIndex)
    {
        result = m_Pools[poolIndex]->GetBlockVector().Defragment(
            pDefragmentationStats,
            maxBytesToMove,
            maxAllocationsToMove);
    }

    // ========  Destroy defragmentators.

    // Process custom pools.
    for(size_t poolIndex = poolCount; poolIndex--; )
    {
        m_Pools[poolIndex]->GetBlockVector().DestroyDefragmentator();
    }

    // Process standard memory.
    for(uint32_t memTypeIndex = GetMemoryTypeCount(); memTypeIndex--; )
    {
        if((m_MemProps.memoryTypes[memTypeIndex].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0)
        {
            m_pBlockVectors[memTypeIndex]->DestroyDefragmentator();
        }
    }

    return result;
}

void VmaAllocator_T::GetAllocationInfo(VmaAllocation hAllocation, VmaAllocationInfo* pAllocationInfo)
{
    if(hAllocation->CanBecomeLost())
    {
        /*
        Warning: This is a carefully designed algorithm.
        Do not modify unless you really know what you're doing :)
        */
        uint32_t localCurrFrameIndex = m_CurrentFrameIndex.load();
        uint32_t localLastUseFrameIndex = hAllocation->GetLastUseFrameIndex();
        for(;;)
        {
            if(localLastUseFrameIndex == VMA_FRAME_INDEX_LOST)
            {
                pAllocationInfo->memoryType = UINT32_MAX;
                pAllocationInfo->deviceMemory = VK_NULL_HANDLE;
                pAllocationInfo->offset = 0;
                pAllocationInfo->size = hAllocation->GetSize();
                pAllocationInfo->pMappedData = VMA_NULL;
                pAllocationInfo->pUserData = hAllocation->GetUserData();
                return;
            }
            else if(localLastUseFrameIndex == localCurrFrameIndex)
            {
                pAllocationInfo->memoryType = hAllocation->GetMemoryTypeIndex();
                pAllocationInfo->deviceMemory = hAllocation->GetMemory();
                pAllocationInfo->offset = hAllocation->GetOffset();
                pAllocationInfo->size = hAllocation->GetSize();
                pAllocationInfo->pMappedData = VMA_NULL;
                pAllocationInfo->pUserData = hAllocation->GetUserData();
                return;
            }
            else // Last use time earlier than current time.
            {
                if(hAllocation->CompareExchangeLastUseFrameIndex(localLastUseFrameIndex, localCurrFrameIndex))
                {
                    localLastUseFrameIndex = localCurrFrameIndex;
                }
            }
        }
    }
    else
    {
        pAllocationInfo->memoryType = hAllocation->GetMemoryTypeIndex();
        pAllocationInfo->deviceMemory = hAllocation->GetMemory();
        pAllocationInfo->offset = hAllocation->GetOffset();
        pAllocationInfo->size = hAllocation->GetSize();
        pAllocationInfo->pMappedData = hAllocation->GetMappedData();
        pAllocationInfo->pUserData = hAllocation->GetUserData();
    }
}

bool VmaAllocator_T::TouchAllocation(VmaAllocation hAllocation)
{
    // This is a stripped-down version of VmaAllocator_T::GetAllocationInfo.
    if(hAllocation->CanBecomeLost())
    {
        uint32_t localCurrFrameIndex = m_CurrentFrameIndex.load();
        uint32_t localLastUseFrameIndex = hAllocation->GetLastUseFrameIndex();
        for(;;)
        {
            if(localLastUseFrameIndex == VMA_FRAME_INDEX_LOST)
            {
                return false;
            }
            else if(localLastUseFrameIndex == localCurrFrameIndex)
            {
                return true;
            }
            else // Last use time earlier than current time.
            {
                if(hAllocation->CompareExchangeLastUseFrameIndex(localLastUseFrameIndex, localCurrFrameIndex))
                {
                    localLastUseFrameIndex = localCurrFrameIndex;
                }
            }
        }
    }
    else
    {
        return true;
    }
}

VkResult VmaAllocator_T::CreatePool(const VmaPoolCreateInfo* pCreateInfo, VmaPool* pPool)
{
    VMA_DEBUG_LOG("  CreatePool: MemoryTypeIndex=%u", pCreateInfo->memoryTypeIndex);

    VmaPoolCreateInfo newCreateInfo = *pCreateInfo;

    if(newCreateInfo.maxBlockCount == 0)
    {
        newCreateInfo.maxBlockCount = SIZE_MAX;
    }
    if(newCreateInfo.blockSize == 0)
    {
        newCreateInfo.blockSize = CalcPreferredBlockSize(newCreateInfo.memoryTypeIndex);
    }

    *pPool = vma_new(this, VmaPool_T)(this, newCreateInfo);

    VkResult res = (*pPool)->m_BlockVector.CreateMinBlocks();
    if(res != VK_SUCCESS)
    {
        vma_delete(this, *pPool);
        *pPool = VMA_NULL;
        return res;
    }

    // Add to m_Pools.
    {
        VmaMutexLock lock(m_PoolsMutex, m_UseMutex);
        VmaVectorInsertSorted<VmaPointerLess>(m_Pools, *pPool);
    }

    return VK_SUCCESS;
}

void VmaAllocator_T::DestroyPool(VmaPool pool)
{
    // Remove from m_Pools.
    {
        VmaMutexLock lock(m_PoolsMutex, m_UseMutex);
        bool success = VmaVectorRemoveSorted<VmaPointerLess>(m_Pools, pool);
        VMA_ASSERT(success && "Pool not found in Allocator.");
    }

    vma_delete(this, pool);
}

void VmaAllocator_T::GetPoolStats(VmaPool pool, VmaPoolStats* pPoolStats)
{
    pool->m_BlockVector.GetPoolStats(pPoolStats);
}

void VmaAllocator_T::SetCurrentFrameIndex(uint32_t frameIndex)
{
    m_CurrentFrameIndex.store(frameIndex);
}

void VmaAllocator_T::MakePoolAllocationsLost(
    VmaPool hPool,
    size_t* pLostAllocationCount)
{
    hPool->m_BlockVector.MakePoolAllocationsLost(
        m_CurrentFrameIndex.load(),
        pLostAllocationCount);
}

void VmaAllocator_T::CreateLostAllocation(VmaAllocation* pAllocation)
{
    *pAllocation = vma_new(this, VmaAllocation_T)(VMA_FRAME_INDEX_LOST, false);
    (*pAllocation)->InitLost();
}

VkResult VmaAllocator_T::AllocateVulkanMemory(const VkMemoryAllocateInfo* pAllocateInfo, VkDeviceMemory* pMemory)
{
    const uint32_t heapIndex = MemoryTypeIndexToHeapIndex(pAllocateInfo->memoryTypeIndex);

    VkResult res;
    if(m_HeapSizeLimit[heapIndex] != VK_WHOLE_SIZE)
    {
        VmaMutexLock lock(m_HeapSizeLimitMutex, m_UseMutex);
        if(m_HeapSizeLimit[heapIndex] >= pAllocateInfo->allocationSize)
        {
            res = (*m_VulkanFunctions.vkAllocateMemory)(m_hDevice, pAllocateInfo, GetAllocationCallbacks(), pMemory);
            if(res == VK_SUCCESS)
            {
                m_HeapSizeLimit[heapIndex] -= pAllocateInfo->allocationSize;
            }
        }
        else
        {
            res = VK_ERROR_OUT_OF_DEVICE_MEMORY;
        }
    }
    else
    {
        res = (*m_VulkanFunctions.vkAllocateMemory)(m_hDevice, pAllocateInfo, GetAllocationCallbacks(), pMemory);
    }

    if(res == VK_SUCCESS && m_DeviceMemoryCallbacks.pfnAllocate != VMA_NULL)
    {
        (*m_DeviceMemoryCallbacks.pfnAllocate)(this, pAllocateInfo->memoryTypeIndex, *pMemory, pAllocateInfo->allocationSize);
    }

    return res;
}

void VmaAllocator_T::FreeVulkanMemory(uint32_t memoryType, VkDeviceSize size, VkDeviceMemory hMemory)
{
    if(m_DeviceMemoryCallbacks.pfnFree != VMA_NULL)
    {
        (*m_DeviceMemoryCallbacks.pfnFree)(this, memoryType, hMemory, size);
    }

    (*m_VulkanFunctions.vkFreeMemory)(m_hDevice, hMemory, GetAllocationCallbacks());

    const uint32_t heapIndex = MemoryTypeIndexToHeapIndex(memoryType);
    if(m_HeapSizeLimit[heapIndex] != VK_WHOLE_SIZE)
    {
        VmaMutexLock lock(m_HeapSizeLimitMutex, m_UseMutex);
        m_HeapSizeLimit[heapIndex] += size;
    }
}

VkResult VmaAllocator_T::Map(VmaAllocation hAllocation, void** ppData)
{
    if(hAllocation->CanBecomeLost())
    {
        return VK_ERROR_MEMORY_MAP_FAILED;
    }

    switch(hAllocation->GetType())
    {
    case VmaAllocation_T::ALLOCATION_TYPE_BLOCK:
        {
            VmaDeviceMemoryBlock* const pBlock = hAllocation->GetBlock();
            char *pBytes = VMA_NULL;
            VkResult res = pBlock->Map(this, 1, (void**)&pBytes);
            if(res == VK_SUCCESS)
            {
                *ppData = pBytes + (ptrdiff_t)hAllocation->GetOffset();
                hAllocation->BlockAllocMap();
            }
            return res;
        }
    case VmaAllocation_T::ALLOCATION_TYPE_DEDICATED:
        return hAllocation->DedicatedAllocMap(this, ppData);
    default:
        VMA_ASSERT(0);
        return VK_ERROR_MEMORY_MAP_FAILED;
    }
}

void VmaAllocator_T::Unmap(VmaAllocation hAllocation)
{
    switch(hAllocation->GetType())
    {
    case VmaAllocation_T::ALLOCATION_TYPE_BLOCK:
        {
            VmaDeviceMemoryBlock* const pBlock = hAllocation->GetBlock();
            hAllocation->BlockAllocUnmap();
            pBlock->Unmap(this, 1);
        }
        break;
    case VmaAllocation_T::ALLOCATION_TYPE_DEDICATED:
        hAllocation->DedicatedAllocUnmap(this);
        break;
    default:
        VMA_ASSERT(0);
    }
}

VkResult VmaAllocator_T::BindBufferMemory(VmaAllocation hAllocation, VkBuffer hBuffer)
{
    VkResult res = VK_SUCCESS;
    switch(hAllocation->GetType())
    {
    case VmaAllocation_T::ALLOCATION_TYPE_DEDICATED:
        res = GetVulkanFunctions().vkBindBufferMemory(
            m_hDevice,
            hBuffer,
            hAllocation->GetMemory(),
            0); //memoryOffset
        break;
    case VmaAllocation_T::ALLOCATION_TYPE_BLOCK:
    {
        VmaDeviceMemoryBlock* pBlock = hAllocation->GetBlock();
        VMA_ASSERT(pBlock && "Binding buffer to allocation that doesn't belong to any block. Is the allocation lost?");
        res = pBlock->BindBufferMemory(this, hAllocation, hBuffer);
        break;
    }
    default:
        VMA_ASSERT(0);
    }
    return res;
}

VkResult VmaAllocator_T::BindImageMemory(VmaAllocation hAllocation, VkImage hImage)
{
    VkResult res = VK_SUCCESS;
    switch(hAllocation->GetType())
    {
    case VmaAllocation_T::ALLOCATION_TYPE_DEDICATED:
        res = GetVulkanFunctions().vkBindImageMemory(
            m_hDevice,
            hImage,
            hAllocation->GetMemory(),
            0); //memoryOffset
        break;
    case VmaAllocation_T::ALLOCATION_TYPE_BLOCK:
    {
        VmaDeviceMemoryBlock* pBlock = hAllocation->GetBlock();
        VMA_ASSERT(pBlock && "Binding image to allocation that doesn't belong to any block. Is the allocation lost?");
        res = pBlock->BindImageMemory(this, hAllocation, hImage);
        break;
    }
    default:
        VMA_ASSERT(0);
    }
    return res;
}

void VmaAllocator_T::FreeDedicatedMemory(VmaAllocation allocation)
{
    VMA_ASSERT(allocation && allocation->GetType() == VmaAllocation_T::ALLOCATION_TYPE_DEDICATED);

    const uint32_t memTypeIndex = allocation->GetMemoryTypeIndex();
    {
        VmaMutexLock lock(m_DedicatedAllocationsMutex[memTypeIndex], m_UseMutex);
        AllocationVectorType* const pDedicatedAllocations = m_pDedicatedAllocations[memTypeIndex];
        VMA_ASSERT(pDedicatedAllocations);
        bool success = VmaVectorRemoveSorted<VmaPointerLess>(*pDedicatedAllocations, allocation);
        VMA_ASSERT(success);
    }

    VkDeviceMemory hMemory = allocation->GetMemory();
    
    if(allocation->GetMappedData() != VMA_NULL)
    {
        (*m_VulkanFunctions.vkUnmapMemory)(m_hDevice, hMemory);
    }
    
    FreeVulkanMemory(memTypeIndex, allocation->GetSize(), hMemory);

    VMA_DEBUG_LOG("    Freed DedicatedMemory MemoryTypeIndex=%u", memTypeIndex);
}

#if VMA_STATS_STRING_ENABLED

void VmaAllocator_T::PrintDetailedMap(VmaJsonWriter& json)
{
    bool dedicatedAllocationsStarted = false;
    for(uint32_t memTypeIndex = 0; memTypeIndex < GetMemoryTypeCount(); ++memTypeIndex)
    {
        VmaMutexLock dedicatedAllocationsLock(m_DedicatedAllocationsMutex[memTypeIndex], m_UseMutex);
        AllocationVectorType* const pDedicatedAllocVector = m_pDedicatedAllocations[memTypeIndex];
        VMA_ASSERT(pDedicatedAllocVector);
        if(pDedicatedAllocVector->empty() == false)
        {
            if(dedicatedAllocationsStarted == false)
            {
                dedicatedAllocationsStarted = true;
                json.WriteString("DedicatedAllocations");
                json.BeginObject();
            }

            json.BeginString("Type ");
            json.ContinueString(memTypeIndex);
            json.EndString();
                
            json.BeginArray();

            for(size_t i = 0; i < pDedicatedAllocVector->size(); ++i)
            {
                const VmaAllocation hAlloc = (*pDedicatedAllocVector)[i];
                json.BeginObject(true);
                    
                json.WriteString("Type");
                json.WriteString(VMA_SUBALLOCATION_TYPE_NAMES[hAlloc->GetSuballocationType()]);

                json.WriteString("Size");
                json.WriteNumber(hAlloc->GetSize());

                const void* pUserData = hAlloc->GetUserData();
                if(pUserData != VMA_NULL)
                {
                    json.WriteString("UserData");
                    if(hAlloc->IsUserDataString())
                    {
                        json.WriteString((const char*)pUserData);
                    }
                    else
                    {
                        json.BeginString();
                        json.ContinueString_Pointer(pUserData);
                        json.EndString();
                    }
                }

                json.EndObject();
            }

            json.EndArray();
        }
    }
    if(dedicatedAllocationsStarted)
    {
        json.EndObject();
    }

    {
        bool allocationsStarted = false;
        for(uint32_t memTypeIndex = 0; memTypeIndex < GetMemoryTypeCount(); ++memTypeIndex)
        {
            if(m_pBlockVectors[memTypeIndex]->IsEmpty() == false)
            {
                if(allocationsStarted == false)
                {
                    allocationsStarted = true;
                    json.WriteString("DefaultPools");
                    json.BeginObject();
                }

                json.BeginString("Type ");
                json.ContinueString(memTypeIndex);
                json.EndString();

                m_pBlockVectors[memTypeIndex]->PrintDetailedMap(json);
            }
        }
        if(allocationsStarted)
        {
            json.EndObject();
        }
    }

    {
        VmaMutexLock lock(m_PoolsMutex, m_UseMutex);
        const size_t poolCount = m_Pools.size();
        if(poolCount > 0)
        {
            json.WriteString("Pools");
            json.BeginArray();
            for(size_t poolIndex = 0; poolIndex < poolCount; ++poolIndex)
            {
                m_Pools[poolIndex]->m_BlockVector.PrintDetailedMap(json);
            }
            json.EndArray();
        }
    }
}

#endif // #if VMA_STATS_STRING_ENABLED

static VkResult AllocateMemoryForImage(
    VmaAllocator allocator,
    VkImage image,
    const VmaAllocationCreateInfo* pAllocationCreateInfo,
    VmaSuballocationType suballocType,
    VmaAllocation* pAllocation)
{
    VMA_ASSERT(allocator && (image != VK_NULL_HANDLE) && pAllocationCreateInfo && pAllocation);
    
    VkMemoryRequirements vkMemReq = {};
    bool requiresDedicatedAllocation = false;
    bool prefersDedicatedAllocation  = false;
    allocator->GetImageMemoryRequirements(image, vkMemReq,
        requiresDedicatedAllocation, prefersDedicatedAllocation);

    return allocator->AllocateMemory(
        vkMemReq,
        requiresDedicatedAllocation,
        prefersDedicatedAllocation,
        VK_NULL_HANDLE, // dedicatedBuffer
        image, // dedicatedImage
        *pAllocationCreateInfo,
        suballocType,
        pAllocation);
}

////////////////////////////////////////////////////////////////////////////////
// Public interface

VkResult vmaCreateAllocator(
    const VmaAllocatorCreateInfo* pCreateInfo,
    VmaAllocator* pAllocator)
{
    VMA_ASSERT(pCreateInfo && pAllocator);
    VMA_DEBUG_LOG("vmaCreateAllocator");
    *pAllocator = vma_new(pCreateInfo->pAllocationCallbacks, VmaAllocator_T)(pCreateInfo);
    return VK_SUCCESS;
}

void vmaDestroyAllocator(
    VmaAllocator allocator)
{
    if(allocator != VK_NULL_HANDLE)
    {
        VMA_DEBUG_LOG("vmaDestroyAllocator");
        VkAllocationCallbacks allocationCallbacks = allocator->m_AllocationCallbacks;
        vma_delete(&allocationCallbacks, allocator);
    }
}

void vmaGetPhysicalDeviceProperties(
    VmaAllocator allocator,
    const VkPhysicalDeviceProperties **ppPhysicalDeviceProperties)
{
    VMA_ASSERT(allocator && ppPhysicalDeviceProperties);
    *ppPhysicalDeviceProperties = &allocator->m_PhysicalDeviceProperties;
}

void vmaGetMemoryProperties(
    VmaAllocator allocator,
    const VkPhysicalDeviceMemoryProperties** ppPhysicalDeviceMemoryProperties)
{
    VMA_ASSERT(allocator && ppPhysicalDeviceMemoryProperties);
    *ppPhysicalDeviceMemoryProperties = &allocator->m_MemProps;
}

void vmaGetMemoryTypeProperties(
    VmaAllocator allocator,
    uint32_t memoryTypeIndex,
    VkMemoryPropertyFlags* pFlags)
{
    VMA_ASSERT(allocator && pFlags);
    VMA_ASSERT(memoryTypeIndex < allocator->GetMemoryTypeCount());
    *pFlags = allocator->m_MemProps.memoryTypes[memoryTypeIndex].propertyFlags;
}

void vmaSetCurrentFrameIndex(
    VmaAllocator allocator,
    uint32_t frameIndex)
{
    VMA_ASSERT(allocator);
    VMA_ASSERT(frameIndex != VMA_FRAME_INDEX_LOST);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->SetCurrentFrameIndex(frameIndex);
}

void vmaCalculateStats(
    VmaAllocator allocator,
    VmaStats* pStats)
{
    VMA_ASSERT(allocator && pStats);
    VMA_DEBUG_GLOBAL_MUTEX_LOCK
    allocator->CalculateStats(pStats);
}

#if VMA_STATS_STRING_ENABLED

void vmaBuildStatsString(
    VmaAllocator allocator,
    char** ppStatsString,
    VkBool32 detailedMap)
{
    VMA_ASSERT(allocator && ppStatsString);
    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    VmaStringBuilder sb(allocator);
    {
        VmaJsonWriter json(allocator->GetAllocationCallbacks(), sb);
        json.BeginObject();

        VmaStats stats;
        allocator->CalculateStats(&stats);

        json.WriteString("Total");
        VmaPrintStatInfo(json, stats.total);
    
        for(uint32_t heapIndex = 0; heapIndex < allocator->GetMemoryHeapCount(); ++heapIndex)
        {
            json.BeginString("Heap ");
            json.ContinueString(heapIndex);
            json.EndString();
            json.BeginObject();

            json.WriteString("Size");
            json.WriteNumber(allocator->m_MemProps.memoryHeaps[heapIndex].size);

            json.WriteString("Flags");
            json.BeginArray(true);
            if((allocator->m_MemProps.memoryHeaps[heapIndex].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) != 0)
            {
                json.WriteString("DEVICE_LOCAL");
            }
            json.EndArray();

            if(stats.memoryHeap[heapIndex].blockCount > 0)
            {
                json.WriteString("Stats");
                VmaPrintStatInfo(json, stats.memoryHeap[heapIndex]);
            }

            for(uint32_t typeIndex = 0; typeIndex < allocator->GetMemoryTypeCount(); ++typeIndex)
            {
                if(allocator->MemoryTypeIndexToHeapIndex(typeIndex) == heapIndex)
                {
                    json.BeginString("Type ");
                    json.ContinueString(typeIndex);
                    json.EndString();

                    json.BeginObject();

                    json.WriteString("Flags");
                    json.BeginArray(true);
                    VkMemoryPropertyFlags flags = allocator->m_MemProps.memoryTypes[typeIndex].propertyFlags;
                    if((flags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0)
                    {
                        json.WriteString("DEVICE_LOCAL");
                    }
                    if((flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0)
                    {
                        json.WriteString("HOST_VISIBLE");
                    }
                    if((flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) != 0)
                    {
                        json.WriteString("HOST_COHERENT");
                    }
                    if((flags & VK_MEMORY_PROPERTY_HOST_CACHED_BIT) != 0)
                    {
                        json.WriteString("HOST_CACHED");
                    }
                    if((flags & VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT) != 0)
                    {
                        json.WriteString("LAZILY_ALLOCATED");
                    }
                    json.EndArray();

                    if(stats.memoryType[typeIndex].blockCount > 0)
                    {
                        json.WriteString("Stats");
                        VmaPrintStatInfo(json, stats.memoryType[typeIndex]);
                    }

                    json.EndObject();
                }
            }

            json.EndObject();
        }
        if(detailedMap == VK_TRUE)
        {
            allocator->PrintDetailedMap(json);
        }

        json.EndObject();
    }

    const size_t len = sb.GetLength();
    char* const pChars = vma_new_array(allocator, char, len + 1);
    if(len > 0)
    {
        memcpy(pChars, sb.GetData(), len);
    }
    pChars[len] = '\0';
    *ppStatsString = pChars;
}

void vmaFreeStatsString(
    VmaAllocator allocator,
    char* pStatsString)
{
    if(pStatsString != VMA_NULL)
    {
        VMA_ASSERT(allocator);
        size_t len = strlen(pStatsString);
        vma_delete_array(allocator, pStatsString, len + 1);
    }
}

#endif // #if VMA_STATS_STRING_ENABLED

/*
This function is not protected by any mutex because it just reads immutable data.
*/
VkResult vmaFindMemoryTypeIndex(
    VmaAllocator allocator,
    uint32_t memoryTypeBits,
    const VmaAllocationCreateInfo* pAllocationCreateInfo,
    uint32_t* pMemoryTypeIndex)
{
    VMA_ASSERT(allocator != VK_NULL_HANDLE);
    VMA_ASSERT(pAllocationCreateInfo != VMA_NULL);
    VMA_ASSERT(pMemoryTypeIndex != VMA_NULL);

    if(pAllocationCreateInfo->memoryTypeBits != 0)
    {
        memoryTypeBits &= pAllocationCreateInfo->memoryTypeBits;
    }
    
    uint32_t requiredFlags = pAllocationCreateInfo->requiredFlags;
    uint32_t preferredFlags = pAllocationCreateInfo->preferredFlags;

    // Convert usage to requiredFlags and preferredFlags.
    switch(pAllocationCreateInfo->usage)
    {
    case VMA_MEMORY_USAGE_UNKNOWN:
        break;
    case VMA_MEMORY_USAGE_GPU_ONLY:
        preferredFlags |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        break;
    case VMA_MEMORY_USAGE_CPU_ONLY:
        requiredFlags |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
        break;
    case VMA_MEMORY_USAGE_CPU_TO_GPU:
        requiredFlags |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
        preferredFlags |= VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
        break;
    case VMA_MEMORY_USAGE_GPU_TO_CPU:
        requiredFlags |= VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT;
        preferredFlags |= VK_MEMORY_PROPERTY_HOST_COHERENT_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
        break;
    default:
        break;
    }

    *pMemoryTypeIndex = UINT32_MAX;
    uint32_t minCost = UINT32_MAX;
    for(uint32_t memTypeIndex = 0, memTypeBit = 1;
        memTypeIndex < allocator->GetMemoryTypeCount();
        ++memTypeIndex, memTypeBit <<= 1)
    {
        // This memory type is acceptable according to memoryTypeBits bitmask.
        if((memTypeBit & memoryTypeBits) != 0)
        {
            const VkMemoryPropertyFlags currFlags =
                allocator->m_MemProps.memoryTypes[memTypeIndex].propertyFlags;
            // This memory type contains requiredFlags.
            if((requiredFlags & ~currFlags) == 0)
            {
                // Calculate cost as number of bits from preferredFlags not present in this memory type.
                uint32_t currCost = VmaCountBitsSet(preferredFlags & ~currFlags);
                // Remember memory type with lowest cost.
                if(currCost < minCost)
                {
                    *pMemoryTypeIndex = memTypeIndex;
                    if(currCost == 0)
                    {
                        return VK_SUCCESS;
                    }
                    minCost = currCost;
                }
            }
        }
    }
    return (*pMemoryTypeIndex != UINT32_MAX) ? VK_SUCCESS : VK_ERROR_FEATURE_NOT_PRESENT;
}

VkResult vmaFindMemoryTypeIndexForBufferInfo(
    VmaAllocator allocator,
    const VkBufferCreateInfo* pBufferCreateInfo,
    const VmaAllocationCreateInfo* pAllocationCreateInfo,
    uint32_t* pMemoryTypeIndex)
{
    VMA_ASSERT(allocator != VK_NULL_HANDLE);
    VMA_ASSERT(pBufferCreateInfo != VMA_NULL);
    VMA_ASSERT(pAllocationCreateInfo != VMA_NULL);
    VMA_ASSERT(pMemoryTypeIndex != VMA_NULL);

    const VkDevice hDev = allocator->m_hDevice;
    VkBuffer hBuffer = VK_NULL_HANDLE;
    VkResult res = allocator->GetVulkanFunctions().vkCreateBuffer(
        hDev, pBufferCreateInfo, allocator->GetAllocationCallbacks(), &hBuffer);
    if(res == VK_SUCCESS)
    {
        VkMemoryRequirements memReq = {};
        allocator->GetVulkanFunctions().vkGetBufferMemoryRequirements(
            hDev, hBuffer, &memReq);

        res = vmaFindMemoryTypeIndex(
            allocator,
            memReq.memoryTypeBits,
            pAllocationCreateInfo,
            pMemoryTypeIndex);

        allocator->GetVulkanFunctions().vkDestroyBuffer(
            hDev, hBuffer, allocator->GetAllocationCallbacks());
    }
    return res;
}

VkResult vmaFindMemoryTypeIndexForImageInfo(
    VmaAllocator allocator,
    const VkImageCreateInfo* pImageCreateInfo,
    const VmaAllocationCreateInfo* pAllocationCreateInfo,
    uint32_t* pMemoryTypeIndex)
{
    VMA_ASSERT(allocator != VK_NULL_HANDLE);
    VMA_ASSERT(pImageCreateInfo != VMA_NULL);
    VMA_ASSERT(pAllocationCreateInfo != VMA_NULL);
    VMA_ASSERT(pMemoryTypeIndex != VMA_NULL);

    const VkDevice hDev = allocator->m_hDevice;
    VkImage hImage = VK_NULL_HANDLE;
    VkResult res = allocator->GetVulkanFunctions().vkCreateImage(
        hDev, pImageCreateInfo, allocator->GetAllocationCallbacks(), &hImage);
    if(res == VK_SUCCESS)
    {
        VkMemoryRequirements memReq = {};
        allocator->GetVulkanFunctions().vkGetImageMemoryRequirements(
            hDev, hImage, &memReq);

        res = vmaFindMemoryTypeIndex(
            allocator,
            memReq.memoryTypeBits,
            pAllocationCreateInfo,
            pMemoryTypeIndex);

        allocator->GetVulkanFunctions().vkDestroyImage(
            hDev, hImage, allocator->GetAllocationCallbacks());
    }
    return res;
}

VkResult vmaCreatePool(
	VmaAllocator allocator,
	const VmaPoolCreateInfo* pCreateInfo,
	VmaPool* pPool)
{
    VMA_ASSERT(allocator && pCreateInfo && pPool);

    VMA_DEBUG_LOG("vmaCreatePool");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    return allocator->CreatePool(pCreateInfo, pPool);
}

void vmaDestroyPool(
    VmaAllocator allocator,
    VmaPool pool)
{
    VMA_ASSERT(allocator);

    if(pool == VK_NULL_HANDLE)
    {
        return;
    }

    VMA_DEBUG_LOG("vmaDestroyPool");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->DestroyPool(pool);
}

void vmaGetPoolStats(
    VmaAllocator allocator,
    VmaPool pool,
    VmaPoolStats* pPoolStats)
{
    VMA_ASSERT(allocator && pool && pPoolStats);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->GetPoolStats(pool, pPoolStats);
}

void vmaMakePoolAllocationsLost(
    VmaAllocator allocator,
    VmaPool pool,
    size_t* pLostAllocationCount)
{
    VMA_ASSERT(allocator && pool);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->MakePoolAllocationsLost(pool, pLostAllocationCount);
}

VkResult vmaAllocateMemory(
    VmaAllocator allocator,
    const VkMemoryRequirements* pVkMemoryRequirements,
    const VmaAllocationCreateInfo* pCreateInfo,
    VmaAllocation* pAllocation,
    VmaAllocationInfo* pAllocationInfo)
{
    VMA_ASSERT(allocator && pVkMemoryRequirements && pCreateInfo && pAllocation);

    VMA_DEBUG_LOG("vmaAllocateMemory");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

	VkResult result = allocator->AllocateMemory(
        *pVkMemoryRequirements,
        false, // requiresDedicatedAllocation
        false, // prefersDedicatedAllocation
        VK_NULL_HANDLE, // dedicatedBuffer
        VK_NULL_HANDLE, // dedicatedImage
        *pCreateInfo,
        VMA_SUBALLOCATION_TYPE_UNKNOWN,
        pAllocation);

    if(pAllocationInfo && result == VK_SUCCESS)
    {
        allocator->GetAllocationInfo(*pAllocation, pAllocationInfo);
    }

	return result;
}

VkResult vmaAllocateMemoryForBuffer(
    VmaAllocator allocator,
    VkBuffer buffer,
    const VmaAllocationCreateInfo* pCreateInfo,
    VmaAllocation* pAllocation,
    VmaAllocationInfo* pAllocationInfo)
{
    VMA_ASSERT(allocator && buffer != VK_NULL_HANDLE && pCreateInfo && pAllocation);

    VMA_DEBUG_LOG("vmaAllocateMemoryForBuffer");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    VkMemoryRequirements vkMemReq = {};
    bool requiresDedicatedAllocation = false;
    bool prefersDedicatedAllocation = false;
    allocator->GetBufferMemoryRequirements(buffer, vkMemReq,
        requiresDedicatedAllocation,
        prefersDedicatedAllocation);

    VkResult result = allocator->AllocateMemory(
        vkMemReq,
        requiresDedicatedAllocation,
        prefersDedicatedAllocation,
        buffer, // dedicatedBuffer
        VK_NULL_HANDLE, // dedicatedImage
        *pCreateInfo,
        VMA_SUBALLOCATION_TYPE_BUFFER,
        pAllocation);

    if(pAllocationInfo && result == VK_SUCCESS)
    {
        allocator->GetAllocationInfo(*pAllocation, pAllocationInfo);
    }

	return result;
}

VkResult vmaAllocateMemoryForImage(
    VmaAllocator allocator,
    VkImage image,
    const VmaAllocationCreateInfo* pCreateInfo,
    VmaAllocation* pAllocation,
    VmaAllocationInfo* pAllocationInfo)
{
    VMA_ASSERT(allocator && image != VK_NULL_HANDLE && pCreateInfo && pAllocation);

    VMA_DEBUG_LOG("vmaAllocateMemoryForImage");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    VkResult result = AllocateMemoryForImage(
        allocator,
        image,
        pCreateInfo,
        VMA_SUBALLOCATION_TYPE_IMAGE_UNKNOWN,
        pAllocation);

    if(pAllocationInfo && result == VK_SUCCESS)
    {
        allocator->GetAllocationInfo(*pAllocation, pAllocationInfo);
    }

	return result;
}

void vmaFreeMemory(
    VmaAllocator allocator,
    VmaAllocation allocation)
{
    VMA_ASSERT(allocator && allocation);

    VMA_DEBUG_LOG("vmaFreeMemory");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->FreeMemory(allocation);
}

void vmaGetAllocationInfo(
    VmaAllocator allocator,
    VmaAllocation allocation,
    VmaAllocationInfo* pAllocationInfo)
{
    VMA_ASSERT(allocator && allocation && pAllocationInfo);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->GetAllocationInfo(allocation, pAllocationInfo);
}

VkBool32 vmaTouchAllocation(
    VmaAllocator allocator,
    VmaAllocation allocation)
{
    VMA_ASSERT(allocator && allocation);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    return allocator->TouchAllocation(allocation);
}

void vmaSetAllocationUserData(
    VmaAllocator allocator,
    VmaAllocation allocation,
    void* pUserData)
{
    VMA_ASSERT(allocator && allocation);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocation->SetUserData(allocator, pUserData);
}

void vmaCreateLostAllocation(
    VmaAllocator allocator,
    VmaAllocation* pAllocation)
{
    VMA_ASSERT(allocator && pAllocation);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK;

    allocator->CreateLostAllocation(pAllocation);
}

VkResult vmaMapMemory(
    VmaAllocator allocator,
    VmaAllocation allocation,
    void** ppData)
{
    VMA_ASSERT(allocator && allocation && ppData);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    return allocator->Map(allocation, ppData);
}

void vmaUnmapMemory(
    VmaAllocator allocator,
    VmaAllocation allocation)
{
    VMA_ASSERT(allocator && allocation);

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    allocator->Unmap(allocation);
}

VkResult vmaDefragment(
    VmaAllocator allocator,
    VmaAllocation* pAllocations,
    size_t allocationCount,
    VkBool32* pAllocationsChanged,
    const VmaDefragmentationInfo *pDefragmentationInfo,
    VmaDefragmentationStats* pDefragmentationStats)
{
    VMA_ASSERT(allocator && pAllocations);

    VMA_DEBUG_LOG("vmaDefragment");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    return allocator->Defragment(pAllocations, allocationCount, pAllocationsChanged, pDefragmentationInfo, pDefragmentationStats);
}

VkResult vmaBindBufferMemory(
    VmaAllocator allocator,
    VmaAllocation allocation,
    VkBuffer buffer)
{
    VMA_ASSERT(allocator && allocation && buffer);

    VMA_DEBUG_LOG("vmaBindBufferMemory");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    return allocator->BindBufferMemory(allocation, buffer);
}

VkResult vmaBindImageMemory(
    VmaAllocator allocator,
    VmaAllocation allocation,
    VkImage image)
{
    VMA_ASSERT(allocator && allocation && image);

    VMA_DEBUG_LOG("vmaBindImageMemory");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    return allocator->BindImageMemory(allocation, image);
}

VkResult vmaCreateBuffer(
    VmaAllocator allocator,
    const VkBufferCreateInfo* pBufferCreateInfo,
    const VmaAllocationCreateInfo* pAllocationCreateInfo,
    VkBuffer* pBuffer,
    VmaAllocation* pAllocation,
    VmaAllocationInfo* pAllocationInfo)
{
    VMA_ASSERT(allocator && pBufferCreateInfo && pAllocationCreateInfo && pBuffer && pAllocation);
    
    VMA_DEBUG_LOG("vmaCreateBuffer");
    
    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    *pBuffer = VK_NULL_HANDLE;
    *pAllocation = VK_NULL_HANDLE;

    // 1. Create VkBuffer.
    VkResult res = (*allocator->GetVulkanFunctions().vkCreateBuffer)(
        allocator->m_hDevice,
        pBufferCreateInfo,
        allocator->GetAllocationCallbacks(),
        pBuffer);
    if(res >= 0)
    {
        // 2. vkGetBufferMemoryRequirements.
        VkMemoryRequirements vkMemReq = {};
        bool requiresDedicatedAllocation = false;
        bool prefersDedicatedAllocation  = false;
        allocator->GetBufferMemoryRequirements(*pBuffer, vkMemReq,
            requiresDedicatedAllocation, prefersDedicatedAllocation);

         // Make sure alignment requirements for specific buffer usages reported
         // in Physical Device Properties are included in alignment reported by memory requirements.
        if((pBufferCreateInfo->usage & VK_BUFFER_USAGE_UNIFORM_TEXEL_BUFFER_BIT) != 0)
        {
           VMA_ASSERT(vkMemReq.alignment %
              allocator->m_PhysicalDeviceProperties.limits.minTexelBufferOffsetAlignment == 0);
        }
        if((pBufferCreateInfo->usage & VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT) != 0)
        {
           VMA_ASSERT(vkMemReq.alignment %
              allocator->m_PhysicalDeviceProperties.limits.minUniformBufferOffsetAlignment == 0);
        }
        if((pBufferCreateInfo->usage & VK_BUFFER_USAGE_STORAGE_BUFFER_BIT) != 0)
        {
           VMA_ASSERT(vkMemReq.alignment %
              allocator->m_PhysicalDeviceProperties.limits.minStorageBufferOffsetAlignment == 0);
        }

        // 3. Allocate memory using allocator.
        res = allocator->AllocateMemory(
            vkMemReq,
            requiresDedicatedAllocation,
            prefersDedicatedAllocation,
            *pBuffer, // dedicatedBuffer
            VK_NULL_HANDLE, // dedicatedImage
            *pAllocationCreateInfo,
            VMA_SUBALLOCATION_TYPE_BUFFER,
            pAllocation);
        if(res >= 0)
        {
            // 3. Bind buffer with memory.
            res = allocator->BindBufferMemory(*pAllocation, *pBuffer);
            if(res >= 0)
            {
                // All steps succeeded.
                if(pAllocationInfo != VMA_NULL)
                {
                    allocator->GetAllocationInfo(*pAllocation, pAllocationInfo);
                }
                return VK_SUCCESS;
            }
            allocator->FreeMemory(*pAllocation);
            *pAllocation = VK_NULL_HANDLE;
            (*allocator->GetVulkanFunctions().vkDestroyBuffer)(allocator->m_hDevice, *pBuffer, allocator->GetAllocationCallbacks());
            *pBuffer = VK_NULL_HANDLE;
            return res;
        }
        (*allocator->GetVulkanFunctions().vkDestroyBuffer)(allocator->m_hDevice, *pBuffer, allocator->GetAllocationCallbacks());
        *pBuffer = VK_NULL_HANDLE;
        return res;
    }
    return res;
}

void vmaDestroyBuffer(
    VmaAllocator allocator,
    VkBuffer buffer,
    VmaAllocation allocation)
{
    if(buffer != VK_NULL_HANDLE)
    {
        VMA_ASSERT(allocator);

        VMA_DEBUG_LOG("vmaDestroyBuffer");

        VMA_DEBUG_GLOBAL_MUTEX_LOCK

        (*allocator->GetVulkanFunctions().vkDestroyBuffer)(allocator->m_hDevice, buffer, allocator->GetAllocationCallbacks());
        
        allocator->FreeMemory(allocation);
    }
}

VkResult vmaCreateImage(
    VmaAllocator allocator,
    const VkImageCreateInfo* pImageCreateInfo,
    const VmaAllocationCreateInfo* pAllocationCreateInfo,
    VkImage* pImage,
    VmaAllocation* pAllocation,
    VmaAllocationInfo* pAllocationInfo)
{
    VMA_ASSERT(allocator && pImageCreateInfo && pAllocationCreateInfo && pImage && pAllocation);

    VMA_DEBUG_LOG("vmaCreateImage");

    VMA_DEBUG_GLOBAL_MUTEX_LOCK

    *pImage = VK_NULL_HANDLE;
    *pAllocation = VK_NULL_HANDLE;

    // 1. Create VkImage.
    VkResult res = (*allocator->GetVulkanFunctions().vkCreateImage)(
        allocator->m_hDevice,
        pImageCreateInfo,
        allocator->GetAllocationCallbacks(),
        pImage);
    if(res >= 0)
    {
        VmaSuballocationType suballocType = pImageCreateInfo->tiling == VK_IMAGE_TILING_OPTIMAL ?
            VMA_SUBALLOCATION_TYPE_IMAGE_OPTIMAL :
            VMA_SUBALLOCATION_TYPE_IMAGE_LINEAR;
        
        // 2. Allocate memory using allocator.
        res = AllocateMemoryForImage(allocator, *pImage, pAllocationCreateInfo, suballocType, pAllocation);
        if(res >= 0)
        {
            // 3. Bind image with memory.
            res = allocator->BindImageMemory(*pAllocation, *pImage);
            if(res >= 0)
            {
                // All steps succeeded.
                if(pAllocationInfo != VMA_NULL)
                {
                    allocator->GetAllocationInfo(*pAllocation, pAllocationInfo);
                }
                return VK_SUCCESS;
            }
            allocator->FreeMemory(*pAllocation);
            *pAllocation = VK_NULL_HANDLE;
            (*allocator->GetVulkanFunctions().vkDestroyImage)(allocator->m_hDevice, *pImage, allocator->GetAllocationCallbacks());
            *pImage = VK_NULL_HANDLE;
            return res;
        }
        (*allocator->GetVulkanFunctions().vkDestroyImage)(allocator->m_hDevice, *pImage, allocator->GetAllocationCallbacks());
        *pImage = VK_NULL_HANDLE;
        return res;
    }
    return res;
}

void vmaDestroyImage(
    VmaAllocator allocator,
    VkImage image,
    VmaAllocation allocation)
{
    if(image != VK_NULL_HANDLE)
    {
        VMA_ASSERT(allocator);

        VMA_DEBUG_LOG("vmaDestroyImage");

        VMA_DEBUG_GLOBAL_MUTEX_LOCK

        (*allocator->GetVulkanFunctions().vkDestroyImage)(allocator->m_hDevice, image, allocator->GetAllocationCallbacks());

        allocator->FreeMemory(allocation);
    }
}

#endif // #ifdef VMA_IMPLEMENTATION