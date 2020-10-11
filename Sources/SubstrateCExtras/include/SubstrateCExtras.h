
#ifndef FRAMEGRAPH_C_EXTRAS_H
#define FRAMEGRAPH_C_EXTRAS_H

#include <stdatomic.h>
#include <stdbool.h>
#include "vk_mem_alloc.h"

typedef struct LinkedNodeHeader {
    struct LinkedNodeHeader *_Atomic next;
} LinkedNodeHeader;

bool LinkedNodeHeaderCompareAndSwap(LinkedNodeHeader *insertionNode, LinkedNodeHeader *nodeToInsert);

#endif // FRAMEGRAPH_C_EXTRAS_H
