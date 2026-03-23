#include "MiumCEFBridgePermissions.h"

#include <cstddef>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "CefRef.h"
#include "Tracing.h"

namespace {

struct MiumCEFPermissionSessionState {
  uint64_t id = 0;
  uint64_t browserId = 0;
  uint64_t promptID = 0;
  std::string dedupeKey;
  std::string requestingOrigin;
  std::string topLevelOrigin;
  std::string frameIdentifier;
  uint32_t permissionFlags = 0;
  uint32_t source = 0;
  std::vector<MiumCEFPermissionAttachment> attachments;
};

struct MiumCEFPermissionBrowserState {
  MiumCEFPermissionRequestHandlerState requestHandler;
  MiumCEFPermissionSessionDismissedHandlerState dismissedHandler;
  std::unordered_set<uint64_t> sessionIDs;
};

struct MiumCEFPermissionNormalizationResult {
  uint32_t flags = 0;
  bool hasUnsupportedBits = false;
};

static std::mutex gPermissionMutex;
static uint64_t gNextPermissionSessionId = 1;
static std::unordered_map<uint64_t, std::unique_ptr<MiumCEFPermissionBrowserState>> gPermissionBrowsers;
static std::unordered_map<uint64_t, std::unique_ptr<MiumCEFPermissionSessionState>> gPermissionSessions;
static std::unordered_map<std::string, uint64_t> gPermissionSessionIDByDedupeKey;

static void releasePermissionAttachments(std::vector<MiumCEFPermissionAttachment>& attachments) {
  for (auto& attachment : attachments) {
    releaseOwnedCefValue(attachment.mediaCallback);
    releaseOwnedCefValue(attachment.promptCallback);
    attachment.mediaCallback = nullptr;
    attachment.promptCallback = nullptr;
  }
}

static MiumCEFPermissionNormalizationResult normalizeMediaPermissions(uint32_t requestedPermissions) {
  constexpr uint32_t supportedMask =
    CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE |
    CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;

  MiumCEFPermissionNormalizationResult result;
  result.hasUnsupportedBits = (requestedPermissions & ~supportedMask) != 0;
  if ((requestedPermissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) != 0) {
    result.flags |= static_cast<uint32_t>(MiumCEFPermissionKindFlags::camera);
  }
  if ((requestedPermissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) != 0) {
    result.flags |= static_cast<uint32_t>(MiumCEFPermissionKindFlags::microphone);
  }
  return result;
}

static MiumCEFPermissionNormalizationResult normalizePromptPermissions(uint32_t requestedPermissions) {
  constexpr uint32_t supportedMask =
    CEF_PERMISSION_TYPE_CAMERA_STREAM |
    CEF_PERMISSION_TYPE_MIC_STREAM |
    CEF_PERMISSION_TYPE_GEOLOCATION;

  MiumCEFPermissionNormalizationResult result;
  result.hasUnsupportedBits = (requestedPermissions & ~supportedMask) != 0;
  if ((requestedPermissions & CEF_PERMISSION_TYPE_CAMERA_STREAM) != 0) {
    result.flags |= static_cast<uint32_t>(MiumCEFPermissionKindFlags::camera);
  }
  if ((requestedPermissions & CEF_PERMISSION_TYPE_MIC_STREAM) != 0) {
    result.flags |= static_cast<uint32_t>(MiumCEFPermissionKindFlags::microphone);
  }
  if ((requestedPermissions & CEF_PERMISSION_TYPE_GEOLOCATION) != 0) {
    result.flags |= static_cast<uint32_t>(MiumCEFPermissionKindFlags::geolocation);
  }
  return result;
}

static bool shouldAutoAllowForMediaStreamOverride(
  const MiumCEFPermissionNormalizationResult& normalization,
  bool mediaStreamOverrideEnabled
) {
  if (!mediaStreamOverrideEnabled || normalization.hasUnsupportedBits || normalization.flags == 0) {
    return false;
  }

  const uint32_t mediaFlags =
    static_cast<uint32_t>(MiumCEFPermissionKindFlags::camera) |
    static_cast<uint32_t>(MiumCEFPermissionKindFlags::microphone);
  return (normalization.flags & ~mediaFlags) == 0;
}

static std::string permissionSessionDedupeKey(
  uint64_t browserId,
  const std::string& requestingOrigin,
  const std::string& topLevelOrigin,
  uint32_t permissionFlags
) {
  // Multiple requests with identical permission flags and origins are coalesced into a single
  // permission session for the same logical browser.
  return
    std::to_string(browserId) + "|" +
    std::to_string(permissionFlags) + "|" +
    requestingOrigin + "|" +
    topLevelOrigin;
}

static std::unique_ptr<MiumCEFPermissionSessionState> removePermissionSessionLocked(
  uint64_t sessionId,
  MiumCEFPermissionSessionDismissedHandlerState* outDismissedHandler
) {
  auto sessionIter = gPermissionSessions.find(sessionId);
  if (sessionIter == gPermissionSessions.end()) {
    return nullptr;
  }

  auto session = std::move(sessionIter->second);
  gPermissionSessions.erase(sessionIter);

  if (!session->dedupeKey.empty()) {
    const auto dedupeIter = gPermissionSessionIDByDedupeKey.find(session->dedupeKey);
    if (dedupeIter != gPermissionSessionIDByDedupeKey.end() && dedupeIter->second == sessionId) {
      gPermissionSessionIDByDedupeKey.erase(dedupeIter);
    }
  }

  const auto browserIter = gPermissionBrowsers.find(session->browserId);
  if (browserIter != gPermissionBrowsers.end() && browserIter->second != nullptr) {
    browserIter->second->sessionIDs.erase(sessionId);
    if (outDismissedHandler != nullptr) {
      *outDismissedHandler = browserIter->second->dismissedHandler;
    }
  }

  return session;
}

static bool buildExecutionBatchLocked(
  uint64_t sessionId,
  MiumCEFPermissionExecutionKind kind,
  MiumCEFPermissionResolution resolution,
  MiumCEFPermissionSessionDismissReason dismissalReason,
  bool notifyDismissedHandler,
  MiumCEFPermissionExecutionBatch* outBatch
) {
  if (outBatch == nullptr) {
    return false;
  }

  MiumCEFPermissionSessionDismissedHandlerState dismissedHandler;
  auto session = removePermissionSessionLocked(
    sessionId,
    notifyDismissedHandler ? &dismissedHandler : nullptr
  );
  if (session == nullptr) {
    return false;
  }

  outBatch->sessionID = session->id;
  outBatch->kind = kind;
  outBatch->resolution = resolution;
  outBatch->dismissalReason = dismissalReason;
  outBatch->notifyDismissedHandler = notifyDismissedHandler;
  outBatch->dismissedHandler = dismissedHandler;
  outBatch->attachments = std::move(session->attachments);
  return true;
}

static uint64_t nextPermissionSessionIDLocked(void) {
  while (true) {
    if (gNextPermissionSessionId == 0) {
      gNextPermissionSessionId = 1;
    }
    const uint64_t candidate = gNextPermissionSessionId++;
    if (gPermissionSessions.find(candidate) == gPermissionSessions.end()) {
      return candidate;
    }
  }
}

static bool handleDeniedRequest(
  uint32_t promptResult,
  uint32_t mediaPermissions,
  cef_permission_prompt_callback_t* promptCallback,
  cef_media_access_callback_t* mediaCallback
) {
  if (promptCallback != nullptr && promptCallback->cont != nullptr) {
    promptCallback->cont(promptCallback, static_cast<cef_permission_request_result_t>(promptResult));
    return true;
  }
  if (mediaCallback != nullptr && mediaCallback->cont != nullptr) {
    mediaCallback->cont(mediaCallback, mediaPermissions);
    return true;
  }
  return false;
}

static bool bridgePermissionRequest(
  uint64_t browserId,
  const std::string& requestingOrigin,
  const std::string& topLevelOrigin,
  const std::string& frameIdentifier,
  uint32_t permissionFlags,
  uint32_t source,
  uint32_t requestedPermissions,
  uint64_t promptID,
  cef_media_access_callback_t* mediaCallback,
  cef_permission_prompt_callback_t* promptCallback
) {
  MiumCEFPermissionRequestHandlerState requestHandler;
  uint64_t sessionId = 0;
  bool shouldDenyImmediately = false;

  {
    std::lock_guard<std::mutex> lock(gPermissionMutex);
    const auto browserIter = gPermissionBrowsers.find(browserId);
    if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
      return false;
    }

    requestHandler = browserIter->second->requestHandler;
    if (requestHandler.callback == nullptr
        || (requestHandler.registration != nullptr
            && !requestHandler.registration->active.load(std::memory_order_acquire))) {
      shouldDenyImmediately = true;
    }
    else {
      const std::string dedupeKey = permissionSessionDedupeKey(
        browserId,
        requestingOrigin,
        topLevelOrigin,
        permissionFlags
      );
      const auto dedupeIter = gPermissionSessionIDByDedupeKey.find(dedupeKey);
      if (dedupeIter != gPermissionSessionIDByDedupeKey.end()) {
        const auto sessionIter = gPermissionSessions.find(dedupeIter->second);
        if (sessionIter != gPermissionSessions.end() && sessionIter->second != nullptr) {
          MiumCEFPermissionAttachment attachment;
          attachment.source = source == static_cast<uint32_t>(MiumCEFPermissionRequestSource::permissionPrompt)
            ? MiumCEFPermissionAttachmentSource::permissionPrompt
            : MiumCEFPermissionAttachmentSource::mediaAccess;
          attachment.requestedPermissions = requestedPermissions;
          attachment.promptID = promptID;
          attachment.mediaCallback = retainCefBorrowed(mediaCallback);
          attachment.promptCallback = retainCefBorrowed(promptCallback);
          sessionIter->second->attachments.push_back(attachment);
          return true;
        }
      }

      sessionId = nextPermissionSessionIDLocked();
      auto session = std::make_unique<MiumCEFPermissionSessionState>();
      session->id = sessionId;
      session->browserId = browserId;
      session->promptID = promptID;
      session->dedupeKey = dedupeKey;
      session->requestingOrigin = requestingOrigin;
      session->topLevelOrigin = topLevelOrigin;
      session->frameIdentifier = frameIdentifier;
      session->permissionFlags = permissionFlags;
      session->source = source;

      MiumCEFPermissionAttachment attachment;
      attachment.source = source == static_cast<uint32_t>(MiumCEFPermissionRequestSource::permissionPrompt)
        ? MiumCEFPermissionAttachmentSource::permissionPrompt
        : MiumCEFPermissionAttachmentSource::mediaAccess;
      attachment.requestedPermissions = requestedPermissions;
      attachment.promptID = promptID;
      attachment.mediaCallback = retainCefBorrowed(mediaCallback);
      attachment.promptCallback = retainCefBorrowed(promptCallback);
      session->attachments.push_back(attachment);

      browserIter->second->sessionIDs.insert(sessionId);
      gPermissionSessionIDByDedupeKey[dedupeKey] = sessionId;
      gPermissionSessions[sessionId] = std::move(session);
    }
  }

