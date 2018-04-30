@_exported import visualc
@_exported import ucrt

@_inlineable
public func autoreleasepool(_ c: () -> Void) {
    c()
}