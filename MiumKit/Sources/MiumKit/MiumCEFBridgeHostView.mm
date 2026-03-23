#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <objc/runtime.h>
#include <vector>

#include "CefRef.h"
#include "MiumCEFBridgeBrowserRegistry.h"
#include "MiumCEFBridgeClient.h"
#include "MiumCEFBridgeHostView.h"
#include "MiumCEFBridgeInternalAdapters.h"
#include "MiumCEFBridgeInternalRuntimeBootstrapSupport.h"
#include "MiumCEFBridgeInternalRuntimeExecutionSupport.h"
#include "MiumCEFBridgeThreading.h"
#include "Tracing.h"
#if defined(MIUM_CEF_BRIDGE_TESTING)
#include "MiumCEFBridgeNative+Testing.h"
#endif

@implementation MiumBrowserContainerView

- (BOOL)isFlipped {
  return YES;
}

@end

@implementation MiumCEFHostResourceState
@end

static char kMiumBrowserContainerAssociationKey;

static MiumBrowserContainerView* associatedBrowserContainerViewForHostView(NSView* hostView) {
  if (hostView == nil) {
    return nil;
  }
  id associated = objc_getAssociatedObject(hostView, &kMiumBrowserContainerAssociationKey);
  return [associated isKindOfClass:[MiumBrowserContainerView class]] ? (MiumBrowserContainerView*)associated : nil;
}

static void setAssociatedBrowserContainerViewForHostView(
  NSView* hostView,
  MiumBrowserContainerView* containerView
) {
  if (hostView == nil) {
    return;
  }
  objc_setAssociatedObject(
    hostView,
    &kMiumBrowserContainerAssociationKey,
    containerView,
    OBJC_ASSOCIATION_RETAIN_NONATOMIC
  );
}

static void initializeWindowInfoForHostView(cef_window_info_t& windowInfo, const void* hostView) {
  std::memset(&windowInfo, 0, sizeof(windowInfo));
  windowInfo.size = sizeof(cef_window_info_t);
  windowInfo.windowless_rendering_enabled = 0;
  windowInfo.shared_texture_enabled = 0;
  windowInfo.external_begin_frame_enabled = 0;
  windowInfo.runtime_style = CEF_RUNTIME_STYLE_DEFAULT;
  windowInfo.hidden = 0;

  if (hostView != nullptr) {
    windowInfo.parent_view = const_cast<void*>(hostView);

    NSView* view = (__bridge NSView*)hostView;
    const NSRect bounds = [view bounds];
    windowInfo.bounds.x = 0;
    windowInfo.bounds.y = 0;
    windowInfo.bounds.width = static_cast<int>(std::max(1.0, std::floor(bounds.size.width)));
    windowInfo.bounds.height = static_cast<int>(std::max(1.0, std::floor(bounds.size.height)));
  }
}

static bool validateHostViewForBrowserCreation(
  void* hostView,
  NSView** outParentView,
  std::string* errorOut
) {
  if (outParentView != nullptr) {
    *outParentView = nil;
  }
  if (errorOut != nullptr) {
    errorOut->clear();
  }
  if (hostView == nullptr) {
    if (errorOut != nullptr) {
      *errorOut = "host view pointer is null";
    }
    return false;
  }

  id candidate = (__bridge id)hostView;
  if (candidate == nil) {
    if (errorOut != nullptr) {
      *errorOut = "host view object is nil";
    }
    return false;
  }
  if (![candidate isKindOfClass:[NSView class]]) {
    if (errorOut != nullptr) {
      *errorOut = "host view is not an NSView";
    }
    return false;
  }

  NSView* parentView = (NSView*)candidate;
  const NSRect bounds = parentView.bounds;
  if (NSWidth(bounds) <= 0.0 || NSHeight(bounds) <= 0.0) {
    if (errorOut != nullptr) {
      *errorOut = "host view has zero bounds";
    }
    return false;
  }
#if !defined(MIUM_CEF_BRIDGE_TESTING)
  NSWindow* window = parentView.window;
  if (window == nil) {
    if (errorOut != nullptr) {
      *errorOut = "host view has no window";
    }
    return false;
  }
  if (parentView.superview == nil && window.contentView != parentView) {
    if (errorOut != nullptr) {
      *errorOut = "host view is detached from a stable superview";
    }
    return false;
  }
  if (window.windowNumber <= 0) {
    if (errorOut != nullptr) {
      *errorOut = "host window has no window number";
    }
    return false;
  }
#endif
  if (outParentView != nullptr) {
    *outParentView = parentView;
  }
  return true;
}

