
add_library(FrameGraphCExtras SHARED
  FrameGraphCExtras.c
  vk_mem_alloc.cpp)
  
target_include_directories(FrameGraphCExtras PUBLIC include/)

install(TARGETS FrameGraphCExtras
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

