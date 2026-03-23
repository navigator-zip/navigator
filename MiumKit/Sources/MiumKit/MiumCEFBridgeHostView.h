#pragma once

#import <AppKit/AppKit.h>

#include <functional>
#include <string>
#include <vector>

#include "MiumCEFBridgeAuxiliaryState.h"
#include "MiumCEFBridgeStateModels.h"

@interface MiumBrowserContainerView : NSView
@end

struct MiumCEFSnapshotOptions {
  NSBitmapImageFileType bitmapFileType = NSBitmapImageFileTypePNG;
  CGFloat jpegCompressionFactor = 0.92;
  bool usesJPEGCompressionFactor = false;
  bool captureAsPDF = false;
  bool hasClipRect = false;
  NSRect clipRect = NSZeroRect;
};

void removeManagedBrowserSubviewsForHostView(NSView* hostView);
void removeAllManagedBrowserSubviews(void);
void resizeEmbeddedBrowserHostView(NSView* hostView, int pixelWidth, int pixelHeight);
double backingScaleFactorForHostView(NSView* hostView);
NSData* snapshotDataForHostView(
  NSView* hostView,
  const MiumCEFSnapshotOptions& options,
  NSString** errorOut
);
bool configureSnapshotFormat(
  NSString* format,
  MiumCEFSnapshotOptions* outOptions,
  NSString** errorOut
);
bool parseSnapshotOptions(
  const char* jsonOptions,
  NSString* outputPath,
  MiumCEFSnapshotOptions* outOptions,
  NSString** errorOut
);
NSRect snapshotBoundsForHostView(
  NSView* hostView,
  const MiumCEFSnapshotOptions& options,
  NSString** errorOut
);
NSBitmapImageRep* snapshotBitmapRepForHostViewFromWindow(NSView* hostView, NSRect bounds);
bool createBrowserWithWindowInfo(
  void* hostView,
  cef_browser_t** outBrowser,
  cef_client_t** outClient,
  std::vector<void*>* outCreatedManagedSubviews = nullptr
);
bool ensureNativeBrowser(uint64_t browserId, uint64_t hostViewId, void* hostView);
