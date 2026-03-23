#!/usr/bin/env bash
set -euo pipefail

SCRIPT_OUTPUT_FILE="${SCRIPT_OUTPUT_FILE_0:-}"

REPO_DIR="${PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "${REPO_DIR}" ]; then
	echo "verify-lfs-data: unable to determine repository root"
	exit 1
fi

if [ ! -d "${REPO_DIR}/.git" ]; then
	echo "verify-lfs-data: ${REPO_DIR} is not a git checkout"
	exit 1
fi

cd "${REPO_DIR}"

# Xcode can run scripts in a PATH that doesn't include Homebrew bin directories.
# Explicitly probe common installation locations.
for candidate in /opt/homebrew/bin /usr/local/bin /usr/bin /bin; do
	if [ -x "${candidate}/git-lfs" ]; then
		export PATH="${candidate}:$PATH"
		break
	fi
done

if command -v git-lfs >/dev/null 2>&1; then
	GIT_LFS_BIN=git-lfs
elif command -v git >/dev/null 2>&1 && git lfs help >/dev/null 2>&1; then
	GIT_LFS_BIN="git lfs"
else
	echo "verify-lfs-data: git-lfs is not installed"
	echo "verify-lfs-data: install it and ensure it is discoverable at build time"
	exit 1
fi

run_git_lfs() {
	if [ "$GIT_LFS_BIN" = "git-lfs" ]; then
		git-lfs "$@"
	else
		git lfs "$@"
	fi
}

if ! run_git_lfs fsck; then
	echo "verify-lfs-data: git lfs fsck failed; some LFS objects are missing"
	exit 1
fi

bad=0
while IFS= read -r file; do
	if run_git_lfs pointer --check --file "${file}" >/dev/null 2>&1; then
		echo "verify-lfs-data: unhydrated pointer file: ${file}"
		bad=1
	fi
done < <(run_git_lfs ls-files -n)

if [ "${bad}" -ne 0 ]; then
	echo "verify-lfs-data: one or more Git LFS files are still pointers"
	exit 1
fi

echo "verify-lfs-data: all Git LFS files are present"

if [ -n "${SCRIPT_OUTPUT_FILE}" ]; then
	touch "${SCRIPT_OUTPUT_FILE}"
fi
