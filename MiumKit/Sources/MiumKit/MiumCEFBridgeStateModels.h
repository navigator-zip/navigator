#pragma once

#import <AppKit/AppKit.h>

#include <string>
#include <unordered_map>
#include <unordered_set>

#include "CefRef.h"
#include "MiumCEFBridgeCallbackRegistration.h"
#include "MiumCEFBridgeCefTypes.h"
#include "MiumCEFBridgeContentClassification.h"
#include "MiumCEFBridgeNative.h"

@class MiumBrowserContainerView;

@interface MiumCEFHostResourceState : NSObject

@property (nonatomic, weak) NSView* hostView;
@property (nonatomic, strong) MiumBrowserContainerView* containerView;

@end

struct MiumCEFMessageState {
  std::string channel;
  MiumCEFEventCallback callback = nullptr;
  void* context = nullptr;
  MiumCEFCallbackRegistrationRef registration;
  uint64_t generation = 0;
};

struct MiumCEFRuntimeState {
  uint64_t id = 0;
  std::string runtimeRoot;
  std::string metadataPath;
  uint64_t defaultRequestContextId = 0;
  bool active = true;
  size_t pendingBrowserCloseCount = 0;
  std::unordered_set<uint64_t> browserIds;
};

struct MiumCEFBrowserState {
  uint64_t id = 0;
  uint64_t runtimeId = 0;
  uint64_t requestContextId = 0;
  uint64_t hostViewId = 0;
  uint64_t generation = 1;
  uint64_t nextMessageHandlerGeneration = 1;
  bool active = true;
  bool closing = false;
  bool terminal = false;
  bool attached = false;
  bool hostViewBound = false;
  CefRef<cef_browser_t> nativeBrowser;
  CefRef<cef_client_t> nativeClient;
  std::unordered_map<std::string, MiumCEFMessageState> handlers;
};

struct MiumCEFHostViewState {
  uint64_t id = 0;
  uint64_t browserId = 0;
  MiumCEFHostResourceState* resources = nil;
  bool active = true;
};

enum class MiumCEFNativeBrowserCloseKind : uint8_t {
  teardown = 0,
  replacement,
};

enum class MiumCEFRuntimeShutdownState : uint8_t {
  uninitialized = 0,
  initializing,
  initialized,
  shutdownRequested,
  drainingBrowsers,
  drainingCallbacks,
  shuttingDownCEF,
  shutDown,
};

enum class MiumCEFBrowserCloseDisposition : uint8_t {
  failed = 0,
  completedSynchronously,
  closePending,
};

struct MiumCEFRendererJavaScriptRequestState {
  uint64_t requestID = 0;
  uint64_t browserId = 0;
  void* completionContext = nullptr;
  MiumCEFCompletion completion = nullptr;
};

struct RuntimeLayoutConfig {
  std::string resourcesDir;
  std::string localesDir;
  std::string helpersDir;
};

template <typename State>
inline State* miumCEFStateFromRefCountedBase(cef_base_ref_counted_t* base) {
  return base == nullptr ? nullptr : reinterpret_cast<State*>(base);
}
