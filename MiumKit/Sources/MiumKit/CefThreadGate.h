#pragma once

#import <Foundation/Foundation.h>

#include <dispatch/dispatch.h>
#include <memory>
#include <type_traits>
#include <utility>

inline bool miumCefIsOnMainThread() {
  return [NSThread isMainThread];
}

template <typename Fn>
inline void miumCefDispatchSyncOnMainThread(Fn&& fn) {
  auto task = std::make_shared<std::decay_t<Fn>>(std::forward<Fn>(fn));
  if (miumCefIsOnMainThread()) {
    (*task)();
    return;
  }
  dispatch_sync(dispatch_get_main_queue(), ^{
    (*task)();
  });
}

template <typename Fn>
inline void miumCefDispatchAsyncOnMainThread(Fn&& fn) {
  auto task = std::make_shared<std::decay_t<Fn>>(std::forward<Fn>(fn));
  dispatch_async(dispatch_get_main_queue(), ^{
    (*task)();
  });
}

template <typename Fn>
inline void miumCefDispatchAfterOnMainThread(dispatch_time_t delay, Fn&& fn) {
  auto task = std::make_shared<std::decay_t<Fn>>(std::forward<Fn>(fn));
  dispatch_after(delay, dispatch_get_main_queue(), ^{
    (*task)();
  });
}
