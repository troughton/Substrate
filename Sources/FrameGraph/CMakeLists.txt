add_library(SwiftFrameGraph)

add_subdirectory(FrameGraph)

if (APPLE)
    add_subdirectory(MetalBackend)
endif()

if (Vulkan_FOUND)
    add_subdirectory(VulkanBackend)
endif()

target_link_libraries(SwiftFrameGraph PRIVATE
  CAtomics FrameGraphUtilities FrameGraphCExtras)
set_target_properties(SwiftFrameGraph PROPERTIES
  Swift_LANGUAGE_VERSION 5)

install(TARGETS SwiftFrameGraph
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
  COMPONENT lib)

