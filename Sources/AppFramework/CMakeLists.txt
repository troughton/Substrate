
add_library(AppFramework)

add_subdirectory(Input)
add_subdirectory(UpdateScheduler)
add_subdirectory(Windowing)

target_sources(AppFramework PRIVATE
  ImGui+RGBAColor.swift
  ImGuiTextureLookup.swift
)

target_link_libraries(AppFramework PRIVATE
  SwiftFrameGraph CNativeFileDialog CImGui FrameGraphUtilities _NumericsShims RealModule SwiftMath)

install(TARGETS AppFramework
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
  COMPONENT lib)


