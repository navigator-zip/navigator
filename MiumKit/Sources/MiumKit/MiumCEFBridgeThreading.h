#pragma once

#include <functional>

const char* miumCEFThreadLaneLabel();
void miumCEFRunOnCefExecutor(std::function<void()> fn);
void miumCEFRunOnCefExecutorAsync(std::function<void()> fn);
void miumCEFRunOnCefMainThread(std::function<void()> fn);
