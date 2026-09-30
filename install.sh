#!/usr/bin/env bash
# ============================================================================
#  EliteHost ServerInfo - installer (online + local)
#  Supported : Debian 12 (bookworm) / Debian 13 (trixie)
#
#  Online - one line, as root:
#    bash <(curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh)
#  Online - with sudo:
#    curl -fsSL https://raw.githubusercontent.com/SSMertnix/serverinfoscript/HEAD/install.sh | sudo bash
#  Local - next to the serverinfo file (git clone / downloaded files):
#    sudo ./install.sh
#
#  Online mode downloads ONE snapshot of this project's own GitHub repository
#  over HTTPS, pinned to an exact commit, validates it and installs it. Nothing
#  else is downloaded or executed; Debian packages come from your apt sources.
#
#  Signature : ELITEHOST-SERVERINFO
# ============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    echo "This installer needs bash:  bash <(curl -fsSL <url>)   or   sudo bash install.sh" >&2
    exit 1
fi

set -uo pipefail
umask 022
export LC_ALL=C.UTF-8 2>/dev/null

# Captured at top level: inside functions bash reports "main" when piped.
readonly SELF_PATH="${BASH_SOURCE[0]:-}"
readonly SI_SIGNATURE="ELITEHOST-SERVERINFO"
readonly DEFAULT_REPO="SSMertnix/serverinfoscript"
readonly BIN_PATH="/usr/local/bin/serverinfo"
readonly LIB_DIR="/usr/local/lib/elitehost-serverinfo"
readonly CONF_DIR="/etc/elitehost"
readonly CONF_FILE="$CONF_DIR/serverinfo.conf"
readonly COMPLETION_DIR="/usr/local/share/bash-completion/completions"
readonly COMPLETION_FILE="$COMPLETION_DIR/serverinfo"
readonly TOTAL_STEPS=5

REPO=${SERVERINFO_REPO:-$DEFAULT_REPO}   # owner/name on GitHub
REF=${SERVERINFO_REF:-HEAD}              # branch, tag or commit (HEAD = default branch)
GH_TOKEN=${SERVERINFO_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}   # only for private repositories
PIN_SHA256=${SERVERINFO_SHA256:-}        # optional: expected SHA-256 of serverinfo
FORCE=0
SKIP_DEPS=0
USE_COLOR=1
FORCE_ONLINE=0
DO_UNINSTALL=0
UNINSTALL_ARGS=()
MODE="local"
SRC_BIN=""
SRC_UNINSTALL=""
NEW_VERSION=""
OLD_VERSION=""
COMMIT=""
PKG_SHA256=""
WORK_DIR=""
LOG_FILE=""
SUCCESS=0
RUN_PID=""
TMP_FILES=()

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
C_RST="" C_BOLD="" C_BRAND="" C_GREEN="" C_YELLOW="" C_RED="" C_GRAY="" C_CYAN="" C_WHITE=""
LOGO_COLORS=()

setup_colors() {
    local c
    if (( ! USE_COLOR )) || [[ ! -t 1 || -n ${NO_COLOR:-} || ${TERM:-dumb} == dumb ]]; then
        return 0
    fi
    C_RST=$'\e[0m' C_BOLD=$'\e[1m' C_GREEN=$'\e[92m' C_YELLOW=$'\e[93m'
    C_RED=$'\e[91m' C_GRAY=$'\e[90m' C_CYAN=$'\e[96m' C_WHITE=$'\e[97m'
    if [[ ${TERM:-} == *256color* || -n ${COLORTERM:-} ]]; then
        C_BRAND=$'\e[38;5;135m'
        for c in 129 135 99 105 69 75; do LOGO_COLORS+=($'\e[38;5;'"${c}m"); done
    else
        C_BRAND=$'\e[35m'
    fi
}

info() { printf '   %s›%s %s\n' "$C_BRAND" "$C_RST" "$*"; }
ok()   { printf '   %s✔%s %s\n' "$C_GREEN" "$C_RST" "$*"; }
warn() { printf '   %s!%s %s\n' "$C_YELLOW" "$C_RST" "$*" >&2; }
kv()   { printf '   %s%-9s%s %s\n' "$C_GRAY" "$1" "$C_RST" "$2"; }
step() { printf '\n %s[%d/%d]%s %s%s%s\n' "$C_BRAND$C_BOLD" "$1" "$TOTAL_STEPS" "$C_RST" "$C_BOLD$C_WHITE" "$2" "$C_RST"; }
have() { command -v "$1" >/dev/null 2>&1; }

