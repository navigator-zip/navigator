#pragma once

#include <cassert>
#include <cstddef>
#include <utility>

#include "CefBaseTraits.h"

inline cef_base_ref_counted_t* retainCefBase(cef_base_ref_counted_t* borrowed) {
  if (borrowed != nullptr && borrowed->add_ref != nullptr) {
    borrowed->add_ref(borrowed);
  }
  return borrowed;
}

inline void releaseCefBase(cef_base_ref_counted_t* owned) {
  if (owned != nullptr && owned->release != nullptr) {
    owned->release(owned);
  }
}

template <typename T>
class CefRef {
 public:
  CefRef() = default;

  CefRef(CefRef&& other) noexcept : value_(other.leak()) {}

  CefRef& operator=(CefRef&& other) noexcept {
    if (this == &other) {
      return *this;
    }
    reset();
    value_ = other.leak();
    return *this;
  }

  CefRef(const CefRef&) = delete;
  CefRef& operator=(const CefRef&) = delete;

  ~CefRef() {
    reset();
  }

  static CefRef retain(T* borrowed) {
    CefRef ref;
    ref.value_ = borrowed;
    if (borrowed != nullptr) {
      if (!hasValidCefBaseAccess(borrowed)) {
        debugAssertValidCefBaseAccess(borrowed);
        ref.value_ = nullptr;
        return ref;
      }
      cef_base_ref_counted_t* base = cefBaseForValue(borrowed);
      base->add_ref(base);
    }
    return ref;
  }

  static CefRef adopt(T* owned) {
    CefRef ref;
    if (!hasValidCefBaseAccess(owned)) {
      debugAssertValidCefBaseAccess(owned);
      return ref;
    }
    ref.value_ = owned;
    return ref;
  }

  void reset() {
    if (value_ == nullptr) {
      return;
    }
    T* owned = value_;
    value_ = nullptr;
    if (!hasValidCefBaseAccess(owned)) {
      debugAssertValidCefBaseAccess(owned);
      return;
    }
    cef_base_ref_counted_t* base = cefBaseForValue(owned);
    base->release(base);
  }

  T* get() const {
    return value_;
  }

  T* operator->() const {
    assert(value_ != nullptr && "Attempted to dereference a null CefRef");
    return value_;
  }

  explicit operator bool() const {
    return value_ != nullptr;
  }

  bool operator==(std::nullptr_t) const {
    return value_ == nullptr;
  }

  bool operator!=(std::nullptr_t) const {
    return value_ != nullptr;
  }

  CefRef& operator=(std::nullptr_t) {
    reset();
    return *this;
  }

  T* leak() {
    T* leaked = value_;
    value_ = nullptr;
    return leaked;
  }

 private:
  T* value_ = nullptr;
};

template <typename T>
inline T* retainCefBorrowed(T* borrowed) {
  return CefRef<T>::retain(borrowed).leak();
}

template <typename T>
inline void releaseOwnedCefValue(T* owned) {
  CefRef<T>::adopt(owned).reset();
}

inline void releaseOwnedCefValue(cef_base_ref_counted_t* owned) {
  releaseCefBase(owned);
}
