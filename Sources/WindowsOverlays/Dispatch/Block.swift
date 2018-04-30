//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CDispatch

public struct DispatchWorkItemFlags : OptionSet, RawRepresentable {
	public let rawValue: UInt
	public init(rawValue: UInt) { self.rawValue = rawValue }

	public static let barrier = DispatchWorkItemFlags(rawValue: 0x1)

	@available(OSX 10.10, iOS 8.0, *)
	public static let detached = DispatchWorkItemFlags(rawValue: 0x2)

	@available(OSX 10.10, iOS 8.0, *)
	public static let assignCurrentContext = DispatchWorkItemFlags(rawValue: 0x4)

	@available(OSX 10.10, iOS 8.0, *)
	public static let noQoS = DispatchWorkItemFlags(rawValue: 0x8)

	@available(OSX 10.10, iOS 8.0, *)
	public static let inheritQoS = DispatchWorkItemFlags(rawValue: 0x10)

	@available(OSX 10.10, iOS 8.0, *)
	public static let enforceQoS = DispatchWorkItemFlags(rawValue: 0x20)
}

/// The dispatch_block_t typealias is different from usual closures in that it
/// uses @convention(block). This is to avoid unnecessary bridging between
/// C blocks and Swift closures, which interferes with dispatch APIs that depend
/// on the referential identity of a block. Particularly, dispatch_block_create.
internal typealias _DispatchBlock = @convention(block) () -> Void
internal typealias dispatch_block_t = @convention(block) () -> Void