die() {
    printf '\n   %s✖ %s%s\n' "$C_RED$C_BOLD" "$*" "$C_RST" >&2
    if [[ -n $LOG_FILE && -s $LOG_FILE ]]; then
        printf '   %sDetails: %s%s\n' "$C_GRAY" "$LOG_FILE" "$C_RST" >&2
    fi
    echo >&2
    exit 1
}

banner() {
    local -a logo=(
        '███████╗██╗     ██╗████████╗███████╗'
        '██╔════╝██║     ██║╚══██╔══╝██╔════╝'
        '█████╗  ██║     ██║   ██║   █████╗  '
        '██╔══╝  ██║     ██║   ██║   ██╔══╝  '
        '███████╗███████╗██║   ██║   ███████╗'
        '╚══════╝╚══════╝╚═╝   ╚═╝   ╚══════╝'
    )
    local i
    echo
    for i in "${!logo[@]}"; do
        printf '   %s%s%s\n' "${LOGO_COLORS[i]:-$C_BRAND}" "${logo[i]}" "$C_RST"
    done
    printf '     %sELITEHOST%s %sSERVERINFO%s %s· installer%s\n' \
        "$C_BOLD$C_BRAND" "$C_RST" "$C_BOLD$C_WHITE" "$C_RST" "$C_GRAY" "$C_RST"
}

