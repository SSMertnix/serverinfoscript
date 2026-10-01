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
    echo "Bu oʻchirish dasturi bash talab qiladi. Ishga tushiring: sudo bash uninstall.sh" >&2
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
EliteHost ServerInfo oʻchirish dasturi

Foydalanish: sudo ./uninstall.sh [PARAMETRLAR]
             sudo serverinfo --uninstall [PARAMETRLAR]

Parametrlar:
  -y, --yes        Tasdiqlash soʻralmasin
  --keep-config    $CONF_FILE saqlab qolinsin
  --no-color       Ranglarsiz chiqish
  -h, --help       Shu yordam
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
            *) usage >&2; echo >&2; die "Nomaʼlum parametr: $1" ;;
        esac
        shift
    done
    setup_colors
    echo
    box "ELITEHOST SERVERINFO · OʻCHIRISH"
    echo
    (( EUID == 0 )) || die "Root huquqi kerak. Ishga tushiring: sudo $0 (yoki: sudo serverinfo --uninstall)"

    for f in "$BIN_PATH" "$COMPLETION_FILE" "$LIB_DIR/uninstall.sh"; do
        if is_ours "$f"; then
            targets+=("$f")
        elif [[ -e $f ]]; then
            warn "Oʻtkazib yuborildi: $f - EliteHost ServerInfo ga tegishli emas"
        fi
    done
    if (( KEEP_CONFIG )); then
        [[ -e $CONF_FILE ]] && info "Sozlamalar saqlanadi: $CONF_FILE (--keep-config)"
    elif is_ours "$CONF_FILE"; then
        targets+=("$CONF_FILE")
    elif [[ -e $CONF_FILE ]]; then
        warn "Oʻtkazib yuborildi: $CONF_FILE - imzo qatori yoʻq, kerak boʻlsa qoʻlda oʻchiring"
    fi

    if (( ${#targets[@]} == 0 )); then
        info "EliteHost ServerInfo oʻrnatilmagan - oʻchiradigan narsa yoʻq"
        exit 0
    fi

    info "Quyidagi fayllar oʻchiriladi:"
    for f in "${targets[@]}"; do
        printf '     %s%s%s\n' "$C_GRAY" "$f" "$C_RST"
    done
    echo

    if (( ! ASSUME_YES )); then
        if [[ ! -t 0 ]]; then
            die "Tasdiqlash uchun terminal yoʻq. Soʻrovsiz oʻchirish uchun --yes bilan qayta ishga tushiring."
        fi
        read -r -p " EliteHost ServerInfo oʻchirilsinmi? [ha/YOʻQ] " answer
        if [[ ! $answer =~ ^([Hh]([Aa])?|[Yy]([Ee][Ss])?)$ ]]; then
            info "Bekor qilindi - hech narsa oʻchirilmadi"
            exit 0
        fi
    fi

    for f in "${targets[@]}"; do
        if rm -f -- "$f"; then
            ok "Oʻchirildi: $f"
            removed=$(( removed + 1 ))
        else
            warn "Oʻchirib boʻlmadi: $f"
        fi
    done
    # directories are removed only if they are empty (rmdir never deletes content)
    for f in "$LIB_DIR" "$CONF_DIR" "${COMPLETION_FILE%/*}" "${COMPLETION_FILE%/*/*}"; do
        rmdir -- "$f" 2>/dev/null && ok "Boʻsh papka oʻchirildi: $f"
    done

    echo
    box "ELITEHOST SERVERINFO OʻCHIRILDI"
    printf '\n %s%d ta fayl oʻchirildi. Pterodactyl, Wings, Docker va tizim paketlariga tegilmadi.%s\n\n' \
        "$C_GRAY" "$removed" "$C_RST"
}

main "$@"
