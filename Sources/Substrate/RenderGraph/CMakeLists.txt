add_subdirectory(BackendExecution)

target_sources(Substrate PRIVATE 
  ArgumentEncoder.swift
  ArgumentEncoding.swift
  CommandRecorder.swift
  DepthStencilDescriptor.swift
  Enums.swift
  RenderGraph.swift
  RenderGraphBlackboard.swift
  RenderGraphJobManager.swift
  FunctionConstantEncoder.swift
  GPUResourceUploader.swift
  PipelineReflection.swift
  Queue.swift
  RefCountedResource.swift
  RenderBackend.swift
  RenderPipeline.swift
  RenderTargetDescriptor.swift
  ResourceDescriptors.swift
  ResourceMap.swift
  ResourceRegistries.swift
  Resources.swift
  ResourceUsages.swift
  Sampler.swift
  SwapChain.swift
  TypedCommandRecorder.swift
  VertexDescriptor.swift
  )

