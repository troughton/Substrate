
add_library(SubstrateCExtras SHARED
  SubstrateCExtras.c
  vk_mem_alloc.cpp)
  
target_include_directories(SubstrateCExtras PUBLIC include/)

install(TARGETS SubstrateCExtras
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)

