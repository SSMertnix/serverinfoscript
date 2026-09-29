#!/usr/bin/env bash
# ============================================================================
#  EliteHost ServerInfo - uninstaller
#  Usage     : sudo ./uninstall.sh [--yes] [--keep-config] [--no-color]
#              sudo serverinfo --uninstall [--yes] [--keep-config]
#  Signature : ELITEHOST-SERVERINFO
#
#  Safe removal: only files that carry the EliteHost ServerInfo signature are
#  deleted (never rm -rf), directories are removed only when empty, and
#  nothing else on the system (Pterodactyl, Wings, Docker, packages) is touched.
# ============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    echo "This uninstaller needs bash. Run: sudo bash uninstall.sh" >&2
    exit 1
fi

set -uo pipefail
export LC_ALL=C.UTF-8 2>/dev/null

readonly SI_SIGNATURE="ELITEHOST-SERVERINFO"
readonly BIN_PATH="/usr/local/bin/serverinfo"
readonly LIB_DIR="/usr/local/lib/elitehost-serverinfo"
readonly CONF_DIR="/etc/elitehost"
readonly CONF_FILE="$CONF_DIR/serverinfo.conf"
readonly COMPLETION_FILE="/usr/local/share/bash-completion/completions/serverinfo"

ASSUME_YES=0
KEEP_CONFIG=0
USE_COLOR=1

C_RST="" C_BOLD="" C_BRAND="" C_GREEN="" C_YELLOW="" C_RED="" C_GRAY="" C_WHITE=""
setup_colors() {
    if (( USE_COLOR )) && [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        C_RST=$'\e[0m' C_BOLD=$'\e[1m' C_BRAND=$'\e[38;5;135m' C_GREEN=$'\e[92m'
        C_YELLOW=$'\e[93m' C_RED=$'\e[91m' C_GRAY=$'\e[90m' C_WHITE=$'\e[97m'
    fi
}

info() { printf ' %s›%s %s\n' "$C_BRAND" "$C_RST" "$*"; }
ok()   { printf ' %s✔%s %s\n' "$C_GREEN" "$C_RST" "$*"; }
warn() { printf ' %s!%s %s\n' "$C_YELLOW" "$C_RST" "$*" >&2; }
die()  { printf ' %s✖%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

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

usage() {
    cat <<EOF
EliteHost ServerInfo uninstaller

Usage: sudo ./uninstall.sh [OPTIONS]
       sudo serverinfo --uninstall [OPTIONS]

Options:
  -y, --yes        Do not ask for confirmation
  --keep-config    Keep $CONF_FILE
  --no-color       Disable colored output
  -h, --help       Show this help
EOF
}

# is_ours FILE - true when FILE is a regular file carrying our signature
is_ours() {
    [[ -f $1 ]] && grep -qs "$SI_SIGNATURE" "$1"
}

main() {
    local f answer removed=0
    local -a targets=()
    while (( $# > 0 )); do
        case $1 in
            -y|--yes) ASSUME_YES=1 ;;
            --keep-config) KEEP_CONFIG=1 ;;
            --no-color|--no-colour) USE_COLOR=0 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; echo >&2; die "Unknown option: $1" ;;
        esac
        shift
    done
    setup_colors
    echo
    box "ELITEHOST SERVERINFO · UNINSTALL"
    echo
    (( EUID == 0 )) || die "Root privileges are required. Run: sudo $0 (or: sudo serverinfo --uninstall)"

    for f in "$BIN_PATH" "$COMPLETION_FILE" "$LIB_DIR/uninstall.sh"; do
        if is_ours "$f"; then
            targets+=("$f")
        elif [[ -e $f ]]; then
            warn "Skipping $f - it does not belong to EliteHost ServerInfo"
        fi
    done
    if (( KEEP_CONFIG )); then
        [[ -e $CONF_FILE ]] && info "Keeping configuration $CONF_FILE (--keep-config)"
    elif is_ours "$CONF_FILE"; then
        targets+=("$CONF_FILE")
    elif [[ -e $CONF_FILE ]]; then
        warn "Skipping $CONF_FILE - signature line missing, remove it manually if needed"
    fi

    if (( ${#targets[@]} == 0 )); then
        info "EliteHost ServerInfo is not installed - nothing to remove"
        exit 0
    fi

    info "The following files will be removed:"
    for f in "${targets[@]}"; do
        printf '     %s%s%s\n' "$C_GRAY" "$f" "$C_RST"
    done
    echo

    if (( ! ASSUME_YES )); then
        if [[ ! -t 0 ]]; then
            die "No terminal to confirm on. Re-run with --yes to remove without a prompt."
        fi
        read -r -p " Remove EliteHost ServerInfo? [y/N] " answer
        if [[ ! $answer =~ ^[Yy]([Ee][Ss])?$ ]]; then
            info "Aborted - nothing was removed"
            exit 0
        fi
    fi

    for f in "${targets[@]}"; do
        if rm -f -- "$f"; then
            ok "Removed $f"
            removed=$(( removed + 1 ))
        else
            warn "Could not remove $f"
        fi
    done
    # directories are removed only if they are empty (rmdir never deletes content)
    for f in "$LIB_DIR" "$CONF_DIR" "${COMPLETION_FILE%/*}" "${COMPLETION_FILE%/*/*}"; do
        rmdir -- "$f" 2>/dev/null && ok "Removed empty directory $f"
    done

    echo
    box "ELITEHOST SERVERINFO REMOVED"
    printf '\n %s%d file(s) removed. Pterodactyl, Wings, Docker and system packages were not touched.%s\n\n' \
        "$C_GRAY" "$removed" "$C_RST"
}

main "$@"