static void logHostViewForBrowserCreation(void* hostView, NSView* parentView) {
  if (parentView == nil) {
    return;
  }
  NSWindow* window = parentView.window;
  const NSRect bounds = parentView.bounds;
  miumCefTrace(
    "host-view",
    "createBrowserSync hostView=%p class=%s window=%p superview=%p bounds=(%.1f %.1f %.1f %.1f)\n",
    hostView,
    object_getClassName(parentView),
    (__bridge void*)window,
    (__bridge void*)parentView.superview,
    bounds.origin.x,
    bounds.origin.y,
    bounds.size.width,
    bounds.size.height
  );
}

double backingScaleFactorForHostView(NSView* hostView) {
  if (hostView == nil) {
    return 1.0;
  }

  CGFloat scale = hostView.window.backingScaleFactor;
  if (scale <= 0.0) {
    scale = hostView.layer.contentsScale;
  }
  if (scale <= 0.0) {
    scale = NSScreen.mainScreen.backingScaleFactor;
  }
  return scale > 0.0 ? scale : 1.0;
}

static MiumBrowserContainerView* browserContainerViewForHostView(NSView* hostView) {
  if (hostView == nil) {
    return nil;
  }
  if (MiumBrowserContainerView* associatedContainerView = associatedBrowserContainerViewForHostView(hostView)) {
    return associatedContainerView;
  }
  CefStateLockGuard lock;
  auto* hostViewState = activeHostViewStateForViewLocked(hostView);
  if (hostViewState == nullptr) {
    return nil;
  }
  return resolvedContainerViewForState(hostViewState);
}

static MiumBrowserContainerView* ensureBrowserContainerViewForHostView(NSView* hostView) {
  if (hostView == nil) {
    return nil;
  }
  MiumBrowserContainerView* containerView = nil;
  {
    CefStateLockGuard lock;
    auto* hostViewState = activeHostViewStateForViewLocked(hostView);
    if (hostViewState != nullptr) {
      containerView = resolvedContainerViewForState(hostViewState);
    }
  }
  if (containerView == nil) {
    containerView = [[MiumBrowserContainerView alloc] initWithFrame:hostView.bounds];
    containerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [hostView addSubview:containerView];
  } else {
    containerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    containerView.frame = hostView.bounds;
  }
  {
    CefStateLockGuard lock;
    auto* hostViewState = activeHostViewStateForViewLocked(hostView);
    if (hostViewState != nullptr) {
      MiumCEFHostResourceState* resources = ensureHostResources(hostViewState);
      if (resources != nil) {
        resources.containerView = containerView;
      }
    }
  }
  setAssociatedBrowserContainerViewForHostView(hostView, containerView);
  return containerView;
}

void removeManagedBrowserSubviewsForHostView(NSView* hostView) {
  if (hostView == nil) {
    return;
  }
  MiumBrowserContainerView* containerView = browserContainerViewForHostView(hostView);
  if (containerView != nil) {
    NSArray<NSView*>* subviews = [containerView.subviews copy];
    for (NSView* subview in subviews) {
      [subview removeFromSuperview];
    }
  }
  if (containerView != nil && containerView.superview == hostView) {
    [containerView removeFromSuperview];
  }
  setAssociatedBrowserContainerViewForHostView(hostView, nil);
  {
    CefStateLockGuard lock;
    auto* hostViewState = activeHostViewStateForViewLocked(hostView);
    if (hostViewState != nullptr && hostViewState->resources != nil) {
      hostViewState->resources.containerView = nil;
    }
  }
}

static void removeCreatedManagedBrowserSubviewsForHostView(
  NSView* hostView,
  const std::vector<void*>& createdManagedSubviews
) {
  if (hostView == nil) {
    return;
  }
  (void)createdManagedSubviews;
  removeManagedBrowserSubviewsForHostView(hostView);
}