  if (shouldDenyImmediately) {
    return handleDeniedRequest(
      CEF_PERMISSION_RESULT_DENY,
      0,
      promptCallback,
      mediaCallback
    );
  }

  MiumCEFPermissionRequest request{};
  request.sessionID = sessionId;
  request.browserID = browserId;
  request.promptID = promptID;
  request.frameIdentifier = frameIdentifier.empty() ? nullptr : frameIdentifier.c_str();
  request.permissionFlags = permissionFlags;
  request.source = source;
  request.requestingOrigin = requestingOrigin.empty() ? nullptr : requestingOrigin.c_str();
  request.topLevelOrigin = topLevelOrigin.empty() ? nullptr : topLevelOrigin.c_str();
  if (requestHandler.registration != nullptr
      && !requestHandler.registration->active.load(std::memory_order_acquire)) {
    MiumCEFPermissionExecutionBatch batch;
    if (miumCEFPermissionTakeResolutionBatch(
          sessionId,
          MiumCEFPermissionResolution::cancel,
          MiumCEFPermissionSessionDismissReason::unknown,
          false,
          &batch
        )) {
      miumCEFPermissionExecuteBatch(&batch);
    }
    return true;
  }
  requestHandler.callback(requestHandler.context, &request);
  return true;
}

} // namespace

