#!/usr/bin/env zsh

set -euo pipefail

LEGACY_PACKAGE_DIR="${PROJECT_DIR}/Vendor/CEF/Release/Chromium Embedded Framework.framework"
RUNTIME_PACKAGE_DIR="${PROJECT_DIR}/Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework"
APP_BUNDLE="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
APP_FRAMEWORKS="${APP_BUNDLE}/Contents/Frameworks"
APP_RESOURCES="${APP_BUNDLE}/Contents/Resources"
APP_EXECUTABLE="${PRODUCT_NAME:-Navigator}"
APP_EXECUTABLE_FROM_BUNDLE="$(/usr/bin/defaults read "${APP_BUNDLE}/Contents/Info.plist" CFBundleExecutable 2>/dev/null || true)"
if [ -n "${APP_EXECUTABLE_FROM_BUNDLE}" ]; then
  APP_EXECUTABLE="${APP_EXECUTABLE_FROM_BUNDLE}"
fi
APP_EXECUTABLE="${APP_EXECUTABLE%.app}"
CODE_SIGN_IDENTITY_VALUE="${CODE_SIGN_IDENTITY:-}"
PACKAGE_DIR=""
CEF_RELEASE_DIR="${PROJECT_DIR}/Vendor/CEF/Release"
SCRIPT_OUTPUT_FILE="${SCRIPT_OUTPUT_FILE_0:-}"

is_lfs_pointer_file() {
  local file_path="$1"
  local first_line=""
  first_line="$(head -n 1 "${file_path}" 2>/dev/null || true)"
  if [ "${first_line}" = "version https://git-lfs.github.com/spec/v1" ]; then
    return 0
  fi
  return 1
}

if [ -d "${RUNTIME_PACKAGE_DIR}" ] && [ -f "${RUNTIME_PACKAGE_DIR}/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" ]; then
  PACKAGE_DIR="${RUNTIME_PACKAGE_DIR}"
elif [ -d "${LEGACY_PACKAGE_DIR}" ] && [ -f "${LEGACY_PACKAGE_DIR}/Chromium Embedded Framework" ]; then
  PACKAGE_DIR="${LEGACY_PACKAGE_DIR}"
elif [ -d "${LEGACY_PACKAGE_DIR}" ]; then
  PACKAGE_DIR="${LEGACY_PACKAGE_DIR}"
elif [ -d "${RUNTIME_PACKAGE_DIR}" ]; then
  PACKAGE_DIR="${RUNTIME_PACKAGE_DIR}"
else
  echo "Packaged CEF runtime missing at ${PROJECT_DIR}/Vendor/CEF/Release. Checked for ChromiumEmbeddedRuntime.framework and Chromium Embedded Framework.framework. Run CEFPackager first." >&2
  exit 1
fi

if [ -d "${PACKAGE_DIR}/Contents" ]; then
  # Legacy CEFPackager output layout.
  CEF_FRAMEWORK="${PACKAGE_DIR}/Contents/Frameworks/Chromium Embedded Framework.framework"
  CEF_RUNTIME_RESOURCES="${PACKAGE_DIR}/Contents/Resources/"
  CEF_HELPERS_DIR="${PACKAGE_DIR}/Contents/Frameworks"
else
  # Direct framework layout from local Vendor CEF checkout.
  CEF_FRAMEWORK="${PACKAGE_DIR}"
  CEF_RUNTIME_RESOURCES="${PACKAGE_DIR}/Resources/"
  CEF_HELPERS_DIR="${PACKAGE_DIR}"
fi

mkdir -p "${APP_FRAMEWORKS}" "${APP_RESOURCES}"

# Keep CEF runtime attachments deterministic for packaging.
/bin/rm -rf "${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"
/bin/rm -rf "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper.app"
/bin/rm -rf "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (Renderer).app"
/bin/rm -rf "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (GPU).app"
/bin/rm -rf "${APP_FRAMEWORKS}/${APP_EXECUTABLE} Helper (Plugin).app"

CEF_DEST_FRAMEWORK="${APP_FRAMEWORKS}/Chromium Embedded Framework.framework"

/bin/rm -rf "${CEF_DEST_FRAMEWORK}"
/bin/mkdir -p "${CEF_DEST_FRAMEWORK}/Versions/A"

