#!/bin/sh
# pxd installer for Linux and macOS.
#
#   curl -fsSL https://pxd.cotc.dev/install.sh | sh
#   curl -fsSL https://pxd.cotc.dev/install.sh | PXD_VERSION=v1.2.3 sh
#
# Environment:
#   PXD_VERSION        install a specific tag (vX.Y.Z or X.Y.Z) instead of latest
#   PXD_INSTALL_DIR    install directory (default: $HOME/.local/bin)
#   PXD_DOWNLOAD_BASE  release base URL
#                      (default: https://github.com/novaladip/pxd/releases)
#   PXD_QUIET=1        suppress non-error output
#
# The archive is always verified against checksums.txt from the same release.
# Without a SHA-256 tool the installer refuses to run: never install unverified
# bytes.
#
# Windows: use install.ps1:
#   irm https://pxd.cotc.dev/install.ps1 | iex
set -eu

say() {
	if [ "${PXD_QUIET:-0}" != "1" ]; then
		printf '%s\n' "$*"
	fi
}

warn() {
	printf 'pxd-install: %s\n' "$*" >&2
}

die() {
	warn "error: $*"
	exit 1
}

TMP_DIR=""
STAGED=""

cleanup() {
	if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
		rm -rf "$TMP_DIR"
	fi
	if [ -n "$STAGED" ] && [ -f "$STAGED" ]; then
		rm -f "$STAGED"
	fi
}

trap 'cleanup' EXIT
trap 'exit 1' HUP INT TERM

detect_platform() {
	case "$(uname -s)" in
	Linux) OS=linux ;;
	Darwin) OS=darwin ;;
	MINGW* | MSYS* | CYGWIN* | Windows_NT)
		die "Windows is not supported by install.sh; run: irm https://pxd.cotc.dev/install.ps1 | iex"
		;;
	*)
		die "unsupported operating system: $(uname -s) (pxd supports Linux and macOS; see https://github.com/novaladip/pxd)"
		;;
	esac

	case "$(uname -m)" in
	x86_64 | amd64) ARCH=amd64 ;;
	aarch64 | arm64) ARCH=arm64 ;;
	*)
		die "unsupported architecture: $(uname -m) (pxd ships amd64 and arm64 builds)"
		;;
	esac

	# A Rosetta-translated shell reports x86_64 on Apple silicon. Prefer the
	# native arm64 build, which runs faster and is the one users expect.
	if [ "$OS" = darwin ] && [ "$ARCH" = amd64 ]; then
		if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || true)" = "1" ]; then
			ARCH=arm64
		fi
	fi
}

resolve_release() {
	if [ -n "${PXD_VERSION:-}" ]; then
		TAG=$PXD_VERSION
		case "$TAG" in
		v*) ;;
		*) TAG="v${TAG}" ;;
		esac
		case "$TAG" in
		v[0-9]*.[0-9]*.[0-9]*) ;;
		*) die "PXD_VERSION must look like vX.Y.Z (got '$PXD_VERSION')" ;;
		esac
		VERSION=${TAG#v}
		ASSET="pxd_${VERSION}_${OS}_${ARCH}.tar.gz"
		RELEASE_URL="${DOWNLOAD_BASE}/download/${TAG}"
	else
		# Version-less asset names keep releases/latest/download/... stable.
		ASSET="pxd_${OS}_${ARCH}.tar.gz"
		RELEASE_URL="${DOWNLOAD_BASE}/latest/download"
	fi
	ARCHIVE_URL="${RELEASE_URL}/${ASSET}"
	CHECKSUMS_URL="${RELEASE_URL}/checksums.txt"
}

fetch() {
	# fetch <url> <destination>
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 10 --retry 2 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		die "curl or wget is required to download pxd"
	fi
}

download_files() {
	TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pxd-install.XXXXXX") ||
		die "could not create a temporary directory"
	say "Downloading ${ARCHIVE_URL}"
	if ! fetch "$ARCHIVE_URL" "${TMP_DIR}/${ASSET}"; then
		die "failed to download ${ARCHIVE_URL}"
	fi
	if ! fetch "$CHECKSUMS_URL" "${TMP_DIR}/checksums.txt"; then
		die "failed to download ${CHECKSUMS_URL}"
	fi
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		return 1
	fi
}

verify_checksum() {
	EXPECTED=$(awk -v want="$ASSET" '$2 == want { print $1; exit }' "${TMP_DIR}/checksums.txt")
	if [ -z "$EXPECTED" ]; then
		die "checksums.txt does not list ${ASSET}; refusing to install unverified bytes"
	fi
	ACTUAL=$(sha256_of "${TMP_DIR}/${ASSET}") ||
		die "no SHA-256 tool found (need sha256sum or shasum); refusing to install unverified bytes"
	if [ "$ACTUAL" != "$EXPECTED" ]; then
		die "checksum mismatch for ${ASSET}: expected ${EXPECTED}, got ${ACTUAL}"
	fi
	say "Verified SHA-256 ${ACTUAL}"
}

install_binary() {
	mkdir -p "${TMP_DIR}/extract" || die "could not create ${TMP_DIR}/extract"
	if ! tar -xzf "${TMP_DIR}/${ASSET}" -C "${TMP_DIR}/extract" pxd 2>/dev/null; then
		die "failed to extract pxd from ${ASSET}"
	fi
	if [ ! -f "${TMP_DIR}/extract/pxd" ]; then
		die "${ASSET} does not contain pxd"
	fi

	if [ ! -d "$INSTALL_DIR" ]; then
		mkdir -p "$INSTALL_DIR" || die "could not create ${INSTALL_DIR}"
	fi
	if [ ! -w "$INSTALL_DIR" ]; then
		die "${INSTALL_DIR} is not writable; set PXD_INSTALL_DIR to a writable directory, e.g. PXD_INSTALL_DIR=\"\$HOME/.local/bin\""
	fi

	# Stage in the target directory and rename, so an existing pxd is either
	# fully replaced or left untouched.
	STAGED="${INSTALL_DIR}/.pxd.tmp.$$"
	cp "${TMP_DIR}/extract/pxd" "$STAGED" || die "could not write to ${INSTALL_DIR}"
	chmod 0755 "$STAGED"
	mv -f "$STAGED" "${INSTALL_DIR}/pxd" || die "could not install to ${INSTALL_DIR}/pxd"
	STAGED=""
}

report() {
	say "Installed pxd to ${INSTALL_DIR}/pxd"

	case ":${PATH:-}:" in
	*":${INSTALL_DIR}:"*) ;;
	*)
		say ""
		say "${INSTALL_DIR} is not on your PATH. Add it with:"
		say "  export PATH=\"${INSTALL_DIR}:\$PATH\""
		;;
	esac

	# Verify the installed binary actually runs (wrong arch, truncated file).
	VERSION_OUTPUT=$("${INSTALL_DIR}/pxd" version 2>&1) ||
		die "the installed pxd failed to run: ${VERSION_OUTPUT}"
	say "$VERSION_OUTPUT"
}

main() {
	if [ -z "${HOME:-}" ] && [ -z "${PXD_INSTALL_DIR:-}" ]; then
		die "HOME is not set; set PXD_INSTALL_DIR to choose an install directory"
	fi
	INSTALL_DIR="${PXD_INSTALL_DIR:-${HOME}/.local/bin}"
	DOWNLOAD_BASE="${PXD_DOWNLOAD_BASE:-https://github.com/novaladip/pxd/releases}"

	detect_platform
	resolve_release
	download_files
	verify_checksum
	install_binary
	report
}

main "$@"
