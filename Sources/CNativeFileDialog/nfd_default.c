#if !__has_include(<windows.h>) && !__has_include(<gtk/gtk.h>)&& !__has_include(<AppKit/AppKit.h>)

#include <stdio.h>
#include "include/nfd.h"

/* single file open dialog */    
nfdresult_t NFD_OpenDialog( const nfdchar_t *filterList,
                            const nfdchar_t *defaultPath,
                            nfdchar_t **outPath ) {
    printf("NFD found no platform interface.\n");
    return NFD_ERROR;
}

/* multiple file open dialog */    
nfdresult_t NFD_OpenDialogMultiple( const nfdchar_t *filterList,
                                    const nfdchar_t *defaultPath,
                                    nfdpathset_t *outPaths ) {
    printf("NFD found no platform interface.\n");
    return NFD_ERROR;
}

/* save dialog */
nfdresult_t NFD_SaveDialog( const nfdchar_t *filterList,
                            const nfdchar_t *defaultPath,
                            nfdchar_t **outPath ) {
    printf("NFD found no platform interface.\n");
    return NFD_ERROR;
}


/* select folder dialog */
nfdresult_t NFD_PickFolder( const nfdchar_t *defaultPath,
                            nfdchar_t **outPath) {
    printf("NFD found no platform interface.\n");
    return NFD_ERROR;
}

#endif