
cmake_minimum_required(VERSION 3.15.1)

project(SwiftFrameGraph LANGUAGES C Swift)

# place all modules into `swift` in the root of the build tree
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# enable shared libraries by default (Windows, Darwin)
#
# Windows does not yet support static libraries in Swift, Darwin no longer
# supports static libraries after ABI stability.
if(CMAKE_SYSTEM_NAME STREQUAL Windows OR CMAKE_SYSTEM_NAME STREQUAL Darwin)
  option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
endif()


# Add CAtomics
include_directories(swift-atomics/Sources/CAtomics/include)
include_directories(ModuleMaps/CAtomics)
add_library(CAtomics SHARED
  swift-atomics/Sources/CAtomics/CAtomics.c)

install(TARGETS CAtomics
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

# Add the FrameGraph libraries.

include(CTest)

include_directories(ModuleMaps/FrameGraphCExtras)

add_subdirectory(Sources)