if [ -d "${CEF_FRAMEWORK}/Versions" ]; then
  SRC_VERSION_DIR="${CEF_FRAMEWORK}/Versions/Current"
  if [ -d "${CEF_FRAMEWORK}/Versions/A" ]; then
    SRC_VERSION_DIR="${CEF_FRAMEWORK}/Versions/A"
  fi
  /usr/bin/ditto "${SRC_VERSION_DIR}/" "${CEF_DEST_FRAMEWORK}/Versions/A/"
  if [ -f "${CEF_DEST_FRAMEWORK}/Versions/A/Chromium Embedded Framework" ] && is_lfs_pointer_file "${CEF_DEST_FRAMEWORK}/Versions/A/Chromium Embedded Framework" && [ -f "${CEF_FRAMEWORK}/Chromium Embedded Framework" ] && ! is_lfs_pointer_file "${CEF_FRAMEWORK}/Chromium Embedded Framework"; then
    /bin/cp -f "${CEF_FRAMEWORK}/Chromium Embedded Framework" "${CEF_DEST_FRAMEWORK}/Versions/A/Chromium Embedded Framework"
  fi
else
  /usr/bin/ditto "${CEF_FRAMEWORK}/" "${CEF_DEST_FRAMEWORK}/Versions/A/"
fi

/bin/mkdir -p "${CEF_DEST_FRAMEWORK}/Versions/A/Resources"

# If a shallow Info.plist was copied into Versions/A, move it to Resources.
if [ -f "${CEF_DEST_FRAMEWORK}/Versions/A/Info.plist" ] && [ ! -f "${CEF_DEST_FRAMEWORK}/Versions/A/Resources/Info.plist" ]; then
  /bin/mv -f "${CEF_DEST_FRAMEWORK}/Versions/A/Info.plist" "${CEF_DEST_FRAMEWORK}/Versions/A/Resources/Info.plist"
fi

if [ ! -f "${CEF_DEST_FRAMEWORK}/Versions/A/Resources/Info.plist" ]; then
  for info_source in \
    "${CEF_FRAMEWORK}/Resources/Info.plist" \
    "${CEF_FRAMEWORK}/Contents/Resources/Info.plist" \
    "${CEF_FRAMEWORK}/Info.plist" \
    "${CEF_FRAMEWORK}/Contents/Info.plist" \
    "${CEF_FRAMEWORK}/Versions/Current/Resources/Info.plist" \
    "${CEF_FRAMEWORK}/Versions/A/Resources/Info.plist"; do
    if [ -f "${info_source}" ]; then
      /bin/cp -f "${info_source}" "${CEF_DEST_FRAMEWORK}/Versions/A/Resources/Info.plist"
      break
    fi
  done
fi

/bin/rm -f "${CEF_DEST_FRAMEWORK}/Versions/Current"
/bin/ln -s "A" "${CEF_DEST_FRAMEWORK}/Versions/Current"

/bin/rm -f "${CEF_DEST_FRAMEWORK}/Chromium Embedded Framework"
/bin/ln -s "Versions/Current/Chromium Embedded Framework" "${CEF_DEST_FRAMEWORK}/Chromium Embedded Framework"

/bin/rm -f "${CEF_DEST_FRAMEWORK}/Resources"
/bin/ln -s "Versions/Current/Resources" "${CEF_DEST_FRAMEWORK}/Resources"

if [ -d "${CEF_DEST_FRAMEWORK}/Versions/Current/Libraries" ]; then
  /bin/rm -f "${CEF_DEST_FRAMEWORK}/Libraries"
  /bin/ln -s "Versions/Current/Libraries" "${CEF_DEST_FRAMEWORK}/Libraries"
fi

/bin/rm -f "${CEF_DEST_FRAMEWORK}/Info.plist"

sign_bundle() {
  local path="$1"
  local required="$2"
  local label="$3"
  local sign_identity="${CODE_SIGN_IDENTITY_VALUE}"
  if [ -z "${sign_identity}" ]; then
    sign_identity="-"
  fi

  /usr/bin/codesign --force --sign "${sign_identity}" --timestamp\=none "${path}" || {
    if [ "${required}" = "1" ]; then
      echo "[AttachCEFRuntime] failed to sign ${label} at ${path} with identity ${sign_identity}" >&2
      return 1
    fi
    echo "[AttachCEFRuntime] warning: failed to sign optional ${label} at ${path}; continuing" >&2
    return 0
  }
}

sign_bundle "${CEF_DEST_FRAMEWORK}" 1 "Chromium Embedded Framework"

