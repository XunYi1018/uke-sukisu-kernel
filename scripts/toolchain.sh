#!/usr/bin/env bash
# Fetch the compiler toolchain and export the make flags that use it.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKSPACE=${WORKSPACE:?WORKSPACE must be set}

CLANG_DIR="${WORKSPACE}/clang"
GCC64_DIR="${WORKSPACE}/gcc-64"
GCC32_DIR="${WORKSPACE}/gcc-32"

AOSP_CLANG_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86"

# Known-good AOSP clang branch/version pairs, verified 2026-07-27.
#
# This table exists because the AOSP prebuilt repo is a minefield: every
# kernel-build branch lists *every* clang version directory in its tree, but
# only the one or two it was actually cut for contain a real toolchain. The
# rest are either absent or contain nothing but a `.keep` placeholder, and the
# generated tarball for those downloads happily with HTTP 200 -- it is just a
# valid, ~165-byte, empty archive. So a typo'd version does not 404; it
# produces an empty clang/ directory and a baffling "clang: not found" later.
#
#   branch                    version     approx clang
#   main-kernel               r596125     newest
#   main-kernel-2026          r584948c
#   main-kernel-2025          r547379     <- default
#   main-kernel-2025          r536225
#   main-kernel-build-2024    r510928
#   master-kernel-build-2022  r450784e    last of the master-* era
#
# Note the branch naming changed twice: master-kernel-build-YYYY became
# main-kernel-build-YYYY in 2023, then main-kernel-YYYY from 2025 on.
clang_known_good() {
	case "$1/$2" in
		main-kernel/r596125 | \
		main-kernel/r547379 | \
		main-kernel-2026/r584948c | \
		main-kernel-2025/r547379 | \
		main-kernel-2025/r536225 | \
		main-kernel-build-2024/r510928 | \
		main-kernel-build-2023/r498229b | \
		master-kernel-build-2022/r450784e | \
		master-kernel-build-2021/r416183b) return 0 ;;
		*) return 1 ;;
	esac
}

setup_clang() {
	rm -rf "$CLANG_DIR"; mkdir -p "$CLANG_DIR"

	if is_true "${USE_CUSTOM_CLANG:-false}"; then
		group "Downloading custom Clang"
		local src=${CUSTOM_CLANG_SOURCE:?CUSTOM_CLANG_SOURCE required}
		case "$src" in
			*.tar.gz | *.tgz | *.tar.xz | *.tar.zst | *.tar.bz2)
				fetch "$src" "${WORKSPACE}/clang-archive"
				# Name the temp file by extension so extract_archive can route it.
				local ext="${src##*/}"; ext="${ext#*.}"
				mv "${WORKSPACE}/clang-archive" "${WORKSPACE}/clang.${ext}"
				extract_archive "${WORKSPACE}/clang.${ext}" "$CLANG_DIR" ;;
			*.zip)
				fetch "$src" "${WORKSPACE}/clang.zip"
				extract_archive "${WORKSPACE}/clang.zip" "$CLANG_DIR" ;;
			*git*)
				retry 3 git clone -q --depth=1 ${CUSTOM_CLANG_BRANCH:+-b "$CUSTOM_CLANG_BRANCH"} \
					"$src" "$CLANG_DIR" || die "failed to clone ${src}" ;;
			*)
				fetch "$src" "${WORKSPACE}/clang.zip"
				extract_archive "${WORKSPACE}/clang.zip" "$CLANG_DIR" ;;
		esac
	else
		group "Downloading AOSP Clang"
		local branch=${CLANG_BRANCH:-main-kernel-2025}
		local version=${CLANG_VERSION:-r547379}

		if ! clang_known_good "$branch" "$version"; then
			warn "clang ${version} on branch ${branch} is not in the verified-good table."
			warn "AOSP lists many version directories per branch but only populates a few;"
			warn "an unpopulated one downloads as a valid but EMPTY archive."
			warn "Verified pairs: main-kernel/r596125, main-kernel-2026/r584948c,"
			warn "main-kernel-2025/r547379, main-kernel-build-2024/r510928,"
			warn "master-kernel-build-2022/r450784e"
		fi

		fetch "${AOSP_CLANG_BASE}/+archive/refs/heads/${branch}/clang-${version}.tar.gz" \
			"${WORKSPACE}/clang.tar.gz"
		extract_archive "${WORKSPACE}/clang.tar.gz" "$CLANG_DIR"
	fi

	# The check that turns the empty-archive trap into an actionable error.
	[ -x "${CLANG_DIR}/bin/clang" ] \
		|| die "no usable clang at ${CLANG_DIR}/bin/clang.
       The archive extracted to: $(ls -A "$CLANG_DIR" 2>/dev/null | head -5 | tr '\n' ' ')
       If this was an AOSP download, that branch/version pair is a placeholder
       with no toolchain in it. Pick a verified pair (see scripts/toolchain.sh)."

	local ver
	ver=$("${CLANG_DIR}/bin/clang" --version | head -n1)
	ok "clang ready: ${ver}"
	export_env CLANG_PATH "${CLANG_DIR}/bin"
	summary "| Compiler | \`${ver}\` |"
	endgroup
}

