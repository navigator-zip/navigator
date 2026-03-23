#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

MODE="${CEF_RUNTIME_MODE:-app}"
APP_EXECUTABLE_NAME="${CEF_RUNTIME_APP_EXECUTABLE_NAME:-${PRODUCT_NAME:-${TARGET_NAME:-Navigator}}}"
APP_EXECUTABLE="${APP_EXECUTABLE_NAME%.app}"
ALLOW_MISSING_HELPERS="${CEF_ALLOW_MISSING_HELPERS:-0}"

CEF_STAGING_DIR="${CEF_STAGING_DIR:-${PROJECT_DIR}/Vendor/CEF/Release}"
CEF_HELPERS_STAGING_DIR="${CEF_HELPERS_STAGING_DIR:-${CEF_STAGING_DIR}}"
CEF_RESOURCES_STAGING_DIR="${CEF_RESOURCES_STAGING_DIR:-${CEF_STAGING_DIR}/CEFResourcesStaging}"
CEF_RUNTIME_PACKAGE_DIR="${CEF_RUNTIME_PACKAGE_DIR:-${PROJECT_DIR}/Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework}"
FRAMEWORK_SRC="${CEF_STAGING_DIR}/Chromium Embedded Framework.framework"
RESOURCES_SRC="${CEF_RESOURCES_STAGING_DIR}"
FRAMEWORK_DST=""
APP_FRAMEWORKS=""
APP_RESOURCES=""
APP_HELPERS=""
REPO_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

if [ ! -d "${RESOURCES_SRC}" ]; then
  if [ "${ALLOW_MISSING_HELPERS}" = "1" ]; then
    RESOURCES_SRC="${CEF_STAGING_DIR}/Resources"
  else
    echo "${SCRIPT_NAME}: missing CEF_RESOURCES_STAGING_DIR at ${CEF_RESOURCES_STAGING_DIR}" >&2
    exit 1
  fi
fi

case "${MODE}" in
  app)
    : "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required for CEF_RUNTIME_MODE=app}"
    : "${FULL_PRODUCT_NAME:?FULL_PRODUCT_NAME is required for CEF_RUNTIME_MODE=app}"
    APP_BUNDLE="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
    APP_FRAMEWORKS="${APP_BUNDLE}/Contents/Frameworks"
    APP_RESOURCES="${APP_BUNDLE}/Contents/Resources"
    APP_HELPERS="${APP_FRAMEWORKS}"
    FRAMEWORK_DST="${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
    ;;
  package)
    APP_FRAMEWORKS="${CEF_RUNTIME_PACKAGE_DIR}/Contents/Frameworks"
    APP_RESOURCES="${CEF_RUNTIME_PACKAGE_DIR}/Contents/Resources"
    APP_HELPERS="${APP_FRAMEWORKS}"
    FRAMEWORK_DST="${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
    rm -rf "${CEF_RUNTIME_PACKAGE_DIR}"
    ;;
  *)
    echo "${SCRIPT_NAME}: unknown CEF_RUNTIME_MODE=${MODE}" >&2
    exit 1
    ;;
esac

mkdir -p "${APP_FRAMEWORKS}" "${APP_RESOURCES}" "${APP_HELPERS}"

if [ "${MODE}" != "package" ]; then
  rm -rf "${FRAMEWORK_DST}"
fi

function fail_with_help {
  echo "${SCRIPT_NAME}: $1" >&2
  echo "Expected at least \"${APP_EXECUTABLE} Helper.app\", \"${APP_EXECUTABLE} Helper (Renderer).app\", \"${APP_EXECUTABLE} Helper (GPU).app\" under ${APP_HELPERS}" >&2
  echo "and Chromium Embedded Framework.framework under ${APP_FRAMEWORKS}" >&2
  exit 1
}

