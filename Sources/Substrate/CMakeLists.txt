add_library(Substrate)

add_subdirectory(RenderGraph)

if (APPLE)
    add_subdirectory(MetalBackend)
endif()

if (Vulkan_FOUND)
    add_subdirectory(VulkanBackend)
endif()

target_link_libraries(Substrate PRIVATE
  CAtomics SubstrateUtilities SubstrateCExtras)
set_target_properties(Substrate PROPERTIES
  Swift_LANGUAGE_VERSION 5)

install(TARGETS Substrate
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
  COMPONENT lib)

