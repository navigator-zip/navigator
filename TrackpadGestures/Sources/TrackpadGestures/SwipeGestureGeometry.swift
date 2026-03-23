import Foundation

struct GesturePoint: Equatable, Sendable {
	let x: Double
	let y: Double

	init(x: Double, y: Double) {
		self.x = x
		self.y = y
	}

	init(frame: TouchFrame) {
		self.init(x: frame.centroidX, y: frame.centroidY)
	}

	init(contact: TouchContact) {
		self.init(x: contact.normalizedX, y: contact.normalizedY)
	}

	func applyingExponentialSmoothing(
		to previous: GesturePoint?,
		alpha: Double
	) -> GesturePoint {
		guard let previous else { return self }
		return GesturePoint(
			x: alpha * x + (1 - alpha) * previous.x,
			y: alpha * y + (1 - alpha) * previous.y
		)
	}
}

struct GestureBoundingBox: Equatable, Sendable {
	let minX: Double
	let maxX: Double
	let minY: Double
	let maxY: Double

	var width: Double {
		maxX - minX
	}

	var height: Double {
		maxY - minY
	}

	static func from(contacts: [TouchContact]) -> GestureBoundingBox {
		guard let firstContact = contacts.first else {
			return GestureBoundingBox(minX: 0, maxX: 0, minY: 0, maxY: 0)
		}

		var minX = firstContact.normalizedX
		var maxX = firstContact.normalizedX
		var minY = firstContact.normalizedY
		var maxY = firstContact.normalizedY

		for contact in contacts.dropFirst() {
			minX = min(minX, contact.normalizedX)
			maxX = max(maxX, contact.normalizedX)
			minY = min(minY, contact.normalizedY)
			maxY = max(maxY, contact.normalizedY)
		}

		return GestureBoundingBox(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
	}
}

enum SwipeGestureGeometry {
	static func averagePairwiseDistance(for contacts: [TouchContact]) -> Double {
		guard contacts.count > 1 else { return 0 }

		var totalDistance = 0.0
		var pairCount = 0

		for leftIndex in contacts.indices {
			for rightIndex in contacts.indices where rightIndex > leftIndex {
				let left = GesturePoint(contact: contacts[leftIndex])
				let right = GesturePoint(contact: contacts[rightIndex])
				totalDistance += hypot(right.x - left.x, right.y - left.y)
				pairCount += 1
			}
		}

		return totalDistance / Double(pairCount)
	}

	static func angleFromHorizontalRadians(vx: Double, vy: Double) -> Double {
		atan2(abs(vy), max(abs(vx), .leastNonzeroMagnitude))
	}
}