void removeAllManagedBrowserSubviews(void) {
  NSMutableArray<MiumCEFHostResourceState*>* hostResources = [NSMutableArray array];
  {
    CefStateLockGuard lock;
    for (const auto& hostPair : gHostViews) {
      auto* hostViewState = hostPair.second.get();
      if (hostViewState != nullptr && hostViewState->resources != nil) {
        [hostResources addObject:hostViewState->resources];
      }
    }
  }

  for (MiumCEFHostResourceState* resources in hostResources) {
    if (resources == nil) {
      continue;
    }
    NSView* hostView = resources.hostView;
    if (hostView != nil) {
      removeManagedBrowserSubviewsForHostView(hostView);
      continue;
    }
    if (resources.containerView != nil) {
      NSArray<NSView*>* subviews = [resources.containerView.subviews copy];
      for (NSView* subview in subviews) {
        [subview removeFromSuperview];
      }
      [resources.containerView removeFromSuperview];
      resources.containerView = nil;
    }
  }
}

static void updateManagedBrowserSubviewsForHostView(
  NSView* hostView,
  const std::vector<void*>& createdManagedSubviews,
  bool removePreviouslyManagedSubviews
) {
  if (hostView == nil) {
    return;
  }
  (void)createdManagedSubviews;
  if (removePreviouslyManagedSubviews) {
    removeManagedBrowserSubviewsForHostView(hostView);
  }
  (void)ensureBrowserContainerViewForHostView(hostView);
}

void resizeEmbeddedBrowserHostView(NSView* hostView, int pixelWidth, int pixelHeight) {
  if (hostView == nil || pixelWidth <= 0 || pixelHeight <= 0) {
    return;
  }

  const CGFloat scale = backingScaleFactorForHostView(hostView);
  const NSSize targetSize = NSMakeSize(
    std::max<CGFloat>(1.0, static_cast<CGFloat>(pixelWidth) / scale),
    std::max<CGFloat>(1.0, static_cast<CGFloat>(pixelHeight) / scale)
  );
  const NSRect targetFrame = NSMakeRect(0.0, 0.0, targetSize.width, targetSize.height);

  MiumBrowserContainerView* containerView = browserContainerViewForHostView(hostView);
  if (containerView == nil) {
    return;
  }
  if (!NSEqualRects(containerView.frame, hostView.bounds)) {
    containerView.frame = hostView.bounds;
  }

  for (NSView* subview in containerView.subviews) {
    if (subview == nil || subview.superview != containerView) {
      continue;
    }
    subview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (!NSEqualRects(subview.frame, targetFrame)) {
      subview.frame = targetFrame;
    }
  }

  [containerView layoutSubtreeIfNeeded];
  [hostView layoutSubtreeIfNeeded];
}

bool configureSnapshotFormat(
  NSString* format,
  MiumCEFSnapshotOptions* outOptions,
  NSString** errorOut
) {
  if (outOptions == nullptr) {
    if (errorOut != nullptr) {
      *errorOut = @"Snapshot options unavailable";
    }
    return false;
  }

  NSString* normalized = format.lowercaseString;
  if (normalized == nil || normalized.length == 0 || [normalized isEqualToString:@"png"]) {
    outOptions->captureAsPDF = false;
    outOptions->bitmapFileType = NSBitmapImageFileTypePNG;
    outOptions->usesJPEGCompressionFactor = false;
    return true;
  }

  if ([normalized isEqualToString:@"jpg"] || [normalized isEqualToString:@"jpeg"]) {
    outOptions->captureAsPDF = false;
    outOptions->bitmapFileType = NSBitmapImageFileTypeJPEG;
    outOptions->usesJPEGCompressionFactor = true;
    return true;
  }

  if ([normalized isEqualToString:@"tif"] || [normalized isEqualToString:@"tiff"]) {
    outOptions->captureAsPDF = false;
    outOptions->bitmapFileType = NSBitmapImageFileTypeTIFF;
    outOptions->usesJPEGCompressionFactor = false;
    return true;
  }

  if ([normalized isEqualToString:@"gif"]) {
    outOptions->captureAsPDF = false;
    outOptions->bitmapFileType = NSBitmapImageFileTypeGIF;
    outOptions->usesJPEGCompressionFactor = false;
    return true;
  }

  if ([normalized isEqualToString:@"bmp"]) {
    outOptions->captureAsPDF = false;
    outOptions->bitmapFileType = NSBitmapImageFileTypeBMP;
    outOptions->usesJPEGCompressionFactor = false;
    return true;
  }

  if ([normalized isEqualToString:@"pdf"]) {
    outOptions->captureAsPDF = true;
    outOptions->usesJPEGCompressionFactor = false;
    return true;
  }

  if (errorOut != nullptr) {
    *errorOut = [NSString stringWithFormat:@"Unsupported snapshot format '%@'", format];
  }
  return false;
}

