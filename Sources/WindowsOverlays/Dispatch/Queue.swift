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

// dispatch/queue.h

import CDispatch

public final class DispatchSpecificKey<T> {
	public init() {}
}

internal class _DispatchSpecificValue<T> {
	internal let value: T
	internal init(value: T) { self.value = value }
}

public extension DispatchQueue {
	public struct Attributes : OptionSet {
		public let rawValue: UInt64
		public init(rawValue: UInt64) { self.rawValue = rawValue }

		public static let concurrent = Attributes(rawValue: 1<<1)

		@available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
		public static let initiallyInactive = Attributes(rawValue: 1<<2)

		fileprivate func _attr() -> dispatch_queue_attr_t? {
			var attr: dispatch_queue_attr_t? = nil

			if self.contains(.concurrent) {
				attr = _swift_dispatch_queue_concurrent()
			}
			return attr
		}
	}

	public enum GlobalQueuePriority {
		@available(OSX, deprecated: 10.10, message: "Use qos attributes instead")
		@available(*, deprecated: 8.0, message: "Use qos attributes instead")
		case high

		@available(OSX, deprecated: 10.10, message: "Use qos attributes instead")
		@available(*, deprecated: 8.0, message: "Use qos attributes instead")
		case `default`

		@available(OSX, deprecated: 10.10, message: "Use qos attributes instead")
		@available(*, deprecated: 8.0, message: "Use qos attributes instead")
		case low

		@available(OSX, deprecated: 10.10, message: "Use qos attributes instead")
		@available(*, deprecated: 8.0, message: "Use qos attributes instead")
		case background

		internal var _translatedValue: Int {
			switch self {
			case .high: return 2 // DISPATCH_QUEUE_PRIORITY_HIGH
			case .default: return 0 // DISPATCH_QUEUE_PRIORITY_DEFAULT
			case .low: return -2 // DISPATCH_QUEUE_PRIORITY_LOW
			case .background: return Int(Int16.min) // DISPATCH_QUEUE_PRIORITY_BACKGROUND
			}
		}
	}

	public enum AutoreleaseFrequency {
		case inherit

		@available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
		case workItem

		@available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
		case never

		internal func _attr(attr: dispatch_queue_attr_t?) -> dispatch_queue_attr_t? {
			return attr
		}
	}

	public class func concurrentPerform(iterations: Int, execute work: (Int) -> Void) {
		_swift_dispatch_apply_current(iterations, work)
	}

	public static let main = DispatchQueue(label: "Main Queue")

	// public class var main: DispatchQueue {
	// 	return DispatchQueue(queue: _swift_dispatch_get_main_queue())
	// }

	public class func global(qos: DispatchQoS.QoSClass = .default) -> DispatchQueue {
		let queue = CDispatch.dispatch_get_global_queue(qos.rawValue.rawValue, 0)
		return DispatchQueue(queue: queue!)
	}

	public class func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? {
		let k = Unmanaged.passUnretained(key).toOpaque()
		if let p = CDispatch.dispatch_get_specific(k) {
			let v = Unmanaged<_DispatchSpecificValue<T>>
				.fromOpaque(p)
				.takeUnretainedValue()
			return v.value
		}
		return nil
	}

	public convenience init(
		label: String,
		qos: DispatchQoS = .unspecified,
		attributes: Attributes = [],
		autoreleaseFrequency: AutoreleaseFrequency = .inherit,
		target: DispatchQueue? = nil)
	{
		var attr = attributes._attr()
		if autoreleaseFrequency != .inherit {
			attr = autoreleaseFrequency._attr(attr: attr)
		}

		self.init(__label: label, attr: attr)
		if let tq = target { self.setTarget(queue: tq) }
	}

	public var label: String {
		return String(validatingUTF8: dispatch_queue_get_label(self.__wrapped))!
	}