void miumCEFPermissionRegisterBrowser(uint64_t browserId) {
  if (browserId == 0) {
    return;
  }

  miumCefTrace("permissions", "register browser=%llu\n", static_cast<unsigned long long>(browserId));
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  gPermissionBrowsers[browserId] = std::make_unique<MiumCEFPermissionBrowserState>();
}

void miumCEFPermissionUnregisterBrowser(uint64_t browserId) {
  std::vector<MiumCEFPermissionExecutionBatch> orphanedBatches;
  miumCefTrace("permissions", "unregister browser=%llu\n", static_cast<unsigned long long>(browserId));

  {
    std::lock_guard<std::mutex> lock(gPermissionMutex);
    const auto browserIter = gPermissionBrowsers.find(browserId);
    if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
      return;
    }

    const std::vector<uint64_t> sessionIDs(
      browserIter->second->sessionIDs.begin(),
      browserIter->second->sessionIDs.end()
    );
    gPermissionBrowsers.erase(browserIter);

    for (const uint64_t sessionId : sessionIDs) {
      MiumCEFPermissionExecutionBatch batch;
      if (buildExecutionBatchLocked(
            sessionId,
            MiumCEFPermissionExecutionKind::finalizeWithoutResolution,
            MiumCEFPermissionResolution::cancel,
            MiumCEFPermissionSessionDismissReason::unknown,
            false,
            &batch
          )) {
        orphanedBatches.push_back(std::move(batch));
      }
    }
  }

  for (auto& batch : orphanedBatches) {
    miumCEFPermissionExecuteBatch(&batch);
  }
}