static bool configureSnapshotFormatFromOutputPath(
  NSString* outputPath,
  MiumCEFSnapshotOptions* outOptions,
  NSString** errorOut
) {
  NSString* extension = outputPath.pathExtension.lowercaseString;
  if (extension == nil || extension.length == 0) {
    extension = @"png";
  }
  return configureSnapshotFormat(extension, outOptions, errorOut);
}

static bool parseSnapshotClipRect(id value, NSRect* outRect, NSString** errorOut) {
  if (value == nil || value == [NSNull null]) {
    return true;
  }
  if (![value isKindOfClass:[NSDictionary class]]) {
    if (errorOut != nullptr) {
      *errorOut = @"Snapshot clip must be an object with x, y, width, and height";
    }
    return false;
  }

  NSDictionary* clipDictionary = (NSDictionary*)value;
  // Clip coordinates are expressed in host-view points so they line up with
  // AppKit snapshot APIs and `hostView.bounds`, not backing pixels.
  NSArray<NSString*>* requiredKeys = @[ @"x", @"y", @"width", @"height" ];
  NSMutableArray<NSNumber*>* values = [NSMutableArray arrayWithCapacity:requiredKeys.count];
  for (NSString* key in requiredKeys) {
    id rawValue = clipDictionary[key];
    if (![rawValue isKindOfClass:[NSNumber class]]) {
      if (errorOut != nullptr) {
        *errorOut = [NSString stringWithFormat:@"Snapshot clip '%@' must be numeric", key];
      }
      return false;
    }
    [values addObject:rawValue];
  }

  const double x = ((NSNumber*)values[0]).doubleValue;
  const double y = ((NSNumber*)values[1]).doubleValue;
  const double width = ((NSNumber*)values[2]).doubleValue;
  const double height = ((NSNumber*)values[3]).doubleValue;
  if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(width) || !std::isfinite(height)
      || width <= 0.0 || height <= 0.0) {
    if (errorOut != nullptr) {
      *errorOut = @"Snapshot clip must have finite x, y, width, and height values";
    }
    return false;
  }

  if (outRect != nullptr) {
    *outRect = NSMakeRect(
      static_cast<CGFloat>(x),
      static_cast<CGFloat>(y),
      static_cast<CGFloat>(width),
      static_cast<CGFloat>(height)
    );
  }
  return true;
}