	public func async(
		group: DispatchGroup? = nil,
		qos: DispatchQoS = .unspecified,
		flags: DispatchWorkItemFlags = [],
		execute work: @escaping @convention(block) () -> Void)
	{
		if group == nil && qos == .unspecified {
			// Fast-path route for the most common API usage
			if flags.isEmpty {
				CDispatch.dispatch_async(self.__wrapped, work)
				return
			} else if flags == .barrier {
				CDispatch.dispatch_barrier_async(self.__wrapped, work)
				return
			}
		}

		let block: @convention(block) () -> Void = work

		if let g = group {
			CDispatch.dispatch_group_async(g.__wrapped, self.__wrapped, block)
		} else {
			CDispatch.dispatch_async(self.__wrapped, block)
		}
	}

	private func _syncBarrier(block: () -> ()) {
		withoutActuallyEscaping(block) { block in
			CDispatch.dispatch_barrier_sync(self.__wrapped, block)
		}
	}

	private func _syncHelper<T>(
		fn: (() -> ()) -> (),
		execute work: () throws -> T,
		rescue: ((Swift.Error) throws -> (T))) rethrows -> T
	{
		var result: T?
		var error: Swift.Error?
		withoutActuallyEscaping(work) { _work in
			fn {
				do {
					result = try _work()
				} catch let e {
					error = e
				}
			}
		}
		if let e = error {
			return try rescue(e)
		} else {
			return result!
		}
	}

	public func sync<T>(execute work: () throws -> T) rethrows -> T {
		return try self._syncHelper(fn: sync, execute: work, rescue: { throw $0 })
	}

	public func sync<T>(flags: DispatchWorkItemFlags, execute work: () throws -> T) rethrows -> T {
		if flags == .barrier {
			return try self._syncHelper(fn: _syncBarrier, execute: work, rescue: { throw $0 })
		} else {
			return try self._syncHelper(fn: sync, execute: work, rescue: { throw $0 })
		}
	}

	public func asyncAfter(
		deadline: DispatchTime,
		qos: DispatchQoS = .unspecified,
		flags: DispatchWorkItemFlags = [],
		execute work: @escaping @convention(block) () -> Void)
	{
		CDispatch.dispatch_after(deadline.rawValue, self.__wrapped, work)
	}

	public func asyncAfter(
		wallDeadline: DispatchWallTime,
		qos: DispatchQoS = .unspecified,
		flags: DispatchWorkItemFlags = [],
		execute work: @escaping @convention(block) () -> Void)
	{
		CDispatch.dispatch_after(wallDeadline.rawValue, self.__wrapped, work)
	}

	public func getSpecific<T>(key: DispatchSpecificKey<T>) -> T? {
		let k = Unmanaged.passUnretained(key).toOpaque()
		if let p = dispatch_queue_get_specific(self.__wrapped, k) {
			let v = Unmanaged<_DispatchSpecificValue<T>>
				.fromOpaque(p)
				.takeUnretainedValue()
			return v.value
		}
		return nil
	}

	public func setSpecific<T>(key: DispatchSpecificKey<T>, value: T?) {
		let k = Unmanaged.passUnretained(key).toOpaque()
		let v = value.flatMap { _DispatchSpecificValue(value: $0) }
		let p = v.flatMap { Unmanaged.passRetained($0).toOpaque() }
		dispatch_queue_set_specific(self.__wrapped, k, p, _destructDispatchSpecificValue)
	}

	#if os(Android)
	@_silgen_name("_dispatch_install_thread_detach_callback")
	private static func _dispatch_install_thread_detach_callback(_ cb: @escaping @convention(c) () -> Void)

	public static func setThreadDetachCallback(_ cb: @escaping @convention(c) () -> Void) {
		_dispatch_install_thread_detach_callback(cb)
	}
	#endif
}

private func _destructDispatchSpecificValue(ptr: UnsafeMutableRawPointer?) {
	if let p = ptr {
		Unmanaged<AnyObject>.fromOpaque(p).release()
	}
}

@_silgen_name("_swift_dispatch_queue_concurrent")
internal func _swift_dispatch_queue_concurrent() -> dispatch_queue_attr_t

@_silgen_name("_swift_dispatch_get_main_queue")
internal func _swift_dispatch_get_main_queue() -> dispatch_queue_t

@_silgen_name("_swift_dispatch_apply_current")
internal func _swift_dispatch_apply_current(_ iterations: Int, _ block: @convention(block) (Int) -> Void)
