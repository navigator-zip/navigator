#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "MiumCEFBridgeNative.h"
#include "include/MiumCEFBridgeCefTypes.h"

enum class MiumCEFPermissionAttachmentSource : uint8_t {
  mediaAccess = 0,
  permissionPrompt = 1,
};

struct MiumCEFPermissionAttachment {
  MiumCEFPermissionAttachmentSource source = MiumCEFPermissionAttachmentSource::mediaAccess;
  uint32_t requestedPermissions = 0;
  uint64_t promptID = 0;
  cef_media_access_callback_t* mediaCallback = nullptr;
  cef_permission_prompt_callback_t* promptCallback = nullptr;
};

struct MiumCEFPermissionRequestHandlerState {
  MiumCEFCallbackRegistrationRef registration;
  void* context = nullptr;
  MiumCEFPermissionRequestCallback callback = nullptr;
};

struct MiumCEFPermissionSessionDismissedHandlerState {
  MiumCEFCallbackRegistrationRef registration;
  void* context = nullptr;
  MiumCEFPermissionSessionDismissedCallback callback = nullptr;
};

enum class MiumCEFPermissionExecutionKind : uint8_t {
  resolve = 0,
  finalizeWithoutResolution = 1,
};

struct MiumCEFPermissionExecutionBatch {
  uint64_t sessionID = 0;
  MiumCEFPermissionExecutionKind kind = MiumCEFPermissionExecutionKind::resolve;
  MiumCEFPermissionResolution resolution = MiumCEFPermissionResolution::cancel;
  MiumCEFPermissionSessionDismissReason dismissalReason = MiumCEFPermissionSessionDismissReason::unknown;
  bool notifyDismissedHandler = false;
  MiumCEFPermissionSessionDismissedHandlerState dismissedHandler;
  std::vector<MiumCEFPermissionAttachment> attachments;
};

void miumCEFPermissionRegisterBrowser(uint64_t browserId);
void miumCEFPermissionUnregisterBrowser(uint64_t browserId);
void miumCEFPermissionResetState(void);

MiumCEFResultCode miumCEFPermissionSetRequestHandler(
  uint64_t browserId,
  void* handlerContext,
  MiumCEFCallbackRegistrationRef registration,
  MiumCEFPermissionRequestCallback handler
);
MiumCEFResultCode miumCEFPermissionSetSessionDismissedHandler(
  uint64_t browserId,
  void* handlerContext,
  MiumCEFCallbackRegistrationRef registration,
  MiumCEFPermissionSessionDismissedCallback handler
);

inline MiumCEFResultCode miumCEFPermissionSetRequestHandler(
  uint64_t browserId,
  void* handlerContext,
  MiumCEFPermissionRequestCallback handler
) {
  return miumCEFPermissionSetRequestHandler(browserId, handlerContext, nullptr, handler);
}

inline MiumCEFResultCode miumCEFPermissionSetSessionDismissedHandler(
  uint64_t browserId,
  void* handlerContext,
  MiumCEFPermissionSessionDismissedCallback handler
) {
  return miumCEFPermissionSetSessionDismissedHandler(browserId, handlerContext, nullptr, handler);
}

bool miumCEFPermissionHandleMediaAccessRequest(
  uint64_t browserId,
  const std::string& requestingOrigin,
  const std::string& topLevelOrigin,
  const std::string& frameIdentifier,
  uint32_t requestedPermissions,
  bool mediaStreamOverrideEnabled,
  cef_media_access_callback_t* callback
);
bool miumCEFPermissionHandleShowPromptRequest(
  uint64_t browserId,
  const std::string& requestingOrigin,
  const std::string& topLevelOrigin,
  uint64_t promptID,
  uint32_t requestedPermissions,
  bool mediaStreamOverrideEnabled,
  cef_permission_prompt_callback_t* callback
);

bool miumCEFPermissionTakePromptDismissalBatch(
  uint64_t browserId,
  uint64_t promptID,
  MiumCEFPermissionSessionDismissReason reason,
  MiumCEFPermissionExecutionBatch* outBatch
);
void miumCEFPermissionTakeBrowserDismissalBatches(
  uint64_t browserId,
  MiumCEFPermissionSessionDismissReason reason,
  bool notifyDismissedHandler,
  std::vector<MiumCEFPermissionExecutionBatch>* outBatches
);
void miumCEFPermissionTakeNavigationDismissalBatches(
  uint64_t browserId,
  const std::string& nextTopLevelOrigin,
  std::vector<MiumCEFPermissionExecutionBatch>* outBatches
);
bool miumCEFPermissionTakeResolutionBatch(
  MiumCEFPermissionSessionID sessionID,
  MiumCEFPermissionResolution resolution,
  MiumCEFPermissionSessionDismissReason dismissalReason,
  bool notifyDismissedHandler,
  MiumCEFPermissionExecutionBatch* outBatch
);

void miumCEFPermissionExecuteBatch(MiumCEFPermissionExecutionBatch* batch);

size_t miumCEFPermissionActiveSessionCount(void);
bool miumCEFPermissionHasActiveSession(MiumCEFPermissionSessionID sessionID);

#if defined(MIUM_CEF_BRIDGE_TESTING)
void miumCEFPermissionSetNextSessionIDForTesting(uint64_t sessionId);
void miumCEFPermissionInjectDanglingBrowserSessionForTesting(
  uint64_t browserId,
  uint64_t sessionId
);
void miumCEFPermissionInjectNullBrowserForTesting(uint64_t browserId);
void miumCEFPermissionInjectNullSessionForTesting(uint64_t sessionId);
#endif
