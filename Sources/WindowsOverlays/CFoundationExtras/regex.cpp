
#include "include/CFoundationExtras.h"
#include <regex>
#include <string.h>

CF_EXPORT bool regexSearch(const wchar_t *_Nonnull pattern, const wchar_t *_Nonnull string) {
    size_t patternLength = wcslen(pattern);
    std::wregex re(pattern, patternLength);
    std::wcmatch match;
    return std::regex_search(string, match, re);
}