function helper_bundle_has_executable {
  local helper_bundle="$1"
  if [ ! -d "${helper_bundle}" ]; then
    return 1
  fi

  local helper_binary_dir="${helper_bundle}/Contents/MacOS"
  if [ ! -d "${helper_binary_dir}" ]; then
    return 1
  fi

  for helper_binary in "${helper_binary_dir}"/*; do
    if [ -f "${helper_binary}" ]; then
      return 0
    fi
  done
  return 1
}

function ensure_framework {
  if [ ! -d "${FRAMEWORK_SRC}" ]; then
    echo "${SCRIPT_NAME}: missing CEF framework source: ${FRAMEWORK_SRC}" >&2
    exit 1
  fi
  /usr/bin/ditto "${FRAMEWORK_SRC}/" "${FRAMEWORK_DST}/"
}

function resolve_framework_resource_dir {
  if [ -d "${FRAMEWORK_DST}/Versions/A/Resources" ]; then
    echo "${FRAMEWORK_DST}/Versions/A/Resources"
    return 0
  fi
  if [ -d "${FRAMEWORK_DST}/Versions/Current/Resources" ]; then
    echo "${FRAMEWORK_DST}/Versions/Current/Resources"
    return 0
  fi
  if [ -d "${FRAMEWORK_DST}/Resources" ]; then
    echo "${FRAMEWORK_DST}/Resources"
    return 0
  fi
  return 1
}

function copy_framework_resources {
  if [ ! -d "${RESOURCES_SRC}" ]; then
    if [ "${ALLOW_MISSING_HELPERS}" = "1" ]; then
      echo "warning: CEF resource staging directory missing: ${RESOURCES_SRC}" >&2
      return
    fi
    echo "${SCRIPT_NAME}: missing CEF resources staging directory: ${RESOURCES_SRC}" >&2
    exit 1
  fi
  /usr/bin/ditto "${RESOURCES_SRC}/" "${APP_RESOURCES}/"
}

function copy_runtime_metadata {
  local framework_resource_dir="$1"
  local framework_resource_name="Contents/Frameworks/Chromium Embedded Framework.framework"
  local locales_path="${framework_resource_name}/Versions/A/Resources/locales"
  if [ "${framework_resource_dir}" = "${APP_FRAMEWORKS}/${framework_resource_name}/Resources" ]; then
    locales_path="${framework_resource_name}/Resources/locales"
  elif [ "${framework_resource_dir}" = "${APP_FRAMEWORKS}/${framework_resource_name}/Versions/Current/Resources" ]; then
    locales_path="${framework_resource_name}/Versions/Current/Resources/locales"
  fi

  local layout_json_path="${APP_RESOURCES}/runtime_layout.json"
  cat > "${layout_json_path}" <<JSON
{
  "expectedPaths": {
    "resourcesRelativePath": "Contents/Resources",
    "localesRelativePath": "${locales_path}",
    "helpersDirRelativePath": "Contents/Frameworks"
  }
}
JSON
}

function copy_helpers_from_staging {
  local required_ok=1

  for helper_name in \
    "${APP_EXECUTABLE} Helper.app" \
    "${APP_EXECUTABLE} Helper (Renderer).app" \
    "${APP_EXECUTABLE} Helper (GPU).app"; do
    local source_bundle="${CEF_HELPERS_STAGING_DIR}/${helper_name}"
    local target_bundle="${APP_HELPERS}/${helper_name}"
    if [ -d "${source_bundle}" ]; then
      rm -rf "${target_bundle}"
      /usr/bin/ditto "${source_bundle}" "${target_bundle}"
      continue
    fi

    echo "${SCRIPT_NAME}: missing required helper bundle ${source_bundle}" >&2
    required_ok=0
  done

  local plugin_source="${CEF_HELPERS_STAGING_DIR}/${APP_EXECUTABLE} Helper (Plugin).app"
  local plugin_target="${APP_HELPERS}/${APP_EXECUTABLE} Helper (Plugin).app"
  if [ -d "${plugin_source}" ]; then
    rm -rf "${plugin_target}"
    /usr/bin/ditto "${plugin_source}" "${plugin_target}"
  else
    echo "warning: optional plugin helper not found in ${CEF_HELPERS_STAGING_DIR}; this is optional for many builds."
  fi

  if [ "${required_ok}" -ne 1 ] && [ "${ALLOW_MISSING_HELPERS}" != "1" ]; then
    fail_with_help
  fi
}

function ensure_expected_helpers {
  for helper_name in \
    "${APP_EXECUTABLE} Helper.app" \
    "${APP_EXECUTABLE} Helper (Renderer).app" \
    "${APP_EXECUTABLE} Helper (GPU).app"; do
    if ! helper_bundle_has_executable "${APP_HELPERS}/${helper_name}"; then
      if [ "${ALLOW_MISSING_HELPERS}" = "1" ]; then
        echo "${SCRIPT_NAME}: missing ${helper_name}; continuing because CEF_ALLOW_MISSING_HELPERS=1" >&2
      else
        fail_with_help
      fi
    fi
  done
}

function verify_runtime_payload {
  local framework_resources
  framework_resources="$(resolve_framework_resource_dir)"
  if [ -z "${framework_resources}" ]; then
    echo "${SCRIPT_NAME}: missing framework Resources under ${FRAMEWORK_DST}" >&2
    exit 1
  fi
  if [ ! -f "${framework_resources}/icudtl.dat" ]; then
    echo "${SCRIPT_NAME}: missing framework resource icudtl.dat" >&2
    exit 1
  fi

  local pak_count
  pak_count="$(find "${framework_resources}" -maxdepth 1 -type f -name "*.pak" | wc -l | awk '{print $1}')"
  if [ "${pak_count}" -eq 0 ]; then
    pak_count="$(find "${framework_resources}" -type f -name "*.pak" | wc -l | awk '{print $1}')"
  fi
  if [ "${pak_count}" -eq 0 ]; then
    echo "${SCRIPT_NAME}: missing framework .pak resources under ${framework_resources}" >&2
    exit 1
  fi

  if [ -d "${framework_resources}/locales" ]; then
    locale_count="$(find "${framework_resources}/locales" -type f | wc -l | awk '{print $1}')"
    echo "[MiumCEF] locale pak files in framework locales: ${locale_count}"
  else
    echo "${SCRIPT_NAME}: framework locales directory not present; using fallback locale resolution: ${framework_resources}" >&2
  fi
}

function helper_entitlements_for_name {
  local helper_name="$1"
  case "${helper_name}" in
    *"(Renderer).app")
      echo "${REPO_DIR}/scripts/entitlements/helper_renderer.plist"
      ;;
    *"(GPU).app")
      echo "${REPO_DIR}/scripts/entitlements/helper_gpu.plist"
      ;;
    *"(Plugin).app")
      echo "${REPO_DIR}/scripts/entitlements/helper_plugin.plist"
      ;;
    *)
      echo "${REPO_DIR}/scripts/entitlements/helper.plist"
      ;;
  esac
}

function sign_if_requested {
  local sign_identity="${CODE_SIGN_IDENTITY:-}"
  if [ -z "${sign_identity}" ] || [ "${sign_identity}" = "-" ]; then
    return 0
  fi

  local framework_binary="${FRAMEWORK_DST}/Versions/A/Chromium Embedded Framework"
  if [ ! -f "${framework_binary}" ]; then
    framework_binary="${FRAMEWORK_DST}/Versions/Current/Chromium Embedded Framework"
  fi

  if [ -f "${framework_binary}" ]; then
    /usr/bin/codesign --force --sign "${sign_identity}" --options runtime "${framework_binary}"
  fi

  /usr/bin/codesign --force --sign "${sign_identity}" --options runtime "${FRAMEWORK_DST}"

  while IFS= read -r -d '' helper; do
    local helper_name
    local helper_executable
    helper_name="$(/usr/bin/basename "${helper}")"
    helper_executable=""
    for candidate in "${helper}/Contents/MacOS/"*; do
      if [ -f "${candidate}" ]; then
        helper_executable="${candidate}"
        break
      fi
    done

    local helper_entitlements
    helper_entitlements="$(helper_entitlements_for_name "${helper_name}")"
    if [ -n "${helper_executable}" ] && [ -f "${helper_executable}" ]; then
      if [ -f "${helper_entitlements}" ]; then
        /usr/bin/codesign --force --sign "${sign_identity}" --options runtime --entitlements "${helper_entitlements}" "${helper_executable}"
      else
        /usr/bin/codesign --force --sign "${sign_identity}" --options runtime "${helper_executable}"
      fi
    fi

    if [ -f "${helper_entitlements}" ]; then
      /usr/bin/codesign --force --sign "${sign_identity}" --options runtime --entitlements "${helper_entitlements}" "${helper}"
    else
      /usr/bin/codesign --force --sign "${sign_identity}" --options runtime "${helper}"
    fi
  done < <(/usr/bin/find "${APP_HELPERS}" -maxdepth 1 -type d -name "*Helper*.app" -print0)

  /usr/bin/codesign --verify --strict --verbose=2 "${FRAMEWORK_DST}"
  for helper in "${APP_HELPERS}"/*Helper*.app; do
    [ -d "${helper}" ] || continue
    /usr/bin/codesign --verify --strict --verbose=2 "${helper}"
  done
  if [ "${VERIFY_DEEP_CODESIGN:-0}" = "1" ]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${FRAMEWORK_DST}"
    for helper in "${APP_HELPERS}"/*Helper*.app; do
      [ -d "${helper}" ] || continue
      /usr/bin/codesign --verify --deep --strict --verbose=2 "${helper}"
    done
  fi
}

ensure_framework
copy_framework_resources
verify_runtime_payload
copy_helpers_from_staging
copy_runtime_metadata "$(resolve_framework_resource_dir)"
ensure_expected_helpers
sign_if_requested
if [ "${MODE}" = "package" ]; then
  echo "${SCRIPT_NAME}: CEF runtime package complete at ${CEF_RUNTIME_PACKAGE_DIR}"
else
  echo "${SCRIPT_NAME}: CEF runtime copy complete"
fi
