import Foundation

enum ChromiumTimestampConverter {
	private static let secondsBetween1601And1970: TimeInterval = 11_644_473_600
	private static let microsecondsPerSecond: TimeInterval = 1_000_000

	static func date(fromWebKitMicroseconds value: Int64) -> Date? {
		guard value > 0 else {
			return nil
		}

		let secondsSinceUnixEpoch = (TimeInterval(value) / microsecondsPerSecond) - secondsBetween1601And1970
		return Date(timeIntervalSince1970: secondsSinceUnixEpoch)
	}
}
