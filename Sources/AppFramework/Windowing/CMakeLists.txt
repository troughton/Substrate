
target_sources(AppFramework PRIVATE
  Application.swift
  InputManager.swift
  Screen.swift
  Window.swift
  Window+ImGui.swift
)

if (APPLE)
  target_sources(AppFramework PRIVATE
    AppFrameworkNSApplication.swift
    CocoaApplication.swift
    CocoaInputManager.swift
    CocoaWindow.swift
    iOSApplication.swift
    iOSWindow.swift
  )
endif()

if (SDL2_FOUND)
  target_sources(AppFramework PRIVATE
    SDLApplication.swift
    SDLGamepadManager.swift
    SDLInputManager.swift
    SDLWindow.swift
  )
endif()
