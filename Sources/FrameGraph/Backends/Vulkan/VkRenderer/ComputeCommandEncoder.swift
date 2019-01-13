//
//  ComputeCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

import SwiftFrameGraph
import CVkRenderer
import Utilities

struct VulkanComputePipelineDescriptor : Hashable {
    var descriptor : ComputePipelineDescriptor
    var layout : VkPipelineLayout
    var threadsPerThreadgroup : Size 

    func withVulkanPipelineCreateInfo(pipelineReflection: VulkanPipelineReflection, stateCaches: StateCaches, _ withInfo: (inout VkComputePipelineCreateInfo) -> Void) {
        let specialisationInfo = stateCaches[self.descriptor.functionConstants, pipelineReflection: pipelineReflection] // TODO: also pass in threadsPerThreadgroup.
        let specialisationInfoPtr = specialisationInfo == nil ? nil : escapingPointer(to: &specialisationInfo!.info)

        let module = stateCaches.shaderLibrary.moduleForFunction(self.descriptor.function)!

        var stage = VkPipelineShaderStageCreateInfo()
        stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
        stage.module = module.vkModule
        stage.stage = VK_SHADER_STAGE_COMPUTE_BIT
        stage.pSpecializationInfo = specialisationInfoPtr
        
        let entryPoint = module.entryPointForFunction(named: self.descriptor.function)
        entryPoint.withCString { cFuncName in 
            stage.pName = cFuncName

            var pipelineInfo = VkComputePipelineCreateInfo()
            pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO
            
            pipelineInfo.stage = stage
            pipelineInfo.layout = self.layout
            
            withInfo(&pipelineInfo)
        }
    }
}

class VulkanComputeCommandEncoder : VulkanResourceBindingCommandEncoder {

    class PipelineState {
        let shaderLibrary : VulkanShaderLibrary
        let bindingManager : ResourceBindingManager
        
        init(shaderLibrary: VulkanShaderLibrary, bindingManager: ResourceBindingManager) {
            self.shaderLibrary = shaderLibrary
            self.bindingManager = bindingManager
        }
        
        var hasChanged = true
        
        var descriptor : ComputePipelineDescriptor! = nil {
            didSet {
                let key = PipelineLayoutKey.compute(descriptor.function)
                self.pipelineReflection = shaderLibrary.reflection(for: key)
                self._layout = nil
                
                self.hasChanged = true
            }
        }
        
        private var _layout : VkPipelineLayout! = nil
        
        var layout : VkPipelineLayout {
            if let layout = _layout {
                return layout
            }
            _layout = self.shaderLibrary.pipelineLayout(for: .compute(descriptor.function), bindingManager: self.bindingManager)
            return _layout
        }
        
        var pipelineReflection : VulkanPipelineReflection! = nil
        
        var threadsPerThreadgroup : Size = Size(width: 0, height: 0, depth: 0) {
            didSet {
                if oldValue != self.threadsPerThreadgroup {
                    self.hasChanged = true
                }
            }
        }

        var vulkanPipelineDescriptor : VulkanComputePipelineDescriptor {
            return VulkanComputePipelineDescriptor(descriptor: self.descriptor, 
                                                   layout: self.layout, 
                                                   threadsPerThreadgroup: threadsPerThreadgroup)
        }
    }
    
    let device : VulkanDevice
    let commandBufferResources: CommandBufferResources
    let resourceRegistry: ResourceRegistry
    let stateCaches : StateCaches
    
    var bindingManager : ResourceBindingManager! = nil
    var pipelineState : PipelineState! = nil
    
    public init(device: VulkanDevice, commandBuffer: CommandBufferResources, shaderLibrary: VulkanShaderLibrary, caches: StateCaches, resourceRegistry: ResourceRegistry) {
        self.device = device
        self.commandBufferResources = commandBuffer
        self.stateCaches = caches
        self.resourceRegistry = resourceRegistry
        
        self.bindingManager = ResourceBindingManager(encoder: self)
        self.pipelineState = PipelineState(shaderLibrary: shaderLibrary, bindingManager: bindingManager)
    }
    
    var queueFamily: QueueFamily {
        return .compute
    }
    
    var bindPoint: VkPipelineBindPoint {
        return VK_PIPELINE_BIND_POINT_COMPUTE
    }
    
    var commandBuffer : VkCommandBuffer {
        return self.commandBufferResources.commandBuffer
    }
    
    var pipelineLayout: VkPipelineLayout {
        return self.pipelineState.layout
    }
    
    var pipelineReflection: VulkanPipelineReflection {
        return self.pipelineState.pipelineReflection
    }
    
