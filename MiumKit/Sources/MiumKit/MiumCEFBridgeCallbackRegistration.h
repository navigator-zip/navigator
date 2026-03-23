#pragma once

#ifdef __cplusplus

#include <atomic>
#include <memory>

struct MiumCEFCallbackRegistration {
  std::atomic<bool> active{true};
  void* userContext = nullptr;

  virtual ~MiumCEFCallbackRegistration() = default;
};

using MiumCEFCallbackRegistrationRef = std::shared_ptr<MiumCEFCallbackRegistration>;

#endif