void miumCEFPermissionResetState(void) {
  std::vector<MiumCEFPermissionExecutionBatch> batches;
  miumCefTrace("permissions", "reset state\n");

  {
    std::lock_guard<std::mutex> lock(gPermissionMutex);
    gNextPermissionSessionId = 1;
    gPermissionBrowsers.clear();
    for (const auto& sessionPair : gPermissionSessions) {
      if (sessionPair.second == nullptr) {
        continue;
      }
      MiumCEFPermissionExecutionBatch batch;
      batch.sessionID = sessionPair.first;
      batch.kind = MiumCEFPermissionExecutionKind::finalizeWithoutResolution;
      batch.resolution = MiumCEFPermissionResolution::cancel;
      batch.dismissalReason = MiumCEFPermissionSessionDismissReason::unknown;
      batch.attachments = std::move(sessionPair.second->attachments);
      batches.push_back(std::move(batch));
    }
    gPermissionSessions.clear();
    gPermissionSessionIDByDedupeKey.clear();
  }

  for (auto& batch : batches) {
    miumCEFPermissionExecuteBatch(&batch);
  }
}

MiumCEFResultCode miumCEFPermissionSetRequestHandler(
  uint64_t browserId,
  void* handlerContext,
  MiumCEFCallbackRegistrationRef registration,
  MiumCEFPermissionRequestCallback handler
) {
  if (browserId == 0) {
    return MiumCEFResultInvalidArgument;
  }

  miumCefTrace("permissions", "set request handler browser=%llu installed=%d\n",
    static_cast<unsigned long long>(browserId),
    handler != nullptr ? 1 : 0);
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  const auto browserIter = gPermissionBrowsers.find(browserId);
  if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
    return MiumCEFResultNotInitialized;
  }
  if (browserIter->second->requestHandler.registration != nullptr) {
    browserIter->second->requestHandler.registration->active.store(false, std::memory_order_release);
  }
  browserIter->second->requestHandler.registration = std::move(registration);
  browserIter->second->requestHandler.context = handlerContext;
  browserIter->second->requestHandler.callback = handler;
  return MiumCEFResultOK;
}

MiumCEFResultCode miumCEFPermissionSetSessionDismissedHandler(
  uint64_t browserId,
  void* handlerContext,
  MiumCEFCallbackRegistrationRef registration,
  MiumCEFPermissionSessionDismissedCallback handler
) {
  if (browserId == 0) {
    return MiumCEFResultInvalidArgument;
  }

  miumCefTrace("permissions", "set dismissed handler browser=%llu installed=%d\n",
    static_cast<unsigned long long>(browserId),
    handler != nullptr ? 1 : 0);
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  const auto browserIter = gPermissionBrowsers.find(browserId);
  if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
    return MiumCEFResultNotInitialized;
  }
  if (browserIter->second->dismissedHandler.registration != nullptr) {
    browserIter->second->dismissedHandler.registration->active.store(false, std::memory_order_release);
  }
  browserIter->second->dismissedHandler.registration = std::move(registration);
  browserIter->second->dismissedHandler.context = handlerContext;
  browserIter->second->dismissedHandler.callback = handler;
  return MiumCEFResultOK;
}