copy_helper() {
  local helper_name="$1"
  local required="$2"
  local should_require_sign="$3"
  shift 3
  local target_helper="${APP_FRAMEWORKS}/${helper_name}"
  local candidates=("$@")
  local source_helper=""

  for candidate in "${candidates[@]}"; do
    if [ -d "${candidate}" ]; then
      source_helper="${candidate}"
      break
    fi
  done

  if [ -n "${source_helper}" ]; then
    /usr/bin/ditto "${source_helper}" "${target_helper}"
    if [ -f "${target_helper}/Contents/Info.plist" ] && [ "${should_require_sign}" = "1" ]; then
      local sign_identity="${CODE_SIGN_IDENTITY_VALUE}"
      if [ -z "${sign_identity}" ]; then
        sign_identity="-"
      fi
      /usr/bin/codesign --force --sign "${sign_identity}" --timestamp\=none "${target_helper}" || {
        if [ "${required}" = "1" ] || [ "${should_require_sign}" = "1" ]; then
          echo "[AttachCEFRuntime] failed to sign helper ${helper_name} with identity ${sign_identity}" >&2
          return 1
        fi
        echo "[AttachCEFRuntime] warning: failed to sign helper ${helper_name}; continuing" >&2
        return 0
      }
    fi
    return 0
  fi

  if [ "${required}" = "1" ]; then
    echo "[AttachCEFRuntime] missing required helper ${helper_name}" >&2
  fi

  return 1
}

for helper in \
  "${APP_EXECUTABLE} Helper.app" \
  "${APP_EXECUTABLE} Helper (Renderer).app" \
  "${APP_EXECUTABLE} Helper (GPU).app" \
  "${APP_EXECUTABLE} Helper (Plugin).app"; do
  if [ "${helper}" = "${APP_EXECUTABLE} Helper.app" ]; then
    copy_helper \
      "${helper}" \
      1 \
      1 \
      "${CEF_HELPERS_DIR}/${helper}" \
      "${CEF_RELEASE_DIR}/${helper}" \
      "${PACKAGE_DIR}/${helper}" \
      "${PACKAGE_DIR}/Contents/Helpers/${helper}" \
      "${PACKAGE_DIR}/Contents/Frameworks/${helper}" \
      "${PACKAGE_DIR}/Contents/Frameworks/Chromium Helper.app" \
      "${CEF_RELEASE_DIR}/Chromium Helper.app" \
      "${PACKAGE_DIR}/Chromium Helper.app" \
      "${PACKAGE_DIR}/Contents/Chromium Helper.app" \
      "${CEF_RELEASE_DIR}/Contents/Chromium Helper.app" \
      "${PACKAGE_DIR}/Contents/Mium Helper.app" \
      "${CEF_RELEASE_DIR}/Contents/Mium Helper.app" \
      "${PACKAGE_DIR}/Mium Helper.app" \
      "${CEF_RELEASE_DIR}/Mium Helper.app" \
      || true
  elif [ "${helper}" = "${APP_EXECUTABLE} Helper (Renderer).app" ]; then
    copy_helper \
      "${helper}" \
      1 \
      1 \
      "${CEF_HELPERS_DIR}/${helper}" \
      "${CEF_RELEASE_DIR}/${helper}" \
      "${PACKAGE_DIR}/${helper}" \
      "${PACKAGE_DIR}/Contents/Helpers/${helper}" \
      "${PACKAGE_DIR}/Contents/Frameworks/${helper}" \
      "${PACKAGE_DIR}/Contents/Chromium Helper (Renderer).app" \
      "${CEF_RELEASE_DIR}/Chromium Helper (Renderer).app" \
      "${CEF_RELEASE_DIR}/Contents/Chromium Helper (Renderer).app" \
      "${CEF_HELPERS_DIR}/Chromium Helper (Renderer).app" \
      "${CEF_HELPERS_DIR}/Contents/Chromium Helper (Renderer).app" \
      "${PACKAGE_DIR}/Mium Helper (Renderer).app" \
      "${CEF_RELEASE_DIR}/Mium Helper (Renderer).app" \
      "${PACKAGE_DIR}/Contents/Mium Helper (Renderer).app" \
      "${CEF_RELEASE_DIR}/Contents/Mium Helper (Renderer).app" \
      || true
  elif [ "${helper}" = "${APP_EXECUTABLE} Helper (GPU).app" ]; then
    copy_helper \
      "${helper}" \
      1 \
      1 \
      "${CEF_HELPERS_DIR}/${helper}" \
      "${CEF_RELEASE_DIR}/${helper}" \
      "${PACKAGE_DIR}/${helper}" \
      "${PACKAGE_DIR}/Contents/Helpers/${helper}" \
      "${PACKAGE_DIR}/Contents/Frameworks/${helper}" \
      "${PACKAGE_DIR}/Contents/Chromium Helper (GPU).app" \
      "${CEF_RELEASE_DIR}/Chromium Helper (GPU).app" \
      "${CEF_RELEASE_DIR}/Contents/Chromium Helper (GPU).app" \
      "${CEF_HELPERS_DIR}/Chromium Helper (GPU).app" \
      "${CEF_HELPERS_DIR}/Contents/Chromium Helper (GPU).app" \
      "${PACKAGE_DIR}/Mium Helper (GPU).app" \
      "${CEF_RELEASE_DIR}/Mium Helper (GPU).app" \
      "${PACKAGE_DIR}/Contents/Mium Helper (GPU).app" \
      "${CEF_RELEASE_DIR}/Contents/Mium Helper (GPU).app" \
      || true
  else
    copy_helper \
      "${helper}" \
      0 \
      1 \
      "${CEF_HELPERS_DIR}/${helper}" \
      "${CEF_RELEASE_DIR}/${helper}" \
      "${PACKAGE_DIR}/${helper}" \
      "${PACKAGE_DIR}/Contents/Helpers/${helper}" \
      "${PACKAGE_DIR}/Contents/Frameworks/${helper}" \
      "${PACKAGE_DIR}/Contents/Chromium Helper (Plugin).app" \
      "${CEF_RELEASE_DIR}/Chromium Helper (Plugin).app" \
      "${CEF_RELEASE_DIR}/Contents/Chromium Helper (Plugin).app" \
      "${CEF_HELPERS_DIR}/Chromium Helper (Plugin).app" \
      "${CEF_HELPERS_DIR}/Contents/Chromium Helper (Plugin).app" \
      "${PACKAGE_DIR}/Mium Helper (Plugin).app" \
      "${CEF_RELEASE_DIR}/Mium Helper (Plugin).app" \
      "${PACKAGE_DIR}/Contents/Mium Helper (Plugin).app" \
      "${CEF_RELEASE_DIR}/Contents/Mium Helper (Plugin).app" \
      || true
  fi