# box TEXT - centered text inside a rounded box
box() {
    local inner=44 text=$1 line pl pr
    printf -v line '%*s' "$inner" ''
    line=${line// /─}
    pl=$(( (inner - ${#text}) / 2 ))
    pr=$(( inner - ${#text} - pl ))
    printf '   %s╭%s╮%s\n' "$C_BRAND" "$line" "$C_RST"
    printf '   %s│%s%*s%s%s%s%*s%s│%s\n' "$C_BRAND" "$C_RST" "$pl" '' "$C_BOLD$C_WHITE" "$text" "$C_RST" "$pr" '' "$C_BRAND" "$C_RST"
    printf '   %s╰%s╯%s\n' "$C_BRAND" "$line" "$C_RST"
}

# run_task LABEL CMD [ARGS...] - run CMD with a spinner (on a terminal); its
# output goes to the install log, which is shown only if something fails.
run_task() {
    local label=$1 pid rc i=0 frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    shift
    printf '\n>>> %s\n' "$label" >> "$LOG_FILE" 2>/dev/null
    if [[ -t 1 && ${TERM:-dumb} != dumb ]]; then
        "$@" >> "$LOG_FILE" 2>&1 < /dev/null &
        pid=$!
        RUN_PID=$pid
        printf '\e[?25l'
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r   %s%s%s %s' "$C_BRAND" "${frames:i % 10:1}" "$C_RST" "$label"
            i=$(( i + 1 ))
            sleep 0.08
        done
        wait "$pid"
        rc=$?
        RUN_PID=""
        printf '\r\e[K\e[?25h'
    else
        "$@" >> "$LOG_FILE" 2>&1 < /dev/null
        rc=$?
    fi
    return "$rc"
}

cleanup() {
    local f
    [[ -t 1 ]] && printf '\e[?25h'
    for f in "${TMP_FILES[@]}"; do
        [[ -n $f && -e $f ]] && rm -f -- "$f"
    done
    if [[ -n $WORK_DIR && -d $WORK_DIR && $WORK_DIR == */elitehost-serverinfo.* ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    # keep the log only when it can explain a failure
    if [[ -n $LOG_FILE && -f $LOG_FILE ]] && { (( SUCCESS )) || [[ ! -s $LOG_FILE ]]; }; then
        rm -f -- "$LOG_FILE"
    fi
}
on_interrupt() {
    # background jobs ignore SIGINT in scripts: stop the running task explicitly
    [[ -n $RUN_PID ]] && kill "$RUN_PID" 2>/dev/null
    echo
    die "Installation interrupted"
}
trap cleanup EXIT
trap on_interrupt INT TERM

usage() {
    cat <<EOF
EliteHost ServerInfo installer

Online (as root):
  bash <(curl -fsSL https://raw.githubusercontent.com/$DEFAULT_REPO/HEAD/install.sh) [OPTIONS]
Online (with sudo):
  curl -fsSL https://raw.githubusercontent.com/$DEFAULT_REPO/HEAD/install.sh | sudo bash -s -- [OPTIONS]
Local:
  sudo ./install.sh [OPTIONS]

Options:
  --ref REF        Branch, tag or commit to install (default: HEAD = default branch)
  --online         Download from GitHub even when local files are present
  --uninstall      Remove EliteHost ServerInfo (add --yes / --keep-config)
  --force          Install on an unsupported OS (only Debian 12/13 are supported)
  --skip-deps      Do not install missing packages with apt
  --no-color       Disable colored output
  -h, --help       Show this help

Environment:
  SERVERINFO_REF      same as --ref
  SERVERINFO_SHA256   abort unless the downloaded serverinfo has this SHA-256
  SERVERINFO_REPO     install from a fork (owner/name)
  GITHUB_TOKEN        read access token, only needed for a private repository
                      (SERVERINFO_GITHUB_TOKEN takes precedence)
EOF
}

parse_args() {
    while (( $# > 0 )); do
        case $1 in
            --ref) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; REF=$2; shift ;;
            --ref=*) REF=${1#*=} ;;
            --online) FORCE_ONLINE=1 ;;
            --uninstall) DO_UNINSTALL=1; shift; UNINSTALL_ARGS=("$@"); return 0 ;;
            --force) FORCE=1 ;;
            --skip-deps) SKIP_DEPS=1 ;;
            --no-color|--no-colour) USE_COLOR=0 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; echo >&2; echo "Unknown option: $1" >&2; exit 2 ;;
        esac
        shift
    done
}

# ---------------------------------------------------------------------------
# Step 1 - system checks
# ---------------------------------------------------------------------------
check_system() {
    local key val id="" version_id="" codename="" pretty="" major=""
    step 1 "System checks"
    (( BASH_VERSINFO[0] >= 5 )) || die "Bash 5.x is required (found $BASH_VERSION)"
    ok "Bash $BASH_VERSION"
    if (( EUID != 0 )); then
        if [[ $MODE == online ]]; then
            die "Root privileges are required. Run:  curl -fsSL https://raw.githubusercontent.com/$REPO/HEAD/install.sh | sudo bash"
        fi
        die "Root privileges are required. Run:  sudo ./install.sh"
    fi
    ok "Running as root"

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
        ok "${pretty:-Debian $major}"
    elif (( FORCE )); then
        warn "Unsupported operating system: ${pretty:-unknown}. Continuing because of --force."
    else
        die "Unsupported operating system: ${pretty:-unknown}. Only Debian 12 and Debian 13 are supported (override with --force)."
    fi
}

# ---------------------------------------------------------------------------
# Step 2 - package (local files or an online snapshot)
# ---------------------------------------------------------------------------
# fetch URL OUTFILE [ACCEPT] - HTTPS-only download with retries (curl, or wget).
# A GitHub token is sent only to api.github.com and only through curl's stdin
# config - never on the command line (visible in ps) and never to redirects.
fetch() {
    local url=$1 out=$2 accept=${3:-}
    local -a args=()
    if have curl; then
        args=(-fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 --retry-delay 2
              --connect-timeout 15 --max-time 180 -o "$out")
        [[ -n $accept ]] && args+=(-H "Accept: $accept")
        if [[ -n $GH_TOKEN && $url == https://api.github.com/* ]]; then
            printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN" | curl -q --config - "${args[@]}" "$url"
        else
            curl -q "${args[@]}" "$url"
        fi
    elif have wget; then
        args=(-q --https-only --tries=3 --timeout=30 -O "$out")
        [[ -n $accept ]] && args+=(--header="Accept: $accept")
        wget "${args[@]}" "$url"
    else
        return 127
    fi
}

download_package() {
    local ref_enc target url size downloaded=0
    local -a urls=() found=()
    step 2 "Download"
    [[ $REPO =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]] || die "Invalid repository name: $REPO"
    if [[ ! $REF =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$ || $REF == *..* || $REF == *//* ]]; then
        die "Invalid --ref value: $REF"
    fi
    if [[ -n $GH_TOKEN && ! $GH_TOKEN =~ ^[A-Za-z0-9_.-]{8,255}$ ]]; then
        warn "Ignoring GITHUB_TOKEN: unexpected format"
        GH_TOKEN=""
    fi
    have curl || have wget || die "curl or wget is required for the online install (apt install curl)"
    if [[ -n $GH_TOKEN ]] && ! have curl; then
        die "GITHUB_TOKEN needs curl (apt install curl)"
    fi
    if ! have tar || ! have gzip; then
        die "tar and gzip are required"
    fi
    kv "Source" "github.com/$REPO @ $REF"

    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/elitehost-serverinfo.XXXXXXXX") || die "Cannot create a temporary directory"
    ref_enc=${REF//\//%2F}

    # 1) pin the ref to an exact commit: consistent, auditable snapshot
    if run_task "Resolving version..." fetch "https://api.github.com/repos/$REPO/commits/$ref_enc" \
        "$WORK_DIR/commit" "application/vnd.github.sha"; then
        # the API answers without a trailing newline: read's status is irrelevant
        IFS= read -r COMMIT < "$WORK_DIR/commit"
        [[ $COMMIT =~ ^[0-9a-f]{40}$ ]] || COMMIT=""
    fi
    if [[ -n $COMMIT ]]; then
        ok "Version  $REF → commit ${COMMIT:0:12}"
    elif grep -qE 'returned error: (404|422)' "$LOG_FILE" 2>/dev/null; then
        die "Version '$REF' was not found in github.com/$REPO (or the repository is private - set GITHUB_TOKEN)"
    else
        warn "Could not pin $REF to a commit (GitHub API unreachable or rate-limited) - using $REF"
    fi

    # 2) one archive = every file from the same commit
    target=${COMMIT:-$REF}
    [[ -z $GH_TOKEN ]] && urls+=("https://github.com/$REPO/archive/$target.tar.gz")
    urls+=("https://api.github.com/repos/$REPO/tarball/${target//\//%2F}")
    for url in "${urls[@]}"; do
        if run_task "Downloading package..." fetch "$url" "$WORK_DIR/package.tar.gz"; then
            downloaded=1
            break
        fi
    done
    if (( ! downloaded )); then
        die "Download failed. Check the network, the --ref value, and that github.com/$REPO is public (or set GITHUB_TOKEN)."
    fi
    size=$(stat -c %s "$WORK_DIR/package.tar.gz" 2>/dev/null) || size=0
    ok "Downloaded $(( (size + 1023) / 1024 )) KiB"

    # 3) unpack (never with the archive's owners/permissions) and validate the layout
    mkdir -p "$WORK_DIR/pkg" || die "Cannot create $WORK_DIR/pkg"
    tar -xzf "$WORK_DIR/package.tar.gz" -C "$WORK_DIR/pkg" --no-same-owner --no-same-permissions \
        >> "$LOG_FILE" 2>&1 || die "The downloaded archive is damaged"
    found=("$WORK_DIR"/pkg/*/serverinfo)
    [[ ${#found[@]} -eq 1 && -f ${found[0]} ]] || die "Unexpected archive layout (serverinfo not found)"
    SRC_BIN=${found[0]}
    SRC_UNINSTALL=${SRC_BIN%/serverinfo}/uninstall.sh
}

use_local_package() {
    step 2 "Package"
    kv "Source" "local files ($(dirname -- "$SRC_BIN"))"
}

validate_package() {
    local sum
    [[ -f $SRC_BIN ]] || die "serverinfo not found: $SRC_BIN"
    grep -q "$SI_SIGNATURE" "$SRC_BIN" || die "$SRC_BIN is not an EliteHost ServerInfo script"
    if ! tr -d '\r' < "$SRC_BIN" | bash -n 2>/dev/null; then
        die "serverinfo contains a syntax error - the file is incomplete or corrupted"
    fi
    NEW_VERSION=$(sed -n 's/^readonly SI_VERSION="\([^"]*\)".*/\1/p' "$SRC_BIN")
    NEW_VERSION=${NEW_VERSION%%$'\n'*}
    if sum=$(sha256sum "$SRC_BIN" 2>/dev/null); then
        PKG_SHA256=${sum%% *}
    fi
    if [[ -n $PIN_SHA256 ]]; then
        [[ ${PIN_SHA256,,} == "$PKG_SHA256" ]] \
            || die "SHA-256 mismatch: expected ${PIN_SHA256,,}, got ${PKG_SHA256:-unknown}"
        ok "SHA-256 matches SERVERINFO_SHA256"
    fi
    ok "serverinfo v${NEW_VERSION:-unknown}  ${C_GRAY}sha256 ${PKG_SHA256:0:16}…${C_RST}"

    if [[ -f $BIN_PATH ]] && grep -qs "$SI_SIGNATURE" "$BIN_PATH"; then
        OLD_VERSION=$(sed -n 's/^readonly SI_VERSION="\([^"]*\)".*/\1/p' "$BIN_PATH")
        OLD_VERSION=${OLD_VERSION%%$'\n'*}
        info "Existing installation v${OLD_VERSION:-unknown} will be updated"
    elif [[ -e $BIN_PATH ]]; then
        die "$BIN_PATH exists and does not belong to EliteHost ServerInfo - refusing to overwrite it"
    fi
}

# ---------------------------------------------------------------------------
# Step 3 - dependencies (apt, only when something is missing)
# ---------------------------------------------------------------------------
apt_install() {
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 -y -q \
        --no-install-recommends install "$@"
}

apt_update() {
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=120 -q update
}

install_dependencies() {
    step 3 "Dependencies"
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
    local -a pkgs=()
    local cmd
    for cmd in "${!dep_pkg[@]}"; do
        have "$cmd" || missing[${dep_pkg[$cmd]}]=1
    done
    [[ -f /etc/ssl/certs/ca-certificates.crt ]] || missing[ca-certificates]=1

    if (( ${#missing[@]} == 0 )); then
        ok "All dependencies are already installed - apt not needed"
        return 0
    fi
    mapfile -t pkgs < <(printf '%s\n' "${!missing[@]}" | sort)
    if (( SKIP_DEPS )); then
        warn "Missing packages (not installed because of --skip-deps): ${pkgs[*]}"
        return 0
    fi
    if ! have apt-get; then
        warn "apt-get not found. Install manually: ${pkgs[*]}"
        return 0
    fi
    if run_task "Installing ${pkgs[*]}..." apt_install "${pkgs[@]}"; then
        ok "Installed: ${pkgs[*]}"
        return 0
    fi
    # Package lists may be empty or outdated (fresh image): refresh once and retry
    run_task "Refreshing package lists (apt-get update)..." apt_update \
        || warn "apt-get update failed (no network or repository problem)"
    if run_task "Installing ${pkgs[*]}..." apt_install "${pkgs[@]}"; then
        ok "Installed: ${pkgs[*]}"
    else
        warn "Could not install: ${pkgs[*]}"
        warn "serverinfo will still work, with fewer details (e.g. no Wings API server counts without curl/jq)"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Step 4 - files
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
    local tmp dir
    step 4 "Installing files"
    # create only missing directories: existing ones keep their mode/owner
    # (e.g. Debian's setgid root:staff /usr/local tree)
    for dir in /usr/local/bin "$LIB_DIR" "$CONF_DIR" "$COMPLETION_DIR"; do
        [[ -d $dir ]] || install -d -m 0755 "$dir" || die "Could not create directory $dir"
    done

    place_file "$SRC_BIN" "$BIN_PATH" 0755 || die "Failed to install $BIN_PATH"
    ok "$BIN_PATH"

    if [[ -f $SRC_UNINSTALL ]] && grep -q "$SI_SIGNATURE" "$SRC_UNINSTALL"; then
        place_file "$SRC_UNINSTALL" "$LIB_DIR/uninstall.sh" 0755 || die "Failed to install the uninstaller"
        ok "$LIB_DIR/uninstall.sh"
    else
        warn "uninstall.sh not found - 'serverinfo --uninstall' will not be available"
    fi

    if [[ -e $CONF_FILE ]]; then
        info "Keeping existing configuration $CONF_FILE"
    else
        tmp=$(mktemp) || die "mktemp failed"
        TMP_FILES+=("$tmp")
        if ! "$BIN_PATH" --print-config > "$tmp" || ! place_file "$tmp" "$CONF_FILE" 0644; then
            die "Failed to create $CONF_FILE"
        fi
        ok "$CONF_FILE"
    fi

    tmp=$(mktemp) || die "mktemp failed"
    TMP_FILES+=("$tmp")
    if [[ -e $COMPLETION_FILE ]] && ! grep -qs "$SI_SIGNATURE" "$COMPLETION_FILE"; then
        warn "$COMPLETION_FILE belongs to another program - bash completion not installed"
    elif "$BIN_PATH" --completion > "$tmp" && place_file "$tmp" "$COMPLETION_FILE" 0644; then
        ok "$COMPLETION_FILE"
        [[ -f /usr/share/bash-completion/bash_completion ]] \
            || info "Tip: 'apt install bash-completion' enables Tab completion in your shell"
    else
        warn "Bash completion could not be installed (optional)"
    fi
}

# ---------------------------------------------------------------------------
# Step 5 - verification
# ---------------------------------------------------------------------------
verify_install() {
    local out
    step 5 "Verification"
    out=$("$BIN_PATH" --version 2>/dev/null) || die "Verification failed: $BIN_PATH --version"
    ok "$out"
    if run_task "Running self-test..." "$BIN_PATH" --json; then
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
    local one_liner="bash <(curl -fsSL https://raw.githubusercontent.com/$REPO/HEAD/install.sh)"
    echo
    box "ELITEHOST SERVERINFO INSTALLED"
    if [[ -n $OLD_VERSION && $OLD_VERSION != "$NEW_VERSION" ]]; then
        printf '\n   %sUpdated v%s → v%s%s\n' "$C_GRAY" "$OLD_VERSION" "$NEW_VERSION" "$C_RST"
    elif [[ -n $OLD_VERSION ]]; then
        printf '\n   %sReinstalled v%s%s\n' "$C_GRAY" "$NEW_VERSION" "$C_RST"
    fi
    cat <<EOF

   ${C_BOLD}Run:${C_RST}
       ${C_CYAN}serverinfo${C_RST}

   ${C_BOLD}Live mode:${C_RST}
       ${C_CYAN}serverinfo --live${C_RST}

   ${C_BOLD}Help:${C_RST}
       ${C_CYAN}serverinfo --help${C_RST}

EOF
    if [[ $MODE == online ]]; then
        if [[ -n $COMMIT ]]; then
            kv "Source" "github.com/$REPO @ ${COMMIT:0:12} ($REF)"
        else
            kv "Source" "github.com/$REPO @ $REF"
        fi
        kv "Update" "$one_liner"
    fi
    kv "Config" "$CONF_FILE"
    kv "Remove" "serverinfo --uninstall"
    echo
}

# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    setup_colors

    if [[ -n $SELF_PATH && -f $SELF_PATH ]] && (( ! FORCE_ONLINE )); then
        SRC_BIN="$(cd -- "$(dirname -- "$SELF_PATH")" && pwd -P)/serverinfo"
        SRC_UNINSTALL="${SRC_BIN%/serverinfo}/uninstall.sh"
        [[ -f $SRC_BIN ]] || MODE=online
    else
        MODE=online
    fi

    if (( DO_UNINSTALL )); then
        local un="$LIB_DIR/uninstall.sh"
        [[ -f $un ]] || un="${SRC_UNINSTALL:-}"
        if [[ -z $un || ! -f $un ]]; then
            echo "EliteHost ServerInfo is not installed - nothing to remove."
            exit 0
        fi
        exec bash "$un" "${UNINSTALL_ARGS[@]}"
    fi

    LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/elitehost-serverinfo-install.XXXXXX.log" 2>/dev/null) || LOG_FILE=/dev/null
    banner
    check_system
    if [[ $MODE == online ]]; then
        download_package
    else
        use_local_package
    fi
    validate_package
    install_dependencies
    install_files
    verify_install
    SUCCESS=1
    finish
}

main "$@"