bool miumCEFPermissionHandleMediaAccessRequest(
  uint64_t browserId,
  const std::string& requestingOrigin,
  const std::string& topLevelOrigin,
  const std::string& frameIdentifier,
  uint32_t requestedPermissions,
  bool mediaStreamOverrideEnabled,
  cef_media_access_callback_t* callback
) {
  if (browserId == 0) {
    return false;
  }

  miumCefTrace("permissions", "media request browser=%llu requested=%u override=%d\n",
    static_cast<unsigned long long>(browserId),
    requestedPermissions,
    mediaStreamOverrideEnabled ? 1 : 0);
  const MiumCEFPermissionNormalizationResult normalization =
    normalizeMediaPermissions(requestedPermissions);
  if (shouldAutoAllowForMediaStreamOverride(normalization, mediaStreamOverrideEnabled)) {
    if (callback != nullptr && callback->cont != nullptr) {
      callback->cont(callback, requestedPermissions);
    }
    return true;
  }

  if (normalization.hasUnsupportedBits || normalization.flags == 0) {
    return handleDeniedRequest(
      CEF_PERMISSION_RESULT_DENY,
      0,
      nullptr,
      callback
    );
  }

  return bridgePermissionRequest(
    browserId,
    requestingOrigin,
    topLevelOrigin,
    frameIdentifier,
    normalization.flags,
    static_cast<uint32_t>(MiumCEFPermissionRequestSource::mediaAccess),
    requestedPermissions,
    0,
    callback,
    nullptr
  );
}

bool miumCEFPermissionHandleShowPromptRequest(
  uint64_t browserId,
  const std::string& requestingOrigin,
  const std::string& topLevelOrigin,
  uint64_t promptID,
  uint32_t requestedPermissions,
  bool mediaStreamOverrideEnabled,
  cef_permission_prompt_callback_t* callback
) {
  if (browserId == 0) {
    return false;
  }

  miumCefTrace("permissions", "prompt request browser=%llu prompt=%llu requested=%u override=%d\n",
    static_cast<unsigned long long>(browserId),
    static_cast<unsigned long long>(promptID),
    requestedPermissions,
    mediaStreamOverrideEnabled ? 1 : 0);
  const MiumCEFPermissionNormalizationResult normalization =
    normalizePromptPermissions(requestedPermissions);
  if (shouldAutoAllowForMediaStreamOverride(normalization, mediaStreamOverrideEnabled)) {
    if (callback != nullptr && callback->cont != nullptr) {
      callback->cont(callback, CEF_PERMISSION_RESULT_ACCEPT);
    }
    return true;
  }

  if (normalization.hasUnsupportedBits || normalization.flags == 0) {
    return handleDeniedRequest(
      CEF_PERMISSION_RESULT_DENY,
      0,
      callback,
      nullptr
    );
  }

  return bridgePermissionRequest(
    browserId,
    requestingOrigin,
    topLevelOrigin,
    std::string(),
    normalization.flags,
    static_cast<uint32_t>(MiumCEFPermissionRequestSource::permissionPrompt),
    requestedPermissions,
    promptID,
    nullptr,
    callback
  );
}

