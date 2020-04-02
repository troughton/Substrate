
add_library(FrameGraphCExtras SHARED
  FrameGraphCExtras.c
  vk_mem_alloc.cpp)

install(TARGETS FrameGraphCExtras
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

