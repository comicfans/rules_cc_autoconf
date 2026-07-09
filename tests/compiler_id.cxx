#include "compiler_id.h"

#include <string_view>

#ifdef __clang_version__
    #define CHECK "clang"
#elif GCC_VERSION
    #define CHECK "gcc"
#elif _MSC_VER
    #define CHECK "msvc"
#else
    #define CHECK "other"
#endif

int main(int, char**) {
    static_assert(std::string_view(COMPILER_ID) == std::string_view(CHECK));
    return 0;
}
