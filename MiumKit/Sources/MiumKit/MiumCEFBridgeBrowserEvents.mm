#import "MiumCEFBridgeBrowserEvents.h"

#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalBrowserMessagingSupport.h"
#include "MiumCEFBridgeInternalBrowserPayloadSupport.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeNative.h"
#include "Tracing.h"

namespace {

CefStringUserFreeUTF16Free loadedFrameworkUserFreeStringDestructor() {
  CefStateLockGuard lock;
  if (!gFrameworkLoaded || gCefApi.frameworkHandle == nullptr) {
    return nullptr;
  }
  return gCefApi.userfreeFree;
}

} // namespace

NSString* NSStringFromCEFString(const cef_string_t* source) {
  if (source == nullptr || source->str == nullptr || source->length <= 0) {
    return @"";
  }
  return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar*>(source->str)
                                      length:static_cast<NSUInteger>(source->length)];
}

NSString* NSStringFromCEFUserFreeString(cef_string_userfree_t source) {
  NSString* string = NSStringFromCEFString(source);
  if (source != nullptr) {
    const CefStringUserFreeUTF16Free userfreeFree = loadedFrameworkUserFreeStringDestructor();
    if (userfreeFree != nullptr) {
      userfreeFree(source);
    }
  }
  return string;
}

std::string stringFromCEFUserFreeString(cef_string_userfree_t source) {
  return stringFromNSStringUTF8(NSStringFromCEFUserFreeString(source));
}

std::string stringFromNSStringUTF8(NSString* source) {
  if (source == nil) {
    return std::string();
  }
  const char* bytes = source.UTF8String;
  return bytes == nullptr ? std::string() : std::string(bytes);
}

void emitTopLevelNativeContentForBrowser(
  cef_browser_t* browser,
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind kind,
  NSString* pathExtension,
  NSString* uniformTypeIdentifier
) {
  const std::string payload = topLevelNativeContentPayloadString(
    urlString,
    kind,
    pathExtension,
    uniformTypeIdentifier
  );
  emitBrowserMessageForMappedBrowser(browser, MiumCEFTopLevelNativeContentChannel, payload.c_str());
}

void emitBrowserMessageForMappedBrowser(
  cef_browser_t* browser,
  const char* channel,
  const char* message
) {
  miumCefTrace(
    "browser-events",
    "BrowserMessage entered browser=%p channel=%s\n",
    static_cast<void*>(browser),
    channel == nullptr ? "" : channel
  );
  if (browser == nullptr || channel == nullptr) {
    miumCefTrace("browser-events", "BrowserMessage missing browser or channel, ignoring\n");
    return;
  }

  const uint64_t browserId = miumCEFNativeBrowserIdFromNativeBrowser(browser);
  if (browserId == 0) {
    miumCefTrace("browser-events", "BrowserMessage no browserId mapping, ignoring\n");
    return;
  }

  const char* resolvedMessage = message == nullptr ? "" : message;
  miumCefTrace(
    "browser-events",
    "BrowserMessage mapped browserId=%llu channel=%s message=%s\n",
    static_cast<unsigned long long>(browserId),
    channel,
    resolvedMessage
  );
  miumNativeCEFEmitMessage(
    reinterpret_cast<MiumCEFBrowserHandle>(reinterpret_cast<void*>(static_cast<uintptr_t>(browserId))),
    channel,
    resolvedMessage
  );
}

std::string renderProcessTerminationPayloadString(
  cef_termination_status_t status,
  int errorCode,
  const cef_string_t* errorString
) {
  NSMutableDictionary<NSString*, id>* payload = [NSMutableDictionary dictionaryWithCapacity:3];
  payload[@"status"] = @(static_cast<int>(status));
  payload[@"errorCode"] = @(errorCode);
  payload[@"errorDescription"] = NSStringFromCEFString(errorString);

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
  if (jsonData == nil || error != nil) {
    return std::string("{\"status\":0,\"errorCode\":0,\"errorDescription\":\"\"}");
  }
  return std::string(static_cast<const char*>(jsonData.bytes), jsonData.length);
}