# AOSP's GCC 4.9 prebuilts are still the binutils of choice for pre-5.x trees
# that cannot yet use LLVM's integrated assembler.
setup_gcc() {
	local gcc_tag=${AOSP_GCC_TAG:-android-12.1.0_r27}

	if is_true "${USE_CUSTOM_GCC_64:-false}"; then
		group "Downloading custom GCC (arm64)"
		fetch_toolchain_generic "${CUSTOM_GCC_64_SOURCE}" "${CUSTOM_GCC_64_BRANCH:-}" "$GCC64_DIR"
		export_env GCC_64 "CROSS_COMPILE=${GCC64_DIR}/bin/${CUSTOM_GCC_64_BIN:-aarch64-linux-android-}"
		endgroup
	elif is_true "${ENABLE_GCC_ARM64:-false}"; then
		group "Downloading AOSP GCC (arm64)"
		mkdir -p "$GCC64_DIR"
		fetch "https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/${gcc_tag}.tar.gz" \
			"${WORKSPACE}/gcc-aarch64.tar.gz"
		extract_archive "${WORKSPACE}/gcc-aarch64.tar.gz" "$GCC64_DIR"
		export_env GCC_64 "CROSS_COMPILE=${GCC64_DIR}/bin/aarch64-linux-android-"
		endgroup
	fi

	if is_true "${USE_CUSTOM_GCC_32:-false}"; then
		group "Downloading custom GCC (arm32)"
		fetch_toolchain_generic "${CUSTOM_GCC_32_SOURCE}" "${CUSTOM_GCC_32_BRANCH:-}" "$GCC32_DIR"
		export_env GCC_32 "CROSS_COMPILE_ARM32=${GCC32_DIR}/bin/${CUSTOM_GCC_32_BIN:-arm-linux-androideabi-}"
		endgroup
	elif is_true "${ENABLE_GCC_ARM32:-false}"; then
		group "Downloading AOSP GCC (arm32)"
		mkdir -p "$GCC32_DIR"
		fetch "https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/${gcc_tag}.tar.gz" \
			"${WORKSPACE}/gcc-arm.tar.gz"
		extract_archive "${WORKSPACE}/gcc-arm.tar.gz" "$GCC32_DIR"
		export_env GCC_32 "CROSS_COMPILE_ARM32=${GCC32_DIR}/bin/arm-linux-androideabi-"
		endgroup
	fi
}

fetch_toolchain_generic() {
	local src=$1 branch=$2 dest=$3
	rm -rf "$dest"; mkdir -p "$dest"
	case "$src" in
		*.tar.gz | *.tgz | *.tar.xz | *.tar.zst)
			local ext="${src##*/}"; ext="${ext#*.}"
			fetch "$src" "${WORKSPACE}/tc.${ext}"
			extract_archive "${WORKSPACE}/tc.${ext}" "$dest" ;;
		*.zip)
			fetch "$src" "${WORKSPACE}/tc.zip"
			extract_archive "${WORKSPACE}/tc.zip" "$dest" ;;
		*git*)
			retry 3 git clone -q --depth=1 ${branch:+-b "$branch"} "$src" "$dest" \
				|| die "failed to clone ${src}" ;;
		*)
			fetch "$src" "${WORKSPACE}/tc.zip"
			extract_archive "${WORKSPACE}/tc.zip" "$dest" ;;
	esac
}

# mkbootimg is only needed when repacking a boot image.
setup_mkbootimg() {
	is_true "${BUILD_BOOT_IMG:-false}" || return 0
	group "Downloading mkbootimg tools"
	local dir="${WORKSPACE}/tools"
	rm -rf "$dir"
	retry 3 git clone -q --depth=1 -b main-kernel \
		https://android.googlesource.com/platform/system/tools/mkbootimg "$dir" \
		|| die "failed to clone mkbootimg"
	ok "mkbootimg ready"
	endgroup
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	setup_clang
	setup_gcc
	setup_mkbootimg
fi
