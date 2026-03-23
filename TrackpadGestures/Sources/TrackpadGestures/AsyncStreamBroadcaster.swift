import Foundation

final class AsyncStreamBroadcaster<Element: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private let replayLimit: Int
	private let bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy
	private var continuations = [UUID: AsyncStream<Element>.Continuation]()
	private var replayBuffer = [Element]()

	init(
		replayLimit: Int = 0,
		bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(16)
	) {
		self.replayLimit = max(0, replayLimit)
		self.bufferingPolicy = bufferingPolicy
	}

	func stream() -> AsyncStream<Element> {
		AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
			let id = UUID()
			let replayedValues = storeContinuation(continuation, id: id)
			for value in replayedValues {
				continuation.yield(value)
			}
			continuation.onTermination = { [weak self] _ in
				self?.removeContinuation(id: id)
			}
		}
	}

	func yield(_ value: Element) {
		for continuation in snapshotContinuations(storing: value) {
			continuation.yield(value)
		}
	}

	private func storeContinuation(_ continuation: AsyncStream<Element>.Continuation, id: UUID) -> [Element] {
		lock.lock()
		continuations[id] = continuation
		let replayedValues = replayBuffer
		lock.unlock()
		return replayedValues
	}

	private func snapshotContinuations(storing value: Element) -> [AsyncStream<Element>.Continuation] {
		lock.lock()
		if replayLimit > 0 {
			replayBuffer.append(value)
			if replayBuffer.count > replayLimit {
				replayBuffer.removeFirst(replayBuffer.count - replayLimit)
			}
		}
		let snapshot = Array(continuations.values)
		lock.unlock()
		return snapshot
	}

	private func removeContinuation(id: UUID) {
		lock.lock()
		continuations.removeValue(forKey: id)
		lock.unlock()
	}
}