done

REQUIRED_HELPERS=(
  "${APP_EXECUTABLE} Helper.app"
  "${APP_EXECUTABLE} Helper (Renderer).app"
  "${APP_EXECUTABLE} Helper (GPU).app"
  "${APP_EXECUTABLE} Helper (Plugin).app"
)
MISSING_HELPERS=0
for required_helper in "${REQUIRED_HELPERS[@]}"; do
  if [ -d "${APP_FRAMEWORKS}/${required_helper}" ]; then
    continue
  fi

  if [ -d "${CEF_RELEASE_DIR}/${required_helper}" ]; then
    /usr/bin/ditto "${CEF_RELEASE_DIR}/${required_helper}" "${APP_FRAMEWORKS}/${required_helper}"
    if [ -f "${APP_FRAMEWORKS}/${required_helper}/Contents/Info.plist" ]; then
      sign_identity="${CODE_SIGN_IDENTITY_VALUE}"
      if [ -z "${sign_identity}" ]; then
        sign_identity="-"
      fi
      /usr/bin/codesign --force --sign "${sign_identity}" --timestamp\=none "${APP_FRAMEWORKS}/${required_helper}" || {
        echo "[AttachCEFRuntime] warning: failed to sign fallback required helper ${required_helper}; continuing" >&2
      }
    fi
    continue
  fi

  echo "[AttachCEFRuntime] missing required helper ${required_helper} from build and fallback sources" >&2
  MISSING_HELPERS=1
done

if [ "${MISSING_HELPERS}" -eq 1 ]; then
  echo "[AttachCEFRuntime] one or more required helpers are missing. Aborting to avoid runtime launch failure." >&2
  exit 1
fi

/usr/bin/ditto "${CEF_RUNTIME_RESOURCES}" "${APP_RESOURCES}/"

RUNTIME_LAYOUT_SOURCE=""
for candidate in \
  "${PACKAGE_DIR}/Contents/Resources/runtime_layout.json" \
  "${CEF_RUNTIME_RESOURCES%/}/runtime_layout.json"; do
  if [ -f "${candidate}" ]; then
    RUNTIME_LAYOUT_SOURCE="${candidate}"
    break
  fi
done

if [ -n "${RUNTIME_LAYOUT_SOURCE}" ]; then
  /bin/cp -f "${RUNTIME_LAYOUT_SOURCE}" "${APP_RESOURCES}/runtime_layout.json"
else
  cat > "${APP_RESOURCES}/runtime_layout.json" <<'JSON'
{
  "expectedPaths": {
    "resourcesRelativePath": "Contents/Resources",
    "localesRelativePath": "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/locales",
    "helpersDirRelativePath": "Contents/Frameworks"
  }
}
JSON
fi

/bin/rm -f "${APP_RESOURCES}/Chromium Embedded Framework"
/bin/rm -f "${APP_RESOURCES}/Info.plist"

if [ -n "${SCRIPT_OUTPUT_FILE}" ]; then
  /usr/bin/touch "${SCRIPT_OUTPUT_FILE}"
fi

echo "Attached packaged CEF runtime from ${PACKAGE_DIR}"
