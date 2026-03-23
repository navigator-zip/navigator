#include "Tracing.h"

#include <cstdio>
#include <cstdlib>

bool miumCefTracingEnabled() {
  const char* enabled = std::getenv("MIUM_CEF_ENABLE_LOGGING");
  return enabled != nullptr && enabled[0] != '\0' && enabled[0] != '0';
}

void miumCefTraceV(const char* component, const char* format, va_list args) {
  if (!miumCefTracingEnabled()) {
    return;
  }
  std::fprintf(stderr, "[MiumCEFTrace][%s] ", component == nullptr ? "unknown" : component);
  std::vfprintf(stderr, format, args);
}

void miumCefTrace(const char* component, const char* format, ...) {
  va_list args;
  va_start(args, format);
  miumCefTraceV(component, format, args);
  va_end(args);
}
