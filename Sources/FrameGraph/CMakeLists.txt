

add_library(SwiftFrameGraph)

add_subdirectory(FrameGraph)
add_subdirectory(MetalBackend)

target_link_libraries(SwiftFrameGraph PRIVATE
  CAtomics FrameGraphUtilities FrameGraphCExtras)
set_target_properties(SwiftFrameGraph PROPERTIES
  Swift_LANGUAGE_VERSION 5)

install(TARGETS SwiftFrameGraph
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
  COMPONENT lib)

