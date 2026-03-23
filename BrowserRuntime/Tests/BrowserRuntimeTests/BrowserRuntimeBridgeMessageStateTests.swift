import AppIntents
@testable import BrowserRuntime
import ModelKit
import XCTest

@MainActor
final class BrowserRuntimeBridgeMessageStateTests: XCTestCase {
	private func pictureInPictureState(
		sequenceNumber: Int = 1,
		event: String = "bootstrap",
		location: String? = "https://navigator.test",
		isCurrentWindowPictureInPicture: Bool = false,
		isVideoPictureInPictureActive: Bool = false,
		isVideoPictureInPictureSupported: Bool? = true,
		isDocumentPictureInPictureSupported: Bool = true,
		isDocumentPictureInPictureWindowOpen: Bool = false,
		currentWindowInnerWidth: Int? = 1280,
		currentWindowInnerHeight: Int? = 720,
		videoPictureInPictureWindowWidth: Int? = nil,
		videoPictureInPictureWindowHeight: Int? = nil,
		documentPictureInPictureWindowWidth: Int? = nil,
		documentPictureInPictureWindowHeight: Int? = nil,
		activeVideo: BrowserRuntimePictureInPictureState.ActiveVideo? = nil,
		videoElementCount: Int? = 1,
		errorDescription: String? = nil
	) -> BrowserRuntimePictureInPictureState {
		BrowserRuntimePictureInPictureState(
			sequenceNumber: sequenceNumber,
			event: event,
			location: location,
			isCurrentWindowPictureInPicture: isCurrentWindowPictureInPicture,
			isVideoPictureInPictureActive: isVideoPictureInPictureActive,
			isVideoPictureInPictureSupported: isVideoPictureInPictureSupported,
			isDocumentPictureInPictureSupported: isDocumentPictureInPictureSupported,
			isDocumentPictureInPictureWindowOpen: isDocumentPictureInPictureWindowOpen,
			currentWindowInnerWidth: currentWindowInnerWidth,
			currentWindowInnerHeight: currentWindowInnerHeight,
			videoPictureInPictureWindowWidth: videoPictureInPictureWindowWidth,
			videoPictureInPictureWindowHeight: videoPictureInPictureWindowHeight,
			documentPictureInPictureWindowWidth: documentPictureInPictureWindowWidth,
			documentPictureInPictureWindowHeight: documentPictureInPictureWindowHeight,
			activeVideo: activeVideo,
			videoElementCount: videoElementCount,
			errorDescription: errorDescription
		)
	}

	func testAddressMessagesDeduplicatePerBrowser() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 1
		var deliveredMessages = [String]()
		state.setHandler({ message in
			deliveredMessages.append(message)
		}, for: browserKey, kind: .address)

		state.consumeMessage("https://navigator.zip", for: browserKey, kind: .address)?("https://navigator.zip")
		state.consumeMessage("https://navigator.zip", for: browserKey, kind: .address)?("https://navigator.zip")
		state.consumeMessage("https://swift.org", for: browserKey, kind: .address)?("https://swift.org")

