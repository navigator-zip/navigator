import Foundation
import ModelKit

private enum ChromiumHistoryConstants {
	static let historyFileName = "History"
	static let historyOutputChunkSize = 64 * 1024
	static let sqliteExecutablePath = "/usr/bin/sqlite3"
	static let historyQuery = """
	SELECT json_object(
		'id', id,
		'url', url,
		'title', title,
		'last_visit_time', last_visit_time
	)
	FROM urls
	WHERE url IS NOT NULL AND TRIM(url) != '' AND last_visit_time > 0
	ORDER BY last_visit_time DESC;
	"""
}

struct ChromiumHistoryReader {
	func loadHistoryEntries(
		source: BrowserImportSource,
		profileURL: URL
	) throws -> [ImportedHistoryEntry] {
		let historyURL = profileURL.appendingPathComponent(
			ChromiumHistoryConstants.historyFileName,
			isDirectory: false
		)
		guard FileManager.default.fileExists(atPath: historyURL.path) else {
			return []
		}

		let temporaryCopyURL = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString, isDirectory: false)

		do {
			try FileManager.default.copyItem(at: historyURL, to: temporaryCopyURL)
			defer {
				try? FileManager.default.removeItem(at: temporaryCopyURL)
			}

			return try queryHistoryEntries(at: temporaryCopyURL, source: source)
		}
		catch let error as BrowserImportError {
			throw error
		}
		catch {
			throw BrowserImportError.readFailed(historyURL)
		}
	}

	private func queryHistoryEntries(
		at databaseURL: URL,
		source: BrowserImportSource
	) throws -> [ImportedHistoryEntry] {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: ChromiumHistoryConstants.sqliteExecutablePath)
		process.arguments = [
			"-readonly",
			databaseURL.path,
			ChromiumHistoryConstants.historyQuery,
		]

		let outputPipe = Pipe()
		let errorPipe = Pipe()
		process.standardOutput = outputPipe
		process.standardError = errorPipe

		do {
			try process.run()
		}
		catch {
			throw BrowserImportError.readFailed(databaseURL)
		}

		defer {
			if process.isRunning {
				process.terminate()
				process.waitUntilExit()
			}
		}

		let historyEntries = try readHistoryEntries(
			from: outputPipe.fileHandleForReading,
			source: source
		)
		process.waitUntilExit()
		let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
		guard process.terminationStatus == 0 else {
			let reason = String(data: errorData, encoding: .utf8)?
				.trimmingCharacters(in: .whitespacesAndNewlines)
				.nonEmpty
				?? "sqlite3 exited with status \(process.terminationStatus)"
			throw BrowserImportError.parseFailed(source, reason: reason)
		}

		return historyEntries
	}

	private func readHistoryEntries(
		from fileHandle: FileHandle,
		source: BrowserImportSource
	) throws -> [ImportedHistoryEntry] {
		var historyEntries = [ImportedHistoryEntry]()
		var bufferedData = Data()

		while true {
			let chunk = fileHandle.readData(ofLength: ChromiumHistoryConstants.historyOutputChunkSize)
			if chunk.isEmpty {
				break
			}
			bufferedData.append(chunk)
			try decodeBufferedHistoryLines(
				from: &bufferedData,
				source: source,
				into: &historyEntries
			)
		}

		if bufferedData.isEmpty == false {
			try decodeHistoryLine(
				bufferedData,
				source: source,
				into: &historyEntries
			)
		}

		return historyEntries
	}

	private func decodeBufferedHistoryLines(
		from bufferedData: inout Data,
		source: BrowserImportSource,
		into historyEntries: inout [ImportedHistoryEntry]
	) throws {
		while let newlineIndex = bufferedData.firstIndex(of: .newLine) {
			let lineData = Data(bufferedData[..<newlineIndex])
			bufferedData.removeSubrange(...newlineIndex)
			try decodeHistoryLine(
				lineData,
				source: source,
				into: &historyEntries
			)
		}
	}

	private func decodeHistoryLine(
		_ lineData: Data,
		source: BrowserImportSource,
		into historyEntries: inout [ImportedHistoryEntry]
	) throws {
		let normalizedLineData = lineData.trimmingTrailingNewlineAndCarriageReturn()
		guard normalizedLineData.isEmpty == false else {
			return
		}

		let row: ChromiumHistoryRow
		do {
			row = try JSONDecoder().decode(
				ChromiumHistoryRow.self,
				from: normalizedLineData
			)
		}
		catch {
			throw BrowserImportError.parseFailed(
				source,
				reason: "Invalid Chromium history output"
			)
		}

		if let historyEntry = makeImportedHistoryEntry(from: row) {
			historyEntries.append(historyEntry)
		}
	}

	private func makeImportedHistoryEntry(from row: ChromiumHistoryRow) -> ImportedHistoryEntry? {
		let normalizedURL = row.url.trimmingCharacters(in: .whitespacesAndNewlines)
		guard normalizedURL.isEmpty == false,
		      let visitedAt = ChromiumTimestampConverter.date(fromWebKitMicroseconds: row.lastVisitTime) else {
			return nil
		}

		let title = row.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
		return ImportedHistoryEntry(
			id: row.id.map(String.init) ?? normalizedURL,
			title: title,
			url: normalizedURL,
			visitedAt: visitedAt
		)
	}
}

private struct ChromiumHistoryRow: Decodable {
	let id: Int64?
	let url: String
	let title: String?
	let lastVisitTime: Int64

	private enum CodingKeys: String, CodingKey {
		case id
		case url
		case title
		case lastVisitTime = "last_visit_time"
	}
}

private extension String {
	var nonEmpty: String? {
		isEmpty ? nil : self
	}
}

private extension UInt8 {
	static let carriageReturn = UInt8(ascii: "\r")
	static let newLine = UInt8(ascii: "\n")
}

private extension Data {
	func trimmingTrailingNewlineAndCarriageReturn() -> Data {
		var trimmedData = self
		while let lastByte = trimmedData.last,
		      lastByte == .newLine || lastByte == .carriageReturn {
			trimmedData.removeLast()
		}
		return trimmedData
	}
}