bool miumCEFPermissionTakePromptDismissalBatch(
  uint64_t browserId,
  uint64_t promptID,
  MiumCEFPermissionSessionDismissReason reason,
  MiumCEFPermissionExecutionBatch* outBatch
) {
  if (outBatch == nullptr) {
    return false;
  }

  std::lock_guard<std::mutex> lock(gPermissionMutex);
  const auto browserIter = gPermissionBrowsers.find(browserId);
  if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
    return false;
  }

  for (const uint64_t sessionId : browserIter->second->sessionIDs) {
    const auto sessionIter = gPermissionSessions.find(sessionId);
    if (sessionIter == gPermissionSessions.end() || sessionIter->second == nullptr) {
      continue;
    }
    for (const auto& attachment : sessionIter->second->attachments) {
      if (attachment.source == MiumCEFPermissionAttachmentSource::permissionPrompt && attachment.promptID == promptID) {
        return buildExecutionBatchLocked(
          sessionId,
          MiumCEFPermissionExecutionKind::finalizeWithoutResolution,
          MiumCEFPermissionResolution::cancel,
          reason,
          true,
          outBatch
        );
      }
    }
  }

  return false;
}

void miumCEFPermissionTakeBrowserDismissalBatches(
  uint64_t browserId,
  MiumCEFPermissionSessionDismissReason reason,
  bool notifyDismissedHandler,
  std::vector<MiumCEFPermissionExecutionBatch>* outBatches
) {
  if (outBatches == nullptr) {
    return;
  }

  miumCefTrace("permissions", "browser dismissal browser=%llu reason=%u notify=%d\n",
    static_cast<unsigned long long>(browserId),
    static_cast<unsigned int>(reason),
    notifyDismissedHandler ? 1 : 0);
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  const auto browserIter = gPermissionBrowsers.find(browserId);
  if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
    return;
  }

  const std::vector<uint64_t> sessionIDs(
    browserIter->second->sessionIDs.begin(),
    browserIter->second->sessionIDs.end()
  );
  for (const uint64_t sessionId : sessionIDs) {
    MiumCEFPermissionExecutionBatch batch;
    if (buildExecutionBatchLocked(
          sessionId,
          MiumCEFPermissionExecutionKind::resolve,
          MiumCEFPermissionResolution::cancel,
          reason,
          notifyDismissedHandler,
          &batch
        )) {
      outBatches->push_back(std::move(batch));
    }
  }
}

void miumCEFPermissionTakeNavigationDismissalBatches(
  uint64_t browserId,
  const std::string& nextTopLevelOrigin,
  std::vector<MiumCEFPermissionExecutionBatch>* outBatches
) {
  if (outBatches == nullptr) {
    return;
  }

  miumCefTrace("permissions", "navigation dismissal browser=%llu nextTopLevelOrigin=%s\n",
    static_cast<unsigned long long>(browserId),
    nextTopLevelOrigin.c_str());
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  const auto browserIter = gPermissionBrowsers.find(browserId);
  if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
    return;
  }

  std::vector<uint64_t> sessionIDs;
  for (const uint64_t sessionId : browserIter->second->sessionIDs) {
    const auto sessionIter = gPermissionSessions.find(sessionId);
    if (sessionIter == gPermissionSessions.end() || sessionIter->second == nullptr) {
      continue;
    }
    const auto& session = *sessionIter->second;
    if (
      session.topLevelOrigin.empty() ||
      nextTopLevelOrigin.empty() ||
      session.topLevelOrigin != nextTopLevelOrigin
    ) {
      sessionIDs.push_back(sessionId);
    }
  }

  for (const uint64_t sessionId : sessionIDs) {
    MiumCEFPermissionExecutionBatch batch;
    if (buildExecutionBatchLocked(
          sessionId,
          MiumCEFPermissionExecutionKind::resolve,
          MiumCEFPermissionResolution::cancel,
          MiumCEFPermissionSessionDismissReason::mainFrameNavigation,
          true,
          &batch
        )) {
      outBatches->push_back(std::move(batch));
    }
  }
}

bool miumCEFPermissionTakeResolutionBatch(
  MiumCEFPermissionSessionID sessionID,
  MiumCEFPermissionResolution resolution,
  MiumCEFPermissionSessionDismissReason dismissalReason,
  bool notifyDismissedHandler,
  MiumCEFPermissionExecutionBatch* outBatch
) {
  miumCefTrace("permissions", "resolve session=%llu resolution=%u dismissal=%u notify=%d\n",
    static_cast<unsigned long long>(sessionID),
    static_cast<unsigned int>(resolution),
    static_cast<unsigned int>(dismissalReason),
    notifyDismissedHandler ? 1 : 0);
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  return buildExecutionBatchLocked(
    sessionID,
    MiumCEFPermissionExecutionKind::resolve,
    resolution,
    dismissalReason,
    notifyDismissedHandler,
    outBatch
  );
}