bool parseSnapshotOptions(
  const char* jsonOptions,
  NSString* outputPath,
  MiumCEFSnapshotOptions* outOptions,
  NSString** errorOut
) {
  if (!configureSnapshotFormatFromOutputPath(outputPath, outOptions, errorOut)) {
    return false;
  }

  if (jsonOptions == nullptr || jsonOptions[0] == '\0') {
    return true;
  }

  NSString* optionsString = [NSString stringWithUTF8String:jsonOptions];
  if (optionsString == nil) {
    if (errorOut != nullptr) {
      *errorOut = @"Snapshot options are not UTF8";
    }
    return false;
  }

  NSString* trimmedOptions = [optionsString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (trimmedOptions == nil || trimmedOptions.length == 0 || [trimmedOptions isEqualToString:@"null"]) {
    return true;
  }

  NSData* optionsData = [trimmedOptions dataUsingEncoding:NSUTF8StringEncoding];

  NSError* parseError = nil;
  id parsedOptions = [NSJSONSerialization JSONObjectWithData:optionsData options:0 error:&parseError];
  if (parsedOptions == nil || parseError != nil) {
    if (errorOut != nullptr) {
      *errorOut = parseError.localizedDescription ?: @"Snapshot options are not valid JSON";
    }
    return false;
  }
  if (![parsedOptions isKindOfClass:[NSDictionary class]]) {
    if (errorOut != nullptr) {
      *errorOut = @"Snapshot options must be a JSON object";
    }
    return false;
  }

  NSDictionary* optionsDictionary = (NSDictionary*)parsedOptions;
  NSSet<NSString*>* supportedKeys = [NSSet setWithArray:@[ @"format", @"quality", @"clip", @"clipRect" ]];
  for (id rawKey in optionsDictionary) {
    NSString* key = (NSString*)rawKey;
    if (![supportedKeys containsObject:key]) {
      if (errorOut != nullptr) {
        *errorOut = [NSString stringWithFormat:@"Unsupported snapshot option '%@'", key];
      }
      return false;
    }
  }

  id formatValue = optionsDictionary[@"format"];
  if (formatValue != nil && formatValue != [NSNull null]) {
    if (![formatValue isKindOfClass:[NSString class]] || ((NSString*)formatValue).length == 0) {
      if (errorOut != nullptr) {
        *errorOut = @"Snapshot format must be a non-empty string";
      }
      return false;
    }
    if (!configureSnapshotFormat((NSString*)formatValue, outOptions, errorOut)) {
      return false;
    }
  }

  const bool hasClip = optionsDictionary[@"clip"] != nil && optionsDictionary[@"clip"] != [NSNull null];
  const bool hasClipRect = optionsDictionary[@"clipRect"] != nil && optionsDictionary[@"clipRect"] != [NSNull null];
  if (hasClip && hasClipRect) {
    if (errorOut != nullptr) {
      *errorOut = @"Provide either 'clip' or 'clipRect', not both";
    }
    return false;
  }

  NSRect clipRect = NSZeroRect;
  if (!parseSnapshotClipRect(hasClip ? optionsDictionary[@"clip"] : optionsDictionary[@"clipRect"], &clipRect, errorOut)) {
    return false;
  }
  outOptions->hasClipRect = hasClip || hasClipRect;
  if (outOptions->hasClipRect) {
    outOptions->clipRect = clipRect;
  }

  id qualityValue = optionsDictionary[@"quality"];
  if (qualityValue != nil && qualityValue != [NSNull null]) {
    if (![qualityValue isKindOfClass:[NSNumber class]]) {
      if (errorOut != nullptr) {
        *errorOut = @"Snapshot quality must be numeric";
      }
      return false;
    }

    const double quality = ((NSNumber*)qualityValue).doubleValue;
    if (!std::isfinite(quality) || quality < 0.0 || quality > 1.0) {
      if (errorOut != nullptr) {
        *errorOut = @"Snapshot quality must be between 0.0 and 1.0";
      }
      return false;
    }
    if (outOptions->captureAsPDF || outOptions->bitmapFileType != NSBitmapImageFileTypeJPEG) {
      if (errorOut != nullptr) {
        *errorOut = @"Snapshot quality is only supported for JPEG snapshots";
      }
      return false;
    }
    outOptions->jpegCompressionFactor = static_cast<CGFloat>(quality);
    outOptions->usesJPEGCompressionFactor = true;
  }

  return true;
}

NSRect snapshotBoundsForHostView(
  NSView* hostView,
  const MiumCEFSnapshotOptions& options,
  NSString** errorOut
) {
  const NSRect hostBounds = hostView.bounds;
  if (NSWidth(hostBounds) <= 0.0 || NSHeight(hostBounds) <= 0.0) {
    if (errorOut != nullptr) {
      *errorOut = @"Browser host view has no visible size";
    }
    return NSZeroRect;
  }

  if (!options.hasClipRect) {
    return hostBounds;
  }

  const NSRect clippedBounds = NSIntersectionRect(hostBounds, options.clipRect);
  if (NSWidth(clippedBounds) <= 0.0 || NSHeight(clippedBounds) <= 0.0) {
    if (errorOut != nullptr) {
      *errorOut = @"Snapshot clip is outside the browser host view bounds";
    }
    return NSZeroRect;
  }

  return clippedBounds;
}

#if defined(MIUM_CEF_BRIDGE_TESTING)
static CGImageRef makeOnePixelSnapshotTestImage(void) {
  static const uint8_t pixel[4] = { 0x33, 0x66, 0xCC, 0xFF };
  CGDataProviderRef provider =
    gTestOnePixelImageFailureMode == MiumCEFBridgeTestOnePixelImageFailureMode::nullProvider
      ? nullptr
      : CGDataProviderCreateWithData(nullptr, pixel, sizeof(pixel), nullptr);
  if (provider == nullptr) {
    return nullptr;
  }
  CGColorSpaceRef colorSpace =
    gTestOnePixelImageFailureMode == MiumCEFBridgeTestOnePixelImageFailureMode::nullColorSpace
      ? nullptr
      : CGColorSpaceCreateDeviceRGB();
  if (colorSpace == nullptr) {
    CGDataProviderRelease(provider);
    return nullptr;
  }
  const CGBitmapInfo bitmapInfo = static_cast<CGBitmapInfo>(
    static_cast<uint32_t>(kCGImageAlphaPremultipliedLast) |
    static_cast<uint32_t>(kCGBitmapByteOrderDefault)
  );
  CGImageRef image = CGImageCreate(
    1,
    1,
    8,
    32,
    4,
    colorSpace,
    bitmapInfo,
    provider,
    nullptr,
    false,
    kCGRenderingIntentDefault
  );
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}
#endif

NSBitmapImageRep* snapshotBitmapRepForHostViewFromWindow(NSView* hostView, NSRect bounds) {
  if (hostView == nil
      || hostView.window == nil
      || hostView.window.windowNumber <= 0
      || [hostView isHiddenOrHasHiddenAncestor]) {
    return nil;
  }

  const NSRect boundsInWindow = [hostView convertRect:bounds toView:nil];
  const NSRect boundsOnScreen = [hostView.window convertRectToScreen:boundsInWindow];
  if (NSWidth(boundsOnScreen) <= 0.0 || NSHeight(boundsOnScreen) <= 0.0) {
    return nil;
  }

  #pragma clang diagnostic push
  #pragma clang diagnostic ignored "-Wdeprecated-declarations"
#if defined(MIUM_CEF_BRIDGE_TESTING)
  CGImageRef windowImage = nullptr;
  switch (gTestWindowSnapshotMode) {
    case MiumCEFBridgeTestWindowSnapshotMode::forceNullImage:
      windowImage = nullptr;
      break;
    case MiumCEFBridgeTestWindowSnapshotMode::forceOnePixelImage:
      windowImage = makeOnePixelSnapshotTestImage();
      break;
    case MiumCEFBridgeTestWindowSnapshotMode::live:
      windowImage = CGWindowListCreateImage(
        NSRectToCGRect(boundsOnScreen),
        kCGWindowListOptionIncludingWindow,
        static_cast<CGWindowID>(hostView.window.windowNumber),
        kCGWindowImageBoundsIgnoreFraming
      );
      break;
  }
#else
  CGImageRef windowImage = CGWindowListCreateImage(
    NSRectToCGRect(boundsOnScreen),
    kCGWindowListOptionIncludingWindow,
    static_cast<CGWindowID>(hostView.window.windowNumber),
    kCGWindowImageBoundsIgnoreFraming
  );
#endif
  #pragma clang diagnostic pop
  if (windowImage == nullptr) {
    return nil;
  }

  NSBitmapImageRep* imageRep = [[NSBitmapImageRep alloc] initWithCGImage:windowImage];
  CGImageRelease(windowImage);
  return imageRep;
}

static NSBitmapImageRep* snapshotBitmapRepForHostViewFromDisplayCache(NSView* hostView, NSRect bounds) {
  NSBitmapImageRep* bitmap = [hostView bitmapImageRepForCachingDisplayInRect:bounds];
  if (bitmap == nil) {
    return nil;
  }

  [hostView cacheDisplayInRect:bounds toBitmapImageRep:bitmap];
  return bitmap;
}

NSData* snapshotDataForHostView(
  NSView* hostView,
  const MiumCEFSnapshotOptions& options,
  NSString** errorOut
) {
  if (hostView == nil) {
    if (errorOut != nullptr) {
      *errorOut = @"Browser host view unavailable";
    }
    return nil;
  }

  [hostView layoutSubtreeIfNeeded];
  [hostView displayIfNeeded];
  if (hostView.window != nil) {
    [hostView.window displayIfNeeded];
  }

  const NSRect bounds = snapshotBoundsForHostView(hostView, options, errorOut);
  if (NSWidth(bounds) <= 0.0 || NSHeight(bounds) <= 0.0) {
    return nil;
  }

  if (options.captureAsPDF) {
    NSData* pdfData = [hostView dataWithPDFInsideRect:bounds];
    if (pdfData == nil && errorOut != nullptr) {
      *errorOut = @"Failed to capture PDF snapshot";
    }
    return pdfData;
  }

  NSBitmapImageRep* bitmap = snapshotBitmapRepForHostViewFromWindow(hostView, bounds);
  if (bitmap == nil) {
    bitmap = snapshotBitmapRepForHostViewFromDisplayCache(hostView, bounds);
  }
  if (bitmap == nil) {
    if (errorOut != nullptr) {
      *errorOut = @"Failed to allocate snapshot buffer";
    }
    return nil;
  }

  NSDictionary* properties = @{};
  if (options.usesJPEGCompressionFactor && options.bitmapFileType == NSBitmapImageFileTypeJPEG) {
    properties = @{ NSImageCompressionFactor: @(options.jpegCompressionFactor) };
  }

  NSData* imageData = [bitmap representationUsingType:options.bitmapFileType properties:properties];
  if (imageData == nil && errorOut != nullptr) {
    *errorOut = @"Failed to encode browser snapshot";
  }
  return imageData;
}

bool createBrowserWithWindowInfo(
  void* hostView,
  cef_browser_t** outBrowser,
  cef_client_t** outClient,
  std::vector<void*>* outCreatedManagedSubviews
) {
  if (outBrowser != nullptr) {
    *outBrowser = nullptr;
  }
  if (outClient != nullptr) {
    *outClient = nullptr;
  }
  if (outCreatedManagedSubviews != nullptr) {
    outCreatedManagedSubviews->clear();
  }

  CefBrowserCreateBrowserSyncFn createBrowserSync = nullptr;
  {
    CefStateLockGuard lock;
    if (!miumCEFIsCefRuntimeUsableLocked()) {
      return false;
    }
    createBrowserSync = gCefApi.createBrowserSync;
  }
  if (createBrowserSync == nullptr) {
    return false;
  }
  if (hostView == nullptr) {
    return false;
  }

  cef_window_info_t info{};
  cef_browser_t* created = nullptr;
  cef_string_t blankURL{};
  std::string urlError;
  bool prepared = miumCEFNativeUTF16FromUTF8("about:blank", blankURL, &urlError);
  if (!prepared) {
    return false;
  }

  cef_client_t* client = createBrowserClient();
  if (client == nullptr) {
    miumCEFNativeClearUTF16String(blankURL);
    return false;
  }

  NSView* parentView = nil;
  bool createdContainer = false;
  bool preparedWindowInfo = false;
  miumCEFNativeRunOnCefMainThread([&] {
    {
      CefStateLockGuard lock;
      if (!miumCEFIsCefRuntimeUsableLocked()) {
        return;
      }
    }

    std::string hostViewError;
    if (!validateHostViewForBrowserCreation(hostView, &parentView, &hostViewError)) {
      miumCefTrace(
        "host-view",
        "createBrowserSync aborted: %s\n",
        hostViewError.empty() ? "invalid host view state" : hostViewError.c_str()
      );
      return;
    }
    logHostViewForBrowserCreation(hostView, parentView);
    createdContainer = browserContainerViewForHostView(parentView) == nil;
    MiumBrowserContainerView* containerView = ensureBrowserContainerViewForHostView(parentView);
    if (containerView == nil) {
      return;
    }
    initializeWindowInfoForHostView(info, (__bridge void*)containerView);
    preparedWindowInfo = true;
  });
  if (!preparedWindowInfo) {
    if (client != nullptr) {
      releaseOwnedCefValue(client);
    }
    miumCEFNativeClearUTF16String(blankURL);
    return false;
  }

  miumCEFNativeRunOnCefMainThread([&] {
    {
      CefStateLockGuard lock;
      if (!miumCEFIsCefRuntimeUsableLocked()) {
        return;
      }
    }

    cef_browser_settings_t settings{};
    settings.size = sizeof(settings);
    miumCefTrace("host-view", "create_browser_sync lane=%s hostView=%p\n", miumCEFThreadLaneLabel(), hostView);
    created = createBrowserSync(&info, client, &blankURL, &settings, nullptr, nullptr);
    miumCefTrace(
      "host-view",
      "createBrowserSync returned browser=%p client=%p\n",
      static_cast<void*>(created),
      static_cast<void*>(client)
    );
  });

  (void)outCreatedManagedSubviews;

  if (created == nullptr) {
    if (client != nullptr) {
      releaseOwnedCefValue(client);
    }
    if (createdContainer && parentView != nil) {
      miumCEFNativeRunOnCefMainThread([parentView] {
        removeManagedBrowserSubviewsForHostView(parentView);
      });
    }
    miumCEFNativeClearUTF16String(blankURL);
    return false;
  }

  bool shouldKickExternalMessagePump = false;
  {
    CefStateLockGuard lock;
    shouldKickExternalMessagePump = gExternalMessagePumpEnabled;
  }
  if (shouldKickExternalMessagePump) {
    miumCEFNativeScheduleExternalMessagePumpWork(0);
  }

  miumCEFNativeClearUTF16String(blankURL);
  if (outBrowser != nullptr) {
    *outBrowser = created;
  }
  if (outClient != nullptr) {
    *outClient = client;
  }
  miumCefTrace(
    "host-view",
    "createBrowserWithWindowInfo success browser=%p client=%p createdContainer=%d\n",
    static_cast<void*>(created),
    static_cast<void*>(client),
    createdContainer ? 1 : 0
  );
  return true;
}

bool ensureNativeBrowser(uint64_t browserId, uint64_t hostViewId, void* hostView) {
  bool shouldCreate = false;
  const bool targetHostBinding = hostView != nullptr;

  {
    CefStateLockGuard lock;
    auto* browserState = activeBrowserStateLocked(browserId);
    if (browserState == nullptr || !miumCEFIsCefRuntimeUsableLocked()) {
      return false;
    }

    if (targetHostBinding && !canBindBrowserToHostViewLocked(browserState, hostViewId, hostView)) {
      return false;
    }

    if (browserState->nativeBrowser == nullptr) {
      shouldCreate = true;
    } else if (
      targetHostBinding &&
      (!browserState->hostViewBound || browserState->hostViewId != hostViewId)
    ) {
      // This bridge does not have a supported reparent path for an already-created native CEF
      // browser across different host views, so host rebinding is modeled as replacement.
      shouldCreate = true;
    } else if (targetHostBinding) {
      return bindBrowserToHostViewLocked(browserState, hostViewId, hostView);
    }
  }

  if (!shouldCreate) {
    return true;
  }

  cef_browser_t* created = nullptr;
  cef_client_t* createdClient = nullptr;
  std::vector<void*> createdManagedSubviews;
  if (!createBrowserWithWindowInfo(hostView, &created, &createdClient, &createdManagedSubviews)) {
    return false;
  }

  bool releaseCreated = true;
  bool installed = false;
  cef_browser_t* browserToClose = nullptr;
  cef_client_t* browserToCloseClient = nullptr;
  bool shouldReplaceManagedSubviews = false;

  {
    CefStateLockGuard lock;
    installed = installNativeBrowserForHostViewLocked(
      browserId,
      hostViewId,
      hostView,
      created,
      createdClient,
      &releaseCreated,
      &shouldReplaceManagedSubviews,
      &browserToClose,
      &browserToCloseClient
    );
  }

  if (!installed && targetHostBinding && hostView != nullptr && !createdManagedSubviews.empty()) {
    const std::vector<void*> staleManagedSubviews = createdManagedSubviews;
    miumCEFNativeRunOnCefMainThread([hostView, staleManagedSubviews] {
      removeCreatedManagedBrowserSubviewsForHostView((__bridge NSView*)hostView, staleManagedSubviews);
    });
  }

  if (targetHostBinding && hostView != nullptr && installed) {
    miumCEFNativeRunOnCefMainThread([hostView, createdManagedSubviews, shouldReplaceManagedSubviews] {
      updateManagedBrowserSubviewsForHostView(
        (__bridge NSView*)hostView,
        createdManagedSubviews,
        shouldReplaceManagedSubviews
      );
    });
  }

  if (browserToClose != nullptr) {
    miumCEFNativeCloseBrowserReplacementTracked(browserToClose, browserToCloseClient);
  } else if (releaseCreated) {
    {
      CefStateLockGuard lock;
      registerPendingBrowserCloseLocked(MiumCEFNativeBrowserCloseKind::replacement);
    }
    miumCEFNativeCloseBrowserReplacementTracked(created, createdClient);
  }

  return installed;
}
