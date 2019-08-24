
#include "include/FrameGraphCExtras.h"

_Bool LinkedNodeHeaderCompareAndSwap(LinkedNodeHeader *insertionNode, LinkedNodeHeader *nodeToInsert) {
    LinkedNodeHeader *expected = nodeToInsert->next;
    return atomic_compare_exchange_weak(&insertionNode->next, &expected, nodeToInsert);
}