void miumCEFPermissionExecuteBatch(MiumCEFPermissionExecutionBatch* batch) {
  if (batch == nullptr) {
    return;
  }

  miumCefTrace("permissions", "execute batch session=%llu kind=%u resolution=%u dismissal=%u attachments=%zu\n",
    static_cast<unsigned long long>(batch->sessionID),
    static_cast<unsigned int>(batch->kind),
    static_cast<unsigned int>(batch->resolution),
    static_cast<unsigned int>(batch->dismissalReason),
    batch->attachments.size());
  if (batch->kind == MiumCEFPermissionExecutionKind::resolve) {
    for (auto& attachment : batch->attachments) {
      switch (attachment.source) {
        case MiumCEFPermissionAttachmentSource::mediaAccess:
          if (attachment.mediaCallback == nullptr) {
            break;
          }
          if (batch->resolution == MiumCEFPermissionResolution::allow) {
            if (attachment.mediaCallback->cont != nullptr) {
              attachment.mediaCallback->cont(attachment.mediaCallback, attachment.requestedPermissions);
            }
          }
          else if (batch->resolution == MiumCEFPermissionResolution::deny) {
            if (attachment.mediaCallback->cont != nullptr) {
              attachment.mediaCallback->cont(attachment.mediaCallback, 0);
            }
          }
          else if (attachment.mediaCallback->cancel != nullptr) {
            attachment.mediaCallback->cancel(attachment.mediaCallback);
          }
          break;
        case MiumCEFPermissionAttachmentSource::permissionPrompt:
          if (attachment.promptCallback == nullptr || attachment.promptCallback->cont == nullptr) {
            break;
          }
          cef_permission_request_result_t result = CEF_PERMISSION_RESULT_DISMISS;
          if (batch->resolution == MiumCEFPermissionResolution::allow) {
            result = CEF_PERMISSION_RESULT_ACCEPT;
          }
          else if (batch->resolution == MiumCEFPermissionResolution::deny) {
            result = CEF_PERMISSION_RESULT_DENY;
          }
          attachment.promptCallback->cont(attachment.promptCallback, result);
          break;
      }
    }
  }

  releasePermissionAttachments(batch->attachments);
  if (batch->notifyDismissedHandler
      && batch->dismissedHandler.callback != nullptr
      && (batch->dismissedHandler.registration == nullptr
          || batch->dismissedHandler.registration->active.load(std::memory_order_acquire))) {
    batch->dismissedHandler.callback(
      batch->dismissedHandler.context,
      batch->sessionID,
      static_cast<uint32_t>(batch->dismissalReason)
    );
  }
  if (batch->dismissedHandler.registration != nullptr) {
    batch->dismissedHandler.registration->active.store(false, std::memory_order_release);
  }
  batch->attachments.clear();
  batch->dismissedHandler = {};
}

size_t miumCEFPermissionActiveSessionCount(void) {
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  return gPermissionSessions.size();
}

bool miumCEFPermissionHasActiveSession(MiumCEFPermissionSessionID sessionID) {
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  return gPermissionSessions.find(sessionID) != gPermissionSessions.end();
}

#if defined(MIUM_CEF_BRIDGE_TESTING)

void miumCEFPermissionSetNextSessionIDForTesting(uint64_t sessionId) {
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  gNextPermissionSessionId = sessionId;
}

void miumCEFPermissionInjectDanglingBrowserSessionForTesting(
  uint64_t browserId,
  uint64_t sessionId
) {
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  const auto browserIter = gPermissionBrowsers.find(browserId);
  if (browserIter == gPermissionBrowsers.end() || browserIter->second == nullptr) {
    return;
  }
  browserIter->second->sessionIDs.insert(sessionId);
}

void miumCEFPermissionInjectNullBrowserForTesting(uint64_t browserId) {
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  gPermissionBrowsers[browserId] = nullptr;
}

void miumCEFPermissionInjectNullSessionForTesting(uint64_t sessionId) {
  std::lock_guard<std::mutex> lock(gPermissionMutex);
  gPermissionSessions[sessionId] = nullptr;
}

#endif