std::string mainFrameNavigationPayloadString(NSString* urlString, int userGesture, int isRedirect) {
  NSMutableDictionary<NSString*, id>* payload = [NSMutableDictionary dictionaryWithCapacity:3];
  payload[@"url"] = urlString ?: @"";
  payload[@"userGesture"] = @(userGesture != 0);
  payload[@"isRedirect"] = @(isRedirect != 0);

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
  if (jsonData == nil || error != nil) {
    return std::string("{\"url\":\"\",\"userGesture\":false,\"isRedirect\":false}");
  }
  return std::string(static_cast<const char*>(jsonData.bytes), jsonData.length);
}

std::string openURLInTabPayloadString(NSString* urlString, bool activatesTab) {
  NSMutableDictionary<NSString*, id>* payload = [NSMutableDictionary dictionaryWithCapacity:2];
  payload[@"url"] = urlString ?: @"";
  payload[@"activatesTab"] = @(activatesTab);

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
  if (jsonData == nil || error != nil) {
    return std::string("{\"url\":\"\",\"activatesTab\":true}");
  }
  return std::string(static_cast<const char*>(jsonData.bytes), jsonData.length);
}

std::string normalizedPermissionOriginString(NSString* rawURLString) {
  if (rawURLString == nil || rawURLString.length == 0) {
    return std::string();
  }

  NSURLComponents* components = [NSURLComponents componentsWithString:rawURLString];
  NSString* scheme = components.scheme.lowercaseString;
  NSString* host = components.host.lowercaseString;
  if (scheme.length == 0 || host.length == 0) {
    return stringFromNSStringUTF8(rawURLString);
  }

  NSMutableString* origin = [NSMutableString stringWithFormat:@"%@://%@", scheme, host];
  if (components.port != nil) {
    [origin appendFormat:@":%@", components.port];
  }
  return stringFromNSStringUTF8(origin);
}

std::string topLevelPermissionOriginString(cef_browser_t* browser) {
  if (browser == nullptr || browser->get_main_frame == nullptr) {
    return std::string();
  }
  cef_frame_t* mainFrame = browser->get_main_frame(browser);
  if (mainFrame == nullptr) {
    return std::string();
  }

  cef_string_userfree_t frameURL = mainFrame->get_url == nullptr ? nullptr : mainFrame->get_url(mainFrame);
  NSString* urlString = NSStringFromCEFUserFreeString(frameURL);
  CefRef<cef_frame_t>::adopt(mainFrame).reset();
  return normalizedPermissionOriginString(urlString);
}

std::string frameIdentifierString(cef_frame_t* frame) {
  if (frame == nullptr || frame->get_identifier == nullptr) {
    return std::string();
  }
  cef_string_userfree_t identifier = frame->get_identifier(frame);
  NSString* identifierString = NSStringFromCEFUserFreeString(identifier);
  return stringFromNSStringUTF8(identifierString);
}

