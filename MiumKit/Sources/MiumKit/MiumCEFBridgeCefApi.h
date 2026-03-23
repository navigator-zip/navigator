#pragma once

#include "include/MiumCEFBridgeCefTypes.h"
#include "include/cef_api_hash.h"
#include "include/cef_version_info.h"

using CefApiHashFn = decltype(&cef_api_hash);
using CefApiVersionFn = decltype(&cef_api_version);
using CefVersionInfoFn = decltype(&cef_version_info);
using CefStringUTF8ToUTF16 = decltype(&cef_string_utf8_to_utf16);
using CefStringUTF16Clear = decltype(&cef_string_utf16_clear);
using CefStringUserFreeUTF16Free = decltype(&cef_string_userfree_utf16_free);
using CefStringListSizeFn = decltype(&cef_string_list_size);
using CefStringListValueFn = decltype(&cef_string_list_value);
using CefInitializeFn = decltype(&cef_initialize);
using CefExecuteProcessFn = decltype(&cef_execute_process);
using CefShutdownFn = decltype(&cef_shutdown);
using CefBrowserCreateBrowserSyncFn = decltype(&cef_browser_host_create_browser_sync);
using CefProcessMessageCreateFn = decltype(&cef_process_message_create);
using CefDoMessageLoopWorkFn = decltype(&cef_do_message_loop_work);
using CefV8ValueCreateFunctionFn = decltype(&cef_v8_value_create_function);
using CefV8ContextGetCurrentContextFn = decltype(&cef_v8_context_get_current_context);

struct CefApi {
  bool loaded = false;
  void* frameworkHandle = nullptr;
  CefVersionInfoFn versionInfo = nullptr;
  CefApiHashFn apiHash = nullptr;
  CefApiVersionFn apiVersion = nullptr;
  CefStringUTF8ToUTF16 utf8ToUTF16 = nullptr;
  CefStringUTF16Clear utf16Clear = nullptr;
  CefStringUserFreeUTF16Free userfreeFree = nullptr;
  CefStringListSizeFn stringListSize = nullptr;
  CefStringListValueFn stringListValue = nullptr;
  CefInitializeFn initialize = nullptr;
  CefExecuteProcessFn executeProcess = nullptr;
  CefShutdownFn shutdown = nullptr;
  CefDoMessageLoopWorkFn doMessageLoopWork = nullptr;
  CefBrowserCreateBrowserSyncFn createBrowserSync = nullptr;
  CefProcessMessageCreateFn createProcessMessage = nullptr;
  CefV8ValueCreateFunctionFn createV8Function = nullptr;
  CefV8ContextGetCurrentContextFn currentV8Context = nullptr;

  void reset() {
    loaded = false;
    frameworkHandle = nullptr;
    versionInfo = nullptr;
    apiHash = nullptr;
    apiVersion = nullptr;
    utf8ToUTF16 = nullptr;
    utf16Clear = nullptr;
    userfreeFree = nullptr;
    stringListSize = nullptr;
    stringListValue = nullptr;
    initialize = nullptr;
    executeProcess = nullptr;
    shutdown = nullptr;
    doMessageLoopWork = nullptr;
    createBrowserSync = nullptr;
    createProcessMessage = nullptr;
    createV8Function = nullptr;
    currentV8Context = nullptr;
  }
};
