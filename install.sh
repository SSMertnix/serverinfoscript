#!/usr/bin/env bash
# ============================================================================
#  EliteHost ServerInfo - installer
#  Supported : Debian 12 (bookworm) / Debian 13 (trixie)
#  Usage     : sudo ./install.sh [--force] [--skip-deps] [--no-color] [--help]
#  Signature : ELITEHOST-SERVERINFO
#
#  What it does
#   1. checks Bash, root privileges and the Debian version (12 or 13)
#   2. installs missing dependencies with apt - only when something is missing
#   3. installs serverinfo to /usr/local/bin/serverinfo (atomic replace)
#   4. installs the uninstaller, a default config and bash completion
#  It never downloads or executes remote code: everything is installed from
#  the files next to this script. Debian packages come from your own apt
#  repositories.
# ============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    echo "This installer needs bash. Run: sudo bash install.sh" >&2
    exit 1
fi

set -uo pipefail
umask 022
export LC_ALL=C.UTF-8 2>/dev/null

readonly SI_SIGNATURE="ELITEHOST-SERVERINFO"
readonly BIN_PATH="/usr/local/bin/serverinfo"
readonly LIB_DIR="/usr/local/lib/elitehost-serverinfo"
readonly CONF_DIR="/etc/elitehost"
readonly CONF_FILE="$CONF_DIR/serverinfo.conf"
readonly COMPLETION_DIR="/usr/local/share/bash-completion/completions"
readonly COMPLETION_FILE="$COMPLETION_DIR/serverinfo"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly SRC_BIN="$SCRIPT_DIR/serverinfo"
readonly SRC_UNINSTALL="$SCRIPT_DIR/uninstall.sh"

FORCE=0
SKIP_DEPS=0
USE_COLOR=1
NEW_VERSION=""
OLD_VERSION=""
TMP_FILES=()

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
C_RST="" C_BOLD="" C_BRAND="" C_GREEN="" C_YELLOW="" C_RED="" C_GRAY="" C_CYAN="" C_WHITE=""

