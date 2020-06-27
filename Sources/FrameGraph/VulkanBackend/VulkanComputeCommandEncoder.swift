//
//  ComputeCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities

struct VulkanComputePipelineDescriptor : Hashable {
    var descriptor : ComputePipelineDescriptor
    var layout : VkPipelineLayout
    var threadsPerThreadgroup : Size 

    func withVulkanPipelineCreateInfo(pipelineReflection: VulkanPipelineReflection, stateCaches: VulkanStateCaches, _ withInfo: (inout VkComputePipelineCreateInfo) -> Void) {
        let specialisationInfo = stateCaches[self.descriptor._functionConstants, pipelineReflection: pipelineReflection] // TODO: also pass in threadsPerThreadgroup.
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
        
        init(shaderLibrary: VulkanShaderLibrary) {
            self.shaderLibrary = shaderLibrary
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
            _layout = self.shaderLibrary.pipelineLayout(for: .compute(descriptor.function))
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
    let commandBufferResources: VulkanCommandBuffer
    let resourceMap: FrameResourceMap<VulkanBackend>
    let stateCaches : VulkanStateCaches
    
    var pipelineState : PipelineState! = nil
    
    public init(device: VulkanDevice, commandBuffer: VulkanCommandBuffer, shaderLibrary: VulkanShaderLibrary, caches: VulkanStateCaches, resourceMap: FrameResourceMap<VulkanBackend>) {
        self.device = device
        self.commandBufferResources = commandBuffer
        self.stateCaches = caches
        self.resourceMap = resourceMap
        
        self.pipelineState = PipelineState(shaderLibrary: shaderLibrary)
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
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [CompactedResourceCommand<VulkanCompactedResourceCommandType>]) {
         var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
        
        for (i, command) in zip(pass.commandRange!, pass.commands) {
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i)
            self.executeCommand(command)
            self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i)
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
            
            let argumentBuffer = args.pointee.argumentBuffer
            let vkArgumentBuffer = resourceMap[argumentBuffer]

            self.commandBufferResources.argumentBuffers.append(vkArgumentBuffer)

            var set : VkDescriptorSet? = vkArgumentBuffer.descriptorSet
            vkCmdBindDescriptorSets(self.commandBuffer, self.bindPoint, self.pipelineLayout, bindingPath.set, 1, &set, 0, nil)

        case .setBytes(let args):
            let bindingPath = args.pointee.bindingPath
            let bytes = args.pointee.bytes
            let length = args.pointee.length
            
            let resourceInfo = self.pipelineReflection[bindingPath]
            
            switch resourceInfo.type {
            case .pushConstantBuffer:
                assert(resourceInfo.bindingRange.count == length, "The push constant size and the setBytes length must match.")
                vkCmdPushConstants(self.commandBuffer, self.pipelineLayout, VkShaderStageFlags(resourceInfo.accessedStages), resourceInfo.bindingRange.lowerBound, length, bytes)
                
            default:
                fatalError("Need to implement VK_EXT_inline_uniform_block or else fall back to a temporary staging buffer")
            }
            
        case .setBufferOffset(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setBuffer(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setTexture(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
        case .setSamplerState(let args):
            fatalError("Currently unimplemented on Vulkan; should use vkCmdPushDescriptorSetKHR when implemented.")
            
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
            
            let buffer = resourceMap[args.pointee.indirectBuffer]
            vkCmdDispatchIndirect(self.commandBuffer, buffer.buffer.vkBuffer, VkDeviceSize(args.pointee.indirectBufferOffset) + VkDeviceSize(buffer.offset))
            
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

#endif // canImport(Vulkan)