const std::string& pictureInPictureObserverScript() {
  static const std::string script = R"JS((function() {
  if (typeof window === "undefined" || typeof document === "undefined") {
    return;
  }
  if (window.__miumPiPObserverInstalled) {
    return;
  }
  window.__miumPiPObserverInstalled = true;

  var promptMessage = "__miumPictureInPictureStateChange__";
  var boundVideos = typeof WeakSet === "function" ? new WeakSet() : null;
  var boundVideoPiPWindow = null;
  var boundPiPWindow = null;
  var lastDocumentWindowOpen = null;
  var nextSequenceNumber = 1;

  function optionalString(value) {
    return typeof value === "string" && value.length > 0 ? value : null;
  }

  function optionalNumber(value) {
    return typeof value === "number" && isFinite(value) ? value : null;
  }

  function optionalInteger(value) {
    return typeof value === "number" && isFinite(value) ? Math.trunc(value) : null;
  }

  function activeVideo() {
    return document.pictureInPictureElement instanceof HTMLVideoElement ? document.pictureInPictureElement : null;
  }

  function serializeVideo(video) {
    if (!(video instanceof HTMLVideoElement)) {
      return null;
    }
    return {
      currentSourceURL: optionalString(video.currentSrc || video.src || ""),
      currentTimeSeconds: optionalNumber(video.currentTime),
      durationSeconds: optionalNumber(video.duration),
      playbackRate: optionalNumber(video.playbackRate),
      paused: !!video.paused,
      ended: !!video.ended,
      muted: !!video.muted,
      volume: optionalNumber(video.volume),
      widthPixels: optionalInteger(video.videoWidth || video.clientWidth || 0),
      heightPixels: optionalInteger(video.videoHeight || video.clientHeight || 0)
    };
  }

  function serializeWindow(pipWindow) {
    if (!pipWindow) {
      return null;
    }
    return {
      widthPixels: optionalInteger(pipWindow.width || 0),
      heightPixels: optionalInteger(pipWindow.height || 0)
    };
  }

  function documentWindowOpen() {
    return !!document.pictureInPictureEnabled;
  }

  function emit(reason) {
    var payload = {
      sequenceNumber: nextSequenceNumber++,
      reason: reason,
      pictureInPictureActive: !!document.pictureInPictureElement,
      documentWindowOpen: documentWindowOpen(),
      video: serializeVideo(activeVideo()),
      pictureInPictureWindow: serializeWindow(boundPiPWindow)
    };
    window.prompt(promptMessage, JSON.stringify(payload));
  }

  function bindWindowEvents(pipWindow) {
    if (!pipWindow || pipWindow === boundPiPWindow) {
      return;
    }
    if (boundPiPWindow && boundPiPWindow.removeEventListener) {
      boundPiPWindow.removeEventListener("resize", onWindowResize);
    }
    boundPiPWindow = pipWindow;
    if (boundPiPWindow.addEventListener) {
      boundPiPWindow.addEventListener("resize", onWindowResize);
    }
  }

  function onWindowResize() {
    emit("pipWindowResize");
  }

  function bindVideo(video) {
    if (!(video instanceof HTMLVideoElement)) {
      return;
    }
    if (boundVideos && boundVideos.has(video)) {
      return;
    }
    if (boundVideos) {
      boundVideos.add(video);
    }
    video.addEventListener("enterpictureinpicture", function(event) {
      boundVideoPiPWindow = event && event.pictureInPictureWindow ? event.pictureInPictureWindow : null;
      bindWindowEvents(boundVideoPiPWindow);
      emit("enterpictureinpicture");
    });
    video.addEventListener("leavepictureinpicture", function() {
      boundVideoPiPWindow = null;
      emit("leavepictureinpicture");
    });
  }

  function observeVideos() {
    var videos = document.querySelectorAll("video");
    for (var index = 0; index < videos.length; index += 1) {
      bindVideo(videos[index]);
    }
  }

  function observeMutations() {
    if (typeof MutationObserver !== "function") {
      return;
    }
    var observer = new MutationObserver(function() {
      observeVideos();
      var currentWindowOpen = documentWindowOpen();
      if (currentWindowOpen !== lastDocumentWindowOpen) {
        lastDocumentWindowOpen = currentWindowOpen;
        emit("documentWindowChange");
      }
    });
    observer.observe(document.documentElement || document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["src", "currentSrc"]
    });
  }

  observeVideos();
  observeMutations();
  lastDocumentWindowOpen = documentWindowOpen();
  emit("bootstrap");
})(); )JS";
  return script;
}