setup_colors() {
    if (( USE_COLOR )) && [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        C_RST=$'\e[0m' C_BOLD=$'\e[1m' C_BRAND=$'\e[38;5;135m' C_GREEN=$'\e[92m'
        C_YELLOW=$'\e[93m' C_RED=$'\e[91m' C_GRAY=$'\e[90m' C_CYAN=$'\e[96m' C_WHITE=$'\e[97m'
    fi
}

info() { printf ' %s›%s %s\n' "$C_BRAND" "$C_RST" "$*"; }
ok()   { printf ' %s✔%s %s\n' "$C_GREEN" "$C_RST" "$*"; }
warn() { printf ' %s!%s %s\n' "$C_YELLOW" "$C_RST" "$*" >&2; }
die()  { printf ' %s✖%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
step() { printf '\n %s%s%s\n' "$C_BOLD$C_WHITE" "$*" "$C_RST"; }
have() { command -v "$1" >/dev/null 2>&1; }

# box TEXT - centered text inside a rounded box (48 columns)
box() {
    local inner=46 text=$1 line pl pr
    printf -v line '%*s' "$inner" ''
    line=${line// /─}
    pl=$(( (inner - ${#text}) / 2 ))
    pr=$(( inner - ${#text} - pl ))
    printf ' %s╭%s╮%s\n' "$C_BRAND" "$line" "$C_RST"
    printf ' %s│%s%*s%s%s%s%*s%s│%s\n' "$C_BRAND" "$C_RST" "$pl" '' "$C_BOLD$C_WHITE" "$text" "$C_RST" "$pr" '' "$C_BRAND" "$C_RST"
    printf ' %s╰%s╯%s\n' "$C_BRAND" "$line" "$C_RST"
}

cleanup() {
    local f
    for f in "${TMP_FILES[@]}"; do
        [[ -n $f && -e $f ]] && rm -f -- "$f"
    done
}
trap cleanup EXIT
trap 'echo; die "Installation interrupted"' INT TERM

usage() {
    cat <<EOF
EliteHost ServerInfo installer

Usage: sudo ./install.sh [OPTIONS]

Options:
  --force        Install on an unsupported OS (only Debian 12/13 are supported)
  --skip-deps    Do not install missing packages with apt
  --no-color     Disable colored output
  -h, --help     Show this help
EOF
}

parse_args() {
    while (( $# > 0 )); do
        case $1 in
            --force) FORCE=1 ;;
            --skip-deps) SKIP_DEPS=1 ;;
            --no-color|--no-colour) USE_COLOR=0 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; echo >&2; die "Unknown option: $1" ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
check_environment() {
    step "1/4  System checks"
    (( BASH_VERSINFO[0] >= 5 )) || die "Bash 5.x is required (found $BASH_VERSION)"
    ok "Bash $BASH_VERSION"
    (( EUID == 0 )) || die "Root privileges are required. Run: sudo ./install.sh"
    ok "Running as root"

    local key val id="" version_id="" codename="" pretty="" major=""
    [[ -r /etc/os-release ]] || die "/etc/os-release not found - cannot detect the operating system"
    while IFS='=' read -r key val; do
        val=${val#[\"\']}
        val=${val%[\"\']}
        case $key in
            ID) id=$val ;;
            VERSION_ID) version_id=$val ;;
            VERSION_CODENAME) codename=$val ;;
            PRETTY_NAME) pretty=$val ;;
        esac
    done < /etc/os-release
    case $version_id in
        12|12.*) major=12 ;;
        13|13.*) major=13 ;;
    esac
    if [[ -z $major ]]; then
        case $codename in
            bookworm) major=12 ;;
            trixie) major=13 ;;
        esac
    fi
    if [[ $id == debian && -n $major ]]; then
        ok "Operating system: ${pretty:-Debian} (Debian $major)"
    elif (( FORCE )); then
        warn "Unsupported operating system: ${pretty:-unknown}. Continuing because of --force."
    else
        die "Unsupported operating system: ${pretty:-unknown}. Only Debian 12 and Debian 13 are supported (override with --force)."
    fi

    [[ -f $SRC_BIN ]] || die "File not found: $SRC_BIN (keep install.sh and serverinfo in the same directory)"
    grep -q "$SI_SIGNATURE" "$SRC_BIN" || die "$SRC_BIN is not an EliteHost ServerInfo script"
    if tr -d '\r' < "$SRC_BIN" | bash -n 2>/dev/null; then
        :
    else
        die "$SRC_BIN contains a syntax error - the file is incomplete or corrupted"
    fi
    NEW_VERSION=$(sed -n 's/^readonly SI_VERSION="\([^"]*\)".*/\1/p' "$SRC_BIN")
    NEW_VERSION=${NEW_VERSION%%$'\n'*}
    ok "Package: serverinfo v${NEW_VERSION:-unknown}"
    if [[ -f $BIN_PATH ]] && grep -qs "$SI_SIGNATURE" "$BIN_PATH"; then
        OLD_VERSION=$(sed -n 's/^readonly SI_VERSION="\([^"]*\)".*/\1/p' "$BIN_PATH")
        OLD_VERSION=${OLD_VERSION%%$'\n'*}
        info "Existing installation found (v${OLD_VERSION:-unknown}) - it will be upgraded"
    elif [[ -e $BIN_PATH ]]; then
        die "$BIN_PATH exists and does not belong to EliteHost ServerInfo - refusing to overwrite it"
    fi
}

# ---------------------------------------------------------------------------
# Dependencies (apt, only when something is missing)
# ---------------------------------------------------------------------------
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 -y -qq \
        --no-install-recommends install "$@" >/dev/null 2>&1
}

install_dependencies() {
    step "2/4  Dependencies"
    # command -> Debian package. Everything is optional at runtime (serverinfo
    # degrades gracefully), but these give the complete feature set:
    #   curl + jq  : live Pterodactyl server states from the local Wings API
    #   iproute2   : per-interface IPv4 addresses
    #   procps     : process checks on hosts without systemd
    local -A dep_pkg=(
        [curl]=curl [jq]=jq [ip]=iproute2 [pgrep]=procps
        [lscpu]=util-linux [lsblk]=util-linux [findmnt]=util-linux
        [timeout]=coreutils [df]=coreutils [awk]=mawk [sed]=sed [grep]=grep
        [tput]=ncurses-bin [find]=findutils [hostname]=hostname
    )
    local -A missing=()
    local cmd
    for cmd in "${!dep_pkg[@]}"; do
        have "$cmd" || missing[${dep_pkg[$cmd]}]=1
    done
    [[ -f /etc/ssl/certs/ca-certificates.crt ]] || missing[ca-certificates]=1

    if (( ${#missing[@]} == 0 )); then
        ok "All dependencies are already installed - apt not needed"
        return 0
    fi
    local -a pkgs
    mapfile -t pkgs < <(printf '%s\n' "${!missing[@]}" | sort)
    if (( SKIP_DEPS )); then
        warn "Missing packages (not installed because of --skip-deps): ${pkgs[*]}"
        return 0
    fi
    if ! have apt-get; then
        warn "apt-get not found. Install manually: ${pkgs[*]}"
        return 0
    fi
    info "Installing missing packages: ${pkgs[*]}"
    if apt_install "${pkgs[@]}"; then
        ok "Dependencies installed"
        return 0
    fi
    # Package lists may be empty or outdated (fresh image) - refresh once and retry
    info "Refreshing package lists (apt-get update)..."
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 -qq update >/dev/null 2>&1 \
        || warn "apt-get update failed (no network or repository problem)"
    if apt_install "${pkgs[@]}"; then
        ok "Dependencies installed"
    else
        warn "Could not install: ${pkgs[*]}"
        warn "serverinfo will still work, with fewer details (e.g. no Wings API server counts without curl/jq)"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------
# place_file SRC DEST MODE - normalize line endings, validate, then atomic rename
place_file() {
    local src=$1 dest=$2 mode=$3 tmp
    tmp=$(mktemp "${dest}.XXXXXX") || return 1
    TMP_FILES+=("$tmp")
    tr -d '\r' < "$src" > "$tmp" || return 1
    if [[ $dest != *.conf && $dest != "$COMPLETION_FILE" ]]; then
        bash -n "$tmp" 2>/dev/null || return 1
    fi
    chmod "$mode" "$tmp" && chown root:root "$tmp" && mv -f -- "$tmp" "$dest"
}

install_files() {
    step "3/4  Installing files"
    local tmp dir
    # create only missing directories: existing ones keep their mode/owner
    # (e.g. Debian's setgid root:staff /usr/local tree)
    for dir in /usr/local/bin "$LIB_DIR" "$CONF_DIR" "$COMPLETION_DIR"; do
        [[ -d $dir ]] || install -d -m 0755 "$dir" || die "Could not create directory $dir"
    done

    place_file "$SRC_BIN" "$BIN_PATH" 0755 || die "Failed to install $BIN_PATH"
    ok "Installed $BIN_PATH"

    if [[ -f $SRC_UNINSTALL ]] && grep -q "$SI_SIGNATURE" "$SRC_UNINSTALL"; then
        place_file "$SRC_UNINSTALL" "$LIB_DIR/uninstall.sh" 0755 || die "Failed to install the uninstaller"
        ok "Installed $LIB_DIR/uninstall.sh"
    else
        warn "uninstall.sh not found next to install.sh - 'serverinfo --uninstall' will not be available"
    fi

    if [[ -e $CONF_FILE ]]; then
        info "Keeping existing configuration $CONF_FILE"
    else
        tmp=$(mktemp) || die "mktemp failed"
        TMP_FILES+=("$tmp")
        if ! "$BIN_PATH" --print-config > "$tmp" || ! place_file "$tmp" "$CONF_FILE" 0644; then
            die "Failed to create $CONF_FILE"
        fi
        ok "Created $CONF_FILE"
    fi

    tmp=$(mktemp) || die "mktemp failed"
    TMP_FILES+=("$tmp")
    if [[ -e $COMPLETION_FILE ]] && ! grep -qs "$SI_SIGNATURE" "$COMPLETION_FILE"; then
        warn "$COMPLETION_FILE belongs to another program - bash completion not installed"
    elif "$BIN_PATH" --completion > "$tmp" && place_file "$tmp" "$COMPLETION_FILE" 0644; then
        if [[ -f /usr/share/bash-completion/bash_completion ]]; then
            ok "Bash completion installed (serverinfo --<TAB>)"
        else
            ok "Bash completion installed"
            info "Tip: 'apt install bash-completion' enables Tab completion in your shell"
        fi
    else
        warn "Bash completion could not be installed (optional)"
    fi
}

verify_install() {
    step "4/4  Verification"
    local out
    out=$("$BIN_PATH" --version 2>/dev/null) || die "Verification failed: $BIN_PATH --version"
    ok "$out"
    if "$BIN_PATH" --json >/dev/null 2>&1; then
        ok "Self-test passed (serverinfo --json)"
    else
        warn "Self-test returned an error - run 'serverinfo' to see details"
    fi
    case ":$PATH:" in
        *:/usr/local/bin:*) ;;
        *) warn "/usr/local/bin is not in your PATH - run $BIN_PATH directly" ;;
    esac
}

finish() {
    echo
    box "ELITEHOST SERVERINFO INSTALLED"
    [[ -n $OLD_VERSION ]] && printf '\n %sUpgraded v%s → v%s%s\n' "$C_GRAY" "$OLD_VERSION" "$NEW_VERSION" "$C_RST"
    cat <<EOF

 ${C_BOLD}Run:${C_RST}
     ${C_CYAN}serverinfo${C_RST}

 ${C_BOLD}Live mode:${C_RST}
     ${C_CYAN}serverinfo --live${C_RST}

 ${C_BOLD}Help:${C_RST}
     ${C_CYAN}serverinfo --help${C_RST}

 ${C_GRAY}Config: $CONF_FILE   ·   Uninstall: sudo serverinfo --uninstall${C_RST}

EOF
}

main() {
    parse_args "$@"
    setup_colors
    echo
    box "ELITEHOST SERVERINFO · INSTALLER"
    check_environment
    install_dependencies
    install_files
    verify_install
    finish
}

main "$@"
