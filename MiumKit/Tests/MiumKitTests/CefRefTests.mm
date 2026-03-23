#import "MiumCEFBridgeNativeTestSupport.h"

#include "../../Sources/MiumKit/CefRef.h"

using namespace MiumCEFBridgeNativeTestSupport;

namespace {

struct ReentrantCefRefOwner {
  CefRef<cef_browser_t> value;
  int reentrantResetCalls = 0;
};

} // namespace

@interface CefRefTests : XCTestCase
@end

@implementation CefRefTests

- (void)testResetClearsOwnedPointerBeforeReentrantReleaseCallbackRuns {
  FakeBrowserHarness harness;
  ReentrantCefRefOwner owner;
  owner.value = CefRef<cef_browser_t>::adopt(&harness.browser->browser);
  harness.browser->lifetime.onFinalRelease = [&owner]() {
    owner.reentrantResetCalls += 1;
    owner.value.reset();
  };

  owner.value.reset();

  XCTAssertEqual(owner.reentrantResetCalls, 1);
  XCTAssertEqual(owner.value.get(), nullptr);
  XCTAssertEqual(harness.browser->lifetime.finalReleaseCount.load(std::memory_order_relaxed), 1);
  XCTAssertEqual(harness.browser->lifetime.refCount.load(std::memory_order_relaxed), 0);
}

@end