		XCTAssertEqual(deliveredMessages, ["https://navigator.zip", "https://swift.org"])
	}

	func testFaviconMessagesUseIndependentDeduplicationState() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 2
		var deliveredMessages = [String]()
		state.setHandler({ message in
			deliveredMessages.append("address:\(message)")
		}, for: browserKey, kind: .address)
		state.setHandler({ message in
			deliveredMessages.append("favicon:\(message)")
		}, for: browserKey, kind: .faviconURL)

		state.consumeMessage("https://example.com/shared", for: browserKey, kind: .address)?("https://example.com/shared")
		state.consumeMessage("https://example.com/shared", for: browserKey, kind: .faviconURL)?("https://example.com/shared")

		XCTAssertEqual(
			deliveredMessages,
			[
				"address:https://example.com/shared",
				"favicon:https://example.com/shared",
			]
		)
	}

	func testTitleMessagesUseIndependentDeduplicationState() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 7
		var deliveredMessages = [String]()
		state.setHandler({ message in
			deliveredMessages.append("address:\(message)")
		}, for: browserKey, kind: .address)
		state.setHandler({ message in
			deliveredMessages.append("title:\(message)")
		}, for: browserKey, kind: .title)

		state.consumeMessage("https://example.com/shared", for: browserKey, kind: .address)?("https://example.com/shared")
		state.consumeMessage("Example Site", for: browserKey, kind: .title)?("Example Site")
		state.consumeMessage("Example Site", for: browserKey, kind: .title)?("Example Site")

		XCTAssertEqual(
			deliveredMessages,
			[
				"address:https://example.com/shared",
				"title:Example Site",
			]
		)
		XCTAssertEqual(state.lastMessage(for: browserKey, kind: .title), "Example Site")
	}

	func testTitleMessagesDeduplicateIndependentlyPerBrowser() {
		var state = BrowserRuntimeBridgeMessageState()
		let firstBrowserKey: UInt64 = 8
		let secondBrowserKey: UInt64 = 9
		var deliveredMessages = [String]()
		state.setHandler({ message in
			deliveredMessages.append("first:\(message)")
		}, for: firstBrowserKey, kind: .title)
		state.setHandler({ message in
			deliveredMessages.append("second:\(message)")
		}, for: secondBrowserKey, kind: .title)

		state.consumeMessage("Navigator", for: firstBrowserKey, kind: .title)?("Navigator")
		state.consumeMessage("Navigator", for: firstBrowserKey, kind: .title)?("Navigator")
		state.consumeMessage("Navigator", for: secondBrowserKey, kind: .title)?("Navigator")

		XCTAssertEqual(
			deliveredMessages,
			[
				"first:Navigator",
				"second:Navigator",
			]
		)
	}

	func testResettingTitleHandlerClearsDedupStateForSameMessage() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 10
		var firstPassMessages = [String]()
		var secondPassMessages = [String]()
		state.setHandler({ message in
			firstPassMessages.append(message)
		}, for: browserKey, kind: .title)

		state.consumeMessage("Navigator", for: browserKey, kind: .title)?("Navigator")
		state.setHandler(nil, for: browserKey, kind: .title)
		state.setHandler({ message in
			secondPassMessages.append(message)
		}, for: browserKey, kind: .title)
		state.consumeMessage("Navigator", for: browserKey, kind: .title)?("Navigator")

		XCTAssertEqual(firstPassMessages, ["Navigator"])
		XCTAssertEqual(secondPassMessages, ["Navigator"])
	}

	func testClearRemovesHandlersAndLastMessages() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 3
		var deliveryCount = 0
		state.setHandler({ _ in
			deliveryCount += 1
		}, for: browserKey, kind: .address)
		state.setHandler({ _ in
			deliveryCount += 1
		}, for: browserKey, kind: .title)
		state.setHandler({ _ in
			deliveryCount += 1
		}, for: browserKey, kind: .faviconURL)

		state.consumeMessage("https://navigator.zip", for: browserKey, kind: .address)?("https://navigator.zip")
		state.consumeMessage("Navigator", for: browserKey, kind: .title)?("Navigator")
		state.consumeMessage("https://navigator.zip/favicon.ico", for: browserKey, kind: .faviconURL)?(
			"https://navigator.zip/favicon.ico"
		)
		state.clear(for: browserKey)

		XCTAssertNil(state.lastMessage(for: browserKey, kind: .address))
		XCTAssertNil(state.lastMessage(for: browserKey, kind: .title))
		XCTAssertNil(state.lastMessage(for: browserKey, kind: .faviconURL))
		XCTAssertNil(state.consumeMessage("https://navigator.zip", for: browserKey, kind: .address))
		XCTAssertNil(state.consumeMessage("Navigator", for: browserKey, kind: .title))
		XCTAssertNil(state.consumeMessage("https://navigator.zip/favicon.ico", for: browserKey, kind: .faviconURL))
		XCTAssertEqual(deliveryCount, 3)
	}

	func testPictureInPictureStateMessagesDeduplicatePerBrowser() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 4
		let initialState = pictureInPictureState(sequenceNumber: 1)
		let repeatedState = pictureInPictureState(sequenceNumber: 1)
		let updatedState = pictureInPictureState(
			sequenceNumber: 2,
			event: "video-enter",
			isCurrentWindowPictureInPicture: true,
			isVideoPictureInPictureActive: true,
			videoPictureInPictureWindowWidth: 360,
			videoPictureInPictureWindowHeight: 202
		)
		var deliveredStates = [BrowserRuntimePictureInPictureState]()
		state.setPictureInPictureStateHandler({ state in
			deliveredStates.append(state)
		}, for: browserKey)

		state.consumePictureInPictureState(initialState, for: browserKey)?(initialState)
		state.consumePictureInPictureState(repeatedState, for: browserKey)?(repeatedState)
		state.consumePictureInPictureState(updatedState, for: browserKey)?(updatedState)

		XCTAssertEqual(deliveredStates, [initialState, updatedState])
		XCTAssertEqual(state.lastPictureInPictureState(for: browserKey), updatedState)
	}

	func testPictureInPictureStateUsesIndependentDeduplicationState() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 5
		let pictureInPictureState = pictureInPictureState(
			sequenceNumber: 1,
			event: "document-open",
			location: "https://example.com/shared",
			isDocumentPictureInPictureWindowOpen: true,
			documentPictureInPictureWindowWidth: 420,
			documentPictureInPictureWindowHeight: 240
		)
		var deliveredMessages = [String]()
		state.setHandler({ message in
			deliveredMessages.append("address:\(message)")
		}, for: browserKey, kind: .address)
		state.setPictureInPictureStateHandler({ state in
			deliveredMessages.append("pip:\(state.location ?? "")#\(state.sequenceNumber)")
		}, for: browserKey)

		state.consumeMessage("https://example.com/shared", for: browserKey, kind: .address)?("https://example.com/shared")
		state.consumePictureInPictureState(pictureInPictureState, for: browserKey)?(pictureInPictureState)

		XCTAssertEqual(
			deliveredMessages,
			[
				"address:https://example.com/shared",
				"pip:https://example.com/shared#1",
			]
		)
	}

	func testClearRemovesPictureInPictureHandlersAndLastState() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 6
		let pictureInPictureState = pictureInPictureState(sequenceNumber: 1, event: "bootstrap")
		var deliveryCount = 0
		state.setPictureInPictureStateHandler({ _ in
			deliveryCount += 1
		}, for: browserKey)

		state.consumePictureInPictureState(pictureInPictureState, for: browserKey)?(pictureInPictureState)
		state.clear(for: browserKey)

		XCTAssertNil(state.lastPictureInPictureState(for: browserKey))
		XCTAssertNil(state.consumePictureInPictureState(pictureInPictureState, for: browserKey))
		XCTAssertEqual(deliveryCount, 1)
	}

	func testOpenURLInTabEventParsesPayload() {
		let payload = #"{"url":"https://navigator.test/new-tab","activatesTab":false}"#

		let event = BrowserRuntimeOpenURLInTabEvent.from(json: payload)

		XCTAssertEqual(
			event,
			.init(url: "https://navigator.test/new-tab", activatesTab: false)
		)
	}

	func testOpenURLInTabEventsDeliverWithoutDeduplication() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 11
		let event = BrowserRuntimeOpenURLInTabEvent(
			url: "https://navigator.test/new-tab",
			activatesTab: false
		)
		var deliveredEvents = [BrowserRuntimeOpenURLInTabEvent]()
		state.setOpenURLInTabHandler({ deliveredEvents.append($0) }, for: browserKey)

		state.consumeOpenURLInTabEvent(event, for: browserKey)?(event)
		state.consumeOpenURLInTabEvent(event, for: browserKey)?(event)

		XCTAssertEqual(deliveredEvents, [event, event])
	}

	func testPictureInPictureStateParsesExtendedPayload() {
		let payload = """
		{
		  "sequenceNumber": 7,
		  "event": "video-request-resolved",
		  "location": "https://navigator.test/player",
		  "isCurrentWindowPictureInPicture": true,
		  "isVideoPictureInPictureActive": true,
		  "isVideoPictureInPictureSupported": true,
		  "isDocumentPictureInPictureSupported": true,
		  "isDocumentPictureInPictureWindowOpen": false,
		  "currentWindowInnerWidth": 480,
		  "currentWindowInnerHeight": 270,
		  "videoPictureInPictureWindowWidth": 480,
		  "videoPictureInPictureWindowHeight": 270,
		  "documentPictureInPictureWindowWidth": null,
		  "documentPictureInPictureWindowHeight": null,
		  "activeVideo": {
		    "currentSourceURL": "https://cdn.navigator.test/video.mp4",
		    "currentTimeSeconds": 12.5,
		    "durationSeconds": 48.0,
		    "playbackRate": 1,
		    "isPaused": false,
		    "isEnded": false,
		    "videoWidth": 1920,
		    "videoHeight": 1080
		  },
		  "videoElementCount": 3,
		  "errorDescription": null
		}
		"""

		let state = BrowserRuntimePictureInPictureState.from(json: payload)

		XCTAssertNotNil(state)
		XCTAssertEqual(state?.sequenceNumber, 7)
		XCTAssertEqual(state?.event, "video-request-resolved")
		XCTAssertEqual(state?.currentWindowInnerWidth, 480)
		XCTAssertEqual(state?.videoPictureInPictureWindowHeight, 270)
		XCTAssertEqual(state?.activeVideo?.currentSourceURL, "https://cdn.navigator.test/video.mp4")
		XCTAssertEqual(state?.activeVideo?.videoWidth, 1920)
	}

	func testPictureInPictureStateDropsInvalidJSON() {
		XCTAssertNil(BrowserRuntimePictureInPictureState.from(json: #"{"event":"missing-sequence"}"#))
	}

	func testTopLevelNativeContentMessagesDeduplicatePerBrowser() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 11
		let content = BrowserRuntimeTopLevelNativeContent(
			kind: .image,
			url: "https://navigator.test/image.png",
			pathExtension: "png",
			uniformTypeIdentifier: "public.png"
		)
		let updatedContent = BrowserRuntimeTopLevelNativeContent(
			kind: .animatedImage,
			url: "https://navigator.test/animated.gif",
			pathExtension: "gif",
			uniformTypeIdentifier: "com.compuserve.gif"
		)
		var deliveredContent = [BrowserRuntimeTopLevelNativeContent]()
		state.setTopLevelNativeContentHandler({ content in
			deliveredContent.append(content)
		}, for: browserKey)

		state.consumeTopLevelNativeContent(content, for: browserKey)?(content)
		state.consumeTopLevelNativeContent(content, for: browserKey)?(content)
		state.consumeTopLevelNativeContent(updatedContent, for: browserKey)?(updatedContent)

		XCTAssertEqual(deliveredContent, [content, updatedContent])
		XCTAssertEqual(state.lastTopLevelNativeContent(for: browserKey), updatedContent)
	}

	func testTopLevelNativeContentParsesPayload() {
		let payload = """
		{
		  "kind": "hlsStream",
		  "url": "https://navigator.test/live.m3u8",
		  "pathExtension": "m3u8",
		  "uniformTypeIdentifier": "public.m3u8-playlist"
		}
		"""

		let content = BrowserRuntimeTopLevelNativeContent.from(json: payload)

		XCTAssertEqual(content?.kind, .hlsStream)
		XCTAssertEqual(content?.url, "https://navigator.test/live.m3u8")
		XCTAssertEqual(content?.pathExtension, "m3u8")
		XCTAssertEqual(content?.uniformTypeIdentifier, "public.m3u8-playlist")
	}

	func testRenderProcessTerminationMessagesDeduplicatePerBrowser() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 12
		let termination = BrowserRuntimeRenderProcessTermination(
			status: 2,
			errorCode: 9,
			errorDescription: "Renderer crashed"
		)
		var deliveredTerminations = [BrowserRuntimeRenderProcessTermination]()
		state.setRenderProcessTerminationHandler({ termination in
			deliveredTerminations.append(termination)
		}, for: browserKey)

		state.consumeRenderProcessTermination(termination, for: browserKey)?(termination)
		state.consumeRenderProcessTermination(termination, for: browserKey)?(termination)

		XCTAssertEqual(deliveredTerminations, [termination])
		XCTAssertEqual(state.lastRenderProcessTermination(for: browserKey), termination)
	}

	func testMainFrameNavigationEventsDeliverWithoutDeduplication() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 13
		let event = BrowserRuntimeMainFrameNavigationEvent(
			url: "https://accounts.google.com/o/oauth2/v2/auth",
			userGesture: false,
			isRedirect: true
		)
		var deliveredEvents = [BrowserRuntimeMainFrameNavigationEvent]()
		state.setMainFrameNavigationHandler({ event in
			deliveredEvents.append(event)
		}, for: browserKey)

		state.consumeMainFrameNavigationEvent(event, for: browserKey)?(event)
		state.consumeMainFrameNavigationEvent(event, for: browserKey)?(event)

		XCTAssertEqual(deliveredEvents, [event, event])
	}

	func testCameraRoutingEventsDeliverWithoutDeduplication() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 14
		let event = BrowserCameraRoutingEvent(
			event: .trackStarted,
			activeManagedTrackCount: 1,
			managedTrackID: "track-1",
			managedDeviceID: "navigator-camera-managed-output",
			preferredFilterPreset: .folia
		)
		var deliveredEvents = [BrowserCameraRoutingEvent]()
		state.setCameraRoutingEventHandler({ deliveredEvents.append($0) }, for: browserKey)

		state.consumeCameraRoutingEvent(event, for: browserKey)?(event)
		state.consumeCameraRoutingEvent(event, for: browserKey)?(event)

		XCTAssertEqual(deliveredEvents, [event, event])
	}

	func testClearRemovesCameraRoutingHandlers() {
		var state = BrowserRuntimeBridgeMessageState()
		let browserKey: UInt64 = 15
		let event = BrowserCameraRoutingEvent(
			event: .trackStopped,
			activeManagedTrackCount: 0
		)
		var deliveryCount = 0
		state.setCameraRoutingEventHandler({ _ in
			deliveryCount += 1
		}, for: browserKey)

		state.consumeCameraRoutingEvent(event, for: browserKey)?(event)
		state.clear(for: browserKey)

		XCTAssertNil(state.consumeCameraRoutingEvent(event, for: browserKey))
		XCTAssertEqual(deliveryCount, 1)
	}
}
