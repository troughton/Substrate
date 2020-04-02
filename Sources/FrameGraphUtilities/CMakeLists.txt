
add_library(FrameGraphUtilities
  Allocators.swift
  ArrayBuffer.swift
  BitPacking.swift
  BitSet.swift
  CachedValue.swift
  Collection+BinarySearch.swift
  Collection+OutOfBounds.swift
  DependencyTable.swift
  EscapingPointer.swift
  HashMap.swift
  HashSet.swift
  LinkedList.swift
  Memory.swift
  ReaderWriterLock.swift
  References.swift
  ResizingAllocator.swift
  RingBuffer.swift
  RoundInteger.swift
  SpinLock.swift
  TaggedHeap.swift)

set_target_properties(FrameGraphUtilities PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

target_link_libraries(FrameGraphUtilities PRIVATE
  CAtomics)

install(TARGETS FrameGraphUtilities
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin
  COMPONENT lib)