void injectPictureInPictureObserverScript(cef_frame_t* frame) {
  if (frame == nullptr || frame->execute_java_script == nullptr) {
    return;
  }

  const std::string& source = pictureInPictureObserverScript();
  cef_string_t script{};
  cef_string_t url{};
  if (!miumCEFNativeUTF16FromUTF8(source.c_str(), script, nullptr)
      || !miumCEFNativeUTF16FromUTF8("about:blank", url, nullptr)) {
    miumCEFNativeClearUTF16String(script);
    miumCEFNativeClearUTF16String(url);
    return;
  }
  frame->execute_java_script(frame, &script, &url, 0);
  miumCEFNativeClearUTF16String(script);
  miumCEFNativeClearUTF16String(url);
}

std::string firstFaviconURLFromList(cef_string_list_t iconURLs) {
  CefStringUTF16Clear utf16Clear = nullptr;
  CefStringListSizeFn stringListSize = nullptr;
  CefStringListValueFn stringListValue = nullptr;
  {
    CefStateLockGuard lock;
    utf16Clear = gCefApi.utf16Clear;
    stringListSize = gCefApi.stringListSize;
    stringListValue = gCefApi.stringListValue;
  }
  if (iconURLs == nullptr || stringListSize == nullptr || stringListValue == nullptr) {
    return std::string();
  }

  const size_t count = stringListSize(iconURLs);
  for (size_t index = 0; index < count; ++index) {
    cef_string_t value{};
    if (!stringListValue(iconURLs, index, &value)) {
      continue;
    }
    NSString* url = NSStringFromCEFString(&value);
    if (utf16Clear != nullptr) {
      utf16Clear(&value);
    }
    if (url.length > 0) {
      return stringFromNSStringUTF8(url);
    }
  }
  return std::string();
}

NSString* miumCEFNativeNSStringFromCEFString(const cef_string_t* source) {
  return NSStringFromCEFString(source);
}

NSString* miumCEFNativeNSStringFromCEFUserFreeString(cef_string_userfree_t source) {
  return NSStringFromCEFUserFreeString(source);
}

std::string miumCEFNativeStringFromNSStringUTF8(NSString* source) {
  return stringFromNSStringUTF8(source);
}

void miumCEFNativeEmitBrowserMessageForMappedBrowser(
  cef_browser_t* browser,
  const char* channel,
  const char* message
) {
  emitBrowserMessageForMappedBrowser(browser, channel, message);
}

void miumCEFNativeEmitTopLevelNativeContentForBrowser(
  cef_browser_t* browser,
  NSString* urlString,
  MiumCEFTopLevelNativeContentKind kind,
  NSString* pathExtension,
  NSString* uniformTypeIdentifier
) {
  emitTopLevelNativeContentForBrowser(browser, urlString, kind, pathExtension, uniformTypeIdentifier);
}

std::string miumCEFNativeRenderProcessTerminationPayloadString(
  cef_termination_status_t status,
  int errorCode,
  const cef_string_t* errorString
) {
  return renderProcessTerminationPayloadString(status, errorCode, errorString);
}

std::string miumCEFNativeMainFrameNavigationPayloadString(
  NSString* urlString,
  int userGesture,
  int isRedirect
) {
  return mainFrameNavigationPayloadString(urlString, userGesture, isRedirect);
}

std::string miumCEFNativeOpenURLInTabPayloadString(
  NSString* urlString,
  bool activatesTab
) {
  return openURLInTabPayloadString(urlString, activatesTab);
}

std::string miumCEFNativeNormalizedPermissionOriginString(NSString* rawURLString) {
  return normalizedPermissionOriginString(rawURLString);
}

std::string miumCEFNativeTopLevelPermissionOriginString(cef_browser_t* browser) {
  return topLevelPermissionOriginString(browser);
}

std::string miumCEFNativeFrameIdentifierString(cef_frame_t* frame) {
  return frameIdentifierString(frame);
}

void miumCEFNativeInjectPictureInPictureObserverScript(cef_frame_t* frame) {
  injectPictureInPictureObserverScript(frame);
}

std::string miumCEFNativeFirstFaviconURLFromList(cef_string_list_t iconURLs) {
  return firstFaviconURLFromList(iconURLs);
}
