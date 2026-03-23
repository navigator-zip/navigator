#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: $0 /path/to/Navigator.app}"
APP_NAME="${2:-${APP_PATH##*/}}"
APP_NAME="${APP_NAME%.app}"
APP_EXECUTABLE="$(/usr/bin/defaults read "${APP_PATH}/Contents/Info.plist" CFBundleExecutable 2>/dev/null || echo "${APP_NAME}")"
APP_EXECUTABLE="${APP_EXECUTABLE#${APP_PATH%/*}/}"
APP_FRAMEWORKS="${APP_PATH}/Contents/Frameworks"
APP_RESOURCES="${APP_PATH}/Contents/Resources"
ALLOW_MISSING_HELPERS="${CEF_ALLOW_MISSING_HELPERS:-0}"

function require_exists {
  local path="$1"
  local label="$2"
  if [ ! -e "${path}" ]; then
    echo "[MiumCEF] missing ${label}: ${path}"
    exit 1
  fi
  echo "[MiumCEF] ok ${label}: ${path}"
}

function print_helper_set {
  local role="$1"
  shift
  local found_path=""
  for candidate in "$@"; do
    if [ -d "${candidate}/Contents/MacOS" ]; then
      for binary in "${candidate}/Contents/MacOS"/*; do
        if [ -f "${binary}" ]; then
          found_path="${candidate}"
          break 2
        fi
      done
    fi
  done
  if [ -z "${found_path}" ]; then
    echo "[MiumCEF] helper(${role}): missing"
  else
    echo "[MiumCEF] helper(${role}): ${found_path}"
  fi
}

echo "[MiumCEF] app        : ${APP_PATH}"
echo "[MiumCEF] executable : ${APP_EXECUTABLE}"

require_exists "${APP_PATH}/Contents/Frameworks/Chromium Embedded Framework.framework" "Chromium Embedded Framework"
require_exists "${APP_RESOURCES}" "Contents/Resources"
require_exists "${APP_RESOURCES}/runtime_layout.json" "runtime_layout.json"

if [ -f "${APP_RESOURCES}/runtime_layout.json" ]; then
  echo "[MiumCEF] runtime layout:"
  cat "${APP_RESOURCES}/runtime_layout.json"
  echo
fi

echo "[MiumCEF] helper layout (Contents/Frameworks):"
print_helper_set "base" \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper.app" \
  "${APP_FRAMEWORKS}/Chromium Helper.app" \
  "${APP_FRAMEWORKS}/Mium Helper.app"
print_helper_set "renderer" \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (Renderer).app" \
  "${APP_FRAMEWORKS}/Chromium Helper (Renderer).app" \
  "${APP_FRAMEWORKS}/Mium Helper (Renderer).app"
print_helper_set "gpu" \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (GPU).app" \
  "${APP_FRAMEWORKS}/Chromium Helper (GPU).app" \
  "${APP_FRAMEWORKS}/Mium Helper (GPU).app"
print_helper_set "plugin" \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (Plugin).app" \
  "${APP_FRAMEWORKS}/Chromium Helper (Plugin).app" \
  "${APP_FRAMEWORKS}/Mium Helper (Plugin).app"

if [ ! -d "${APP_FRAMEWORKS}" ]; then
  echo "[MiumCEF] no Frameworks directory found"
  exit 1
fi

base_helper_found=0
for candidate in \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper.app" \
  "${APP_FRAMEWORKS}/Chromium Helper.app" \
  "${APP_FRAMEWORKS}/Mium Helper.app"; do
  if [ -d "${candidate}/Contents/MacOS" ]; then
    for binary in "${candidate}/Contents/MacOS"/*; do
      if [ -f "${binary}" ]; then
        base_helper_found=1
        break 2
      fi
    done
  fi
done

renderer_helper_found=0
for candidate in \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (Renderer).app" \
  "${APP_FRAMEWORKS}/Chromium Helper (Renderer).app" \
  "${APP_FRAMEWORKS}/Mium Helper (Renderer).app"; do
  if [ -d "${candidate}/Contents/MacOS" ]; then
    for binary in "${candidate}/Contents/MacOS"/*; do
      if [ -f "${binary}" ]; then
        renderer_helper_found=1
        break 2
      fi
    done
  fi
done

gpu_helper_found=0
for candidate in \
  "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (GPU).app" \
  "${APP_FRAMEWORKS}/Chromium Helper (GPU).app" \
  "${APP_FRAMEWORKS}/Mium Helper (GPU).app"; do
  if [ -d "${candidate}/Contents/MacOS" ]; then
    for binary in "${candidate}/Contents/MacOS"/*; do
      if [ -f "${binary}" ]; then
        gpu_helper_found=1
        break 2
      fi
    done
  fi
done

if [ "${base_helper_found}" -ne 1 ] || [ "${renderer_helper_found}" -ne 1 ] || [ "${gpu_helper_found}" -ne 1 ]; then
  if [ "${ALLOW_MISSING_HELPERS}" = "1" ]; then
    echo "[MiumCEF] helper check warning: base/renderer/gpu missing, continuing because CEF_ALLOW_MISSING_HELPERS=1"
  else
    echo "[MiumCEF] required helpers missing (base/renderer/gpu must exist)"
    exit 1
  fi
fi

echo "[MiumCEF] architecture (framework)"
lipo -info "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework/Chromium Embedded Framework"

function verify_code_signature {
  local target="$1"
  /usr/bin/codesign --verify --strict --verbose=3 "${target}"
}

function verify_code_signature_deep {
  local target="$1"
  /usr/bin/codesign --verify --deep --strict --verbose=4 "${target}"
}

function require_entitlements {
  local target="$1"
  local label="$2"
  local entitlements
  entitlements="$(/usr/bin/codesign -d --entitlements - "${target}" 2>&1)"
  local required_keys=(
    "com.apple.security.cs.allow-jit"
    "com.apple.security.cs.allow-unsigned-executable-memory"
    "com.apple.security.cs.disable-library-validation"
  )
  for required_key in "${required_keys[@]}"; do
    if [[ "${entitlements}" != *"${required_key}"* ]]; then
      echo "[MiumCEF] missing entitlement ${required_key} on ${label}: ${target}"
      echo "${entitlements}"
      exit 1
    fi
  done
  echo "[MiumCEF] ok entitlements (${label}): ${target}"
}

echo "[MiumCEF] code signature check"
verify_code_signature "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
for helper in "${APP_FRAMEWORKS}"/*Helper*.app; do
  [ -d "${helper}" ] && verify_code_signature "${helper}"
done
require_entitlements "${APP_PATH}" "app"
for helper in "${APP_FRAMEWORKS}"/*Helper*.app; do
  [ -d "${helper}" ] && require_entitlements "${helper}" "helper"
  [ -d "${helper}" ] && echo "[MiumCEF] helper signed: ${helper}" || true
done

if [ "${VERIFY_DEEP_CODESIGN:-0}" = "1" ]; then
  verify_code_signature_deep "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
  for helper in "${APP_FRAMEWORKS}"/*Helper*.app; do
    [ -d "${helper}" ] && verify_code_signature_deep "${helper}"
  done
fi

echo "[MiumCEF] key framework settings"
if [ -d "${APP_RESOURCES}/locales" ]; then
  locale_count="$(find "${APP_RESOURCES}/locales" -type f | wc -l | awk '{print $1}')"
  echo "[MiumCEF] locale pak files in Contents/Resources/locales: ${locale_count}"
fi
if [ -d "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework/Versions/A/Resources/locales" ]; then
  locale_count="$(find "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework/Versions/A/Resources/locales" -type f | wc -l | awk '{print $1}')"
  echo "[MiumCEF] locale pak files in framework resources: ${locale_count}"
fi
