
add_library(CNativeFileDialog SHARED
  nfd_common.c
)

if (APPLE)
    target_sources(CNativeFileDialog PRIVATE nfd_cocoa.m)
    target_link_libraries(CNativeFileDialog PRIVATE "-framework AppKit")
endif ()

if (GTK2_FOUND)
    target_sources(CNativeFileDialog nfd_gtk.c)
endif ()

if (WIN32)
    target_sources(CNativeFileDialog nfd_win.cpp)
endif ()

target_include_directories(CNativeFileDialog PUBLIC include/)

install(TARGETS CNativeFileDialog
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

