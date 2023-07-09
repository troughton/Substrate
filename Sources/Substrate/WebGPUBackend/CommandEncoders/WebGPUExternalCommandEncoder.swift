#if canImport(WebGPU)
import WebGPU

final class WebGPUExternalCommandEncoder: ExternalCommandEncoderImpl {
    let encoder: WGPUCommandEncoder
    
    init(passRecord: RenderPassRecord, encoder: WGPUCommandEncoder) {
        self.encoder = encoder
    }
    
    func pushDebugGroup(_ string: String) {
        wgpuCommandEncoderPushDebugGroup(self.encoder, string)
    }
    
    func popDebugGroup() {
        wgpuCommandEncoderPopDebugGroup(self.encoder)
    }
    
    func insertDebugSignpost(_ string: String) {
        wgpuCommandEncoderInsertDebugMarker(self.encoder, string)
    }
    
    func setLabel(_ label: String) {
        wgpuCommandEncoderSetLabel(self.encoder, label)
    }
    
    func encodeCommand(_ command: (UnsafeRawPointer) -> Void) {
        command(UnsafeRawPointer(self.encoder))
    }
}

#endif // canImport(Metal)
