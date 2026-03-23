#pragma once

#include <cstdarg>

bool miumCefTracingEnabled();
void miumCefTrace(const char* component, const char* format, ...);
void miumCefTraceV(const char* component, const char* format, va_list args);
