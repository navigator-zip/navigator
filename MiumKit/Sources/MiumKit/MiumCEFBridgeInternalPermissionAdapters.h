#pragma once

#include <vector>

#include "MiumCEFBridgePermissions.h"

void miumCEFNativeExecutePermissionBatchOnCefMainThread(MiumCEFPermissionExecutionBatch&& batch);
void miumCEFNativeExecutePermissionBatchesOnCefMainThread(std::vector<MiumCEFPermissionExecutionBatch>&& batches);
