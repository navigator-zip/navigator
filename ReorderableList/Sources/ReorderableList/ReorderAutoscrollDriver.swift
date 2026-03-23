import AppKit

struct ReorderAutoscrollDriver {
	private let configuration: AutoscrollConfiguration
	private var lastTickTime: TimeInterval?

	init(configuration: AutoscrollConfiguration) {
		self.configuration = configuration
	}

	mutating func reset() {
		lastTickTime = nil
	}

	mutating func delta(
		pointerYInClipView: CGFloat,
		visibleHeight: CGFloat,
		now: TimeInterval
	) -> CGFloat? {
		guard visibleHeight > 0 else { return nil }
		let edgeZoneHeight = min(configuration.edgeZoneHeight, visibleHeight * 0.12)
		guard edgeZoneHeight > 0 else { return nil }

		let direction: CGFloat
		let penetration: CGFloat
		if pointerYInClipView >= 0, pointerYInClipView < edgeZoneHeight {
			direction = -1
			penetration = (edgeZoneHeight - pointerYInClipView) / edgeZoneHeight
		}
		else if pointerYInClipView <= visibleHeight, pointerYInClipView > visibleHeight - edgeZoneHeight {
			direction = 1
			penetration = (pointerYInClipView - (visibleHeight - edgeZoneHeight)) / edgeZoneHeight
		}
		else {
			lastTickTime = nil
			return nil
		}

		let clampedPenetration = min(max(penetration, 0), 1)
		let easedPenetration = clampedPenetration * clampedPenetration
		let speed = configuration.minimumSpeed
			+ ((configuration.maximumSpeed - configuration.minimumSpeed) * easedPenetration)
		let deltaTime = max(
			1 / 120,
			min(now - (lastTickTime ?? (now - (1 / 120))), 1 / 30)
		)
		lastTickTime = now
		return direction * speed * deltaTime
	}

	mutating func debugDelta(
		pointerYInClipView: CGFloat,
		visibleHeight: CGFloat,
		now: TimeInterval
	) -> CGFloat? {
		delta(
			pointerYInClipView: pointerYInClipView,
			visibleHeight: visibleHeight,
			now: now
		)
	}
}