    func prepareToDispatch() {
        if self.pipelineState.hasChanged {
            defer {
                self.pipelineState.hasChanged = false
            }
            
            let pipeline = self.stateCaches[self.pipelineState.vulkanPipelineDescriptor, pipelineReflection: self.pipelineState.pipelineReflection]

            vkCmdBindPipeline(self.commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline)
        }
        
        self.bindingManager.bindDescriptorSets()
    }
    
    func executeCommands(_ commands: ArraySlice<FrameGraphCommand>, resourceCommands: inout [ResourceCommand]) {
        
        for (i, command) in zip(commands.indices, commands) {
            self.executeResourceCommands(resourceCommands: &resourceCommands, order: .before, commandIndex: i)
            self.executeCommand(command)
            self.executeResourceCommands(resourceCommands: &resourceCommands, order: .after, commandIndex: i)
        }
    }
    
    func executeCommand(_ command: FrameGraphCommand) {
        switch command {
        case .insertDebugSignpost(_):
            break
            
        case .setLabel(_):
            break
            
        case .pushDebugGroup(_):
            break
            
        case .popDebugGroup:
            break
            
        case .setArgumentBuffer(let args):
            let bindingPath = args.pointee.bindingPath
            let vkBindingPath = VulkanResourceBindingPath(bindingPath)
            
            let argumentBuffer = args.pointee.argumentBuffer
            let vkArgumentBuffer = resourceRegistry.allocateArgumentBufferIfNeeded(argumentBuffer, 
                                                                                    bindingPath: vkBindingPath, 
                                                                                    commandBufferResources: self.commandBufferResources, 
                                                                                    pipelineReflection: self.pipelineReflection, 
                                                                                    stateCaches: stateCaches)

            self.commandBufferResources.argumentBuffers.append(vkArgumentBuffer)

            var set : VkDescriptorSet? = vkArgumentBuffer.descriptorSet
            vkCmdBindDescriptorSets(self.commandBuffer, self.bindPoint, self.pipelineLayout, vkBindingPath.set, 1, &set, 0, nil)

        case .setBytes(let args):
            self.bindingManager.setBytes(args: args)
            
        case .setBufferOffset(let args):
            self.bindingManager.setBufferOffset(args: args)
            
        case .setBuffer(let args):
            self.bindingManager.setBuffer(args: args)
            
        case .setTexture(let args):
            self.bindingManager.setTexture(args: args)
            
        case .setSamplerState(let args):
            self.bindingManager.setSamplerState(args: args)
            
        case .dispatchThreads(let args):
            let threadsPerThreadgroup = args.pointee.threadsPerThreadgroup
            self.pipelineState.threadsPerThreadgroup = threadsPerThreadgroup
            self.prepareToDispatch()
            
            let threads = args.pointee.threads
            
            // Calculate how many threadgroups are required for this number of threads
            let threadgroupsPerGridX = (args.pointee.threads.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width
            let threadgroupsPerGridY = (args.pointee.threads.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height
            let threadgroupsPerGridZ = (args.pointee.threads.depth + threadsPerThreadgroup.depth - 1) / threadsPerThreadgroup.depth

            vkCmdDispatch(self.commandBuffer, UInt32(threadgroupsPerGridX), UInt32(threadgroupsPerGridY), UInt32(threadgroupsPerGridZ))
            
        case .dispatchThreadgroups(let args):
            self.pipelineState.threadsPerThreadgroup = args.pointee.threadsPerThreadgroup
            self.prepareToDispatch()
            
            vkCmdDispatch(self.commandBuffer, UInt32(args.pointee.threadgroupsPerGrid.width), UInt32(args.pointee.threadgroupsPerGrid.height), UInt32(args.pointee.threadgroupsPerGrid.depth))
            
        case .dispatchThreadgroupsIndirect(let args):
            self.pipelineState.threadsPerThreadgroup = args.pointee.threadsPerThreadgroup
            self.prepareToDispatch()
            
            vkCmdDispatchIndirect(self.commandBuffer, resourceRegistry[buffer: args.pointee.indirectBuffer]!.vkBuffer, VkDeviceSize(args.pointee.indirectBufferOffset))
            
        case .setComputePipelineDescriptor(let descriptorPtr):
            self.pipelineState.descriptor = descriptorPtr.takeUnretainedValue().pipelineDescriptor
            
        case .setStageInRegion(_):
            fatalError("Unimplemented.")
            
        case .setThreadgroupMemoryLength(_):
            fatalError("Unimplemented.")
            
        default:
            fatalError()
        }
        
    }
}
