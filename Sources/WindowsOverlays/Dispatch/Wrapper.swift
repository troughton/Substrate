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

// This file contains declarations that are provided by the
// importer via Dispatch.apinote when the platform has Objective-C support

public func dispatchMain() -> Never {
	CDispatch.dispatch_main()
}

public class DispatchObject {

	internal func wrapped() -> dispatch_object_t {
		fatalError("should be overriden in subclass")
	}

	public func setTarget(queue:DispatchQueue) {
		dispatch_set_target_queue(wrapped(), queue.__wrapped)
	}

	public func activate() {
		fatalError("Unavailable on Windows.")
	}

	public func suspend() {
		dispatch_suspend(wrapped())
	}

	public func resume() {
		dispatch_resume(wrapped())
	}
}


public class DispatchGroup : DispatchObject {
	internal let __wrapped:dispatch_group_t;

	final internal override func wrapped() -> dispatch_object_t {
		return unsafeBitCast(__wrapped, to: dispatch_object_t.self)
	}

	public override init() {
		__wrapped = dispatch_group_create()
	}

	deinit {
		_swift_dispatch_release(wrapped())
	}

	public func enter() {
		dispatch_group_enter(__wrapped)
	}

	public func leave() {
		dispatch_group_leave(__wrapped)
	}
}

public class DispatchSemaphore : DispatchObject {
	internal let __wrapped: dispatch_semaphore_t;

	final internal override func wrapped() -> dispatch_object_t {
		return unsafeBitCast(__wrapped, to: dispatch_object_t.self)
	}

	public init(value: Int) {
		__wrapped = dispatch_semaphore_create(Int32(value))
	}

	deinit {
		_swift_dispatch_release(wrapped())
	}
}

public class DispatchQueue : DispatchObject {
	internal let __wrapped:dispatch_queue_t;

	final internal override func wrapped() -> dispatch_object_t {
		return unsafeBitCast(__wrapped, to: dispatch_object_t.self)
	}

	internal init(__label: String, attr: dispatch_queue_attr_t?) {
		__wrapped = dispatch_queue_create(__label, attr)
	}

	internal init(__label: String, attr:  dispatch_queue_attr_t?, queue: DispatchQueue?) {
		fatalError("Unsupported on Windows.")
	}

	internal init(queue:dispatch_queue_t) {
		__wrapped = queue
	}

	deinit {
		_swift_dispatch_release(wrapped())
	}

	public func sync(execute workItem: ()->()) {
		withoutActuallyEscaping(workItem) { workItem in
			dispatch_sync(self.__wrapped, workItem)
		}
	}
}

public class DispatchSource : DispatchObject,
	DispatchSourceProtocol,	DispatchSourceRead,
	DispatchSourceSignal, DispatchSourceTimer,
	DispatchSourceUserDataAdd, DispatchSourceUserDataOr,
	DispatchSourceUserDataReplace, DispatchSourceWrite {
	internal let __wrapped:dispatch_source_t

	final internal override func wrapped() -> dispatch_object_t {
		return unsafeBitCast(__wrapped, to: dispatch_object_t.self)
	}

	internal init(source:dispatch_source_t) {
		__wrapped = source
	}

	deinit {
		_swift_dispatch_release(wrapped())
	}
}

#if HAVE_MACH
extension DispatchSource : DispatchSourceMachSend,
	DispatchSourceMachReceive, DispatchSourceMemoryPressure {
}
#endif

public typealias DispatchSourceHandler = @convention(block) () -> Void

public protocol DispatchSourceProtocol {
	func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: DispatchSourceHandler?)

	func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: DispatchSourceHandler?)

	func setRegistrationHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: DispatchSourceHandler?)

	func cancel()

	func resume()

	func suspend()

	var handle: UInt { get }

	var mask: UInt { get }

	var data: UInt { get }

	var isCancelled: Bool { get }
}

public protocol DispatchSourceUserDataAdd : DispatchSourceProtocol {
	func add(data: UInt)
}

public protocol DispatchSourceUserDataOr : DispatchSourceProtocol {
	func or(data: UInt)
}

public protocol DispatchSourceUserDataReplace : DispatchSourceProtocol {
	func replace(data: UInt)
}

#if HAVE_MACH
public protocol DispatchSourceMachSend : DispatchSourceProtocol {
	public var handle: mach_port_t { get }

	public var data: DispatchSource.MachSendEvent { get }

	public var mask: DispatchSource.MachSendEvent { get }
}
#endif

#if HAVE_MACH
public protocol DispatchSourceMachReceive : DispatchSourceProtocol {
	var handle: mach_port_t { get }
}
#endif

#if HAVE_MACH
public protocol DispatchSourceMemoryPressure : DispatchSourceProtocol {
	public var data: DispatchSource.MemoryPressureEvent { get }

	public var mask: DispatchSource.MemoryPressureEvent { get }
}
#endif

public protocol DispatchSourceRead : DispatchSourceProtocol {
}

public protocol DispatchSourceSignal : DispatchSourceProtocol {
}

public protocol DispatchSourceTimer : DispatchSourceProtocol {
	func scheduleOneshot(deadline: DispatchTime, leeway: DispatchTimeInterval)

	func scheduleOneshot(wallDeadline: DispatchWallTime, leeway: DispatchTimeInterval)

	func scheduleRepeating(deadline: DispatchTime, interval: DispatchTimeInterval, leeway: DispatchTimeInterval)

	func scheduleRepeating(deadline: DispatchTime, interval: Double, leeway: DispatchTimeInterval)

	func scheduleRepeating(wallDeadline: DispatchWallTime, interval: DispatchTimeInterval, leeway: DispatchTimeInterval)

	func scheduleRepeating(wallDeadline: DispatchWallTime, interval: Double, leeway: DispatchTimeInterval)
}

#if !os(Linux) && !os(Android)
public protocol DispatchSourceFileSystemObject : DispatchSourceProtocol {
	var handle: Int32 { get }

	var data: DispatchSource.FileSystemEvent { get }

	var mask: DispatchSource.FileSystemEvent { get }
}
#endif

public protocol DispatchSourceWrite : DispatchSourceProtocol {
}


internal enum _OSQoSClass : Int32  {
	case QOS_CLASS_USER_INTERACTIVE = 2
	case QOS_CLASS_DEFAULT = 0
	case QOS_CLASS_BACKGROUND = -2

	static var QOS_CLASS_UNSPECIFIED : _OSQoSClass { return .QOS_CLASS_DEFAULT }

	static var QOS_CLASS_UTILITY : _OSQoSClass { return .QOS_CLASS_BACKGROUND }

	static var QOS_CLASS_USER_INITIATED : _OSQoSClass { return .QOS_CLASS_USER_INTERACTIVE }
}

@_silgen_name("_swift_dispatch_release")
internal func _swift_dispatch_release(_ obj: dispatch_object_t) -> Void

@_silgen_name("_swift_dispatch_retain")
internal func _swift_dispatch_retain(_ obj: dispatch_object_t) -> Void
