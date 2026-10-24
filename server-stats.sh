#!/usr/bin/env bash
#
# server-stats.sh - basic Linux server performance report
#
# Reports:
#   * total CPU usage
#   * memory usage (used vs free, with percentage)
#   * disk usage (used vs free, with percentage)
#   * top processes by CPU usage
#   * top processes by memory usage
#
# Extras:
#   * OS / kernel / architecture
#   * uptime and load average
#   * CPU core count and process count
#   * logged in users
#   * failed login attempts (auth.log / secure / journald / lastb)
#   * mounted filesystem usage
#
# Usage:
#   ./server-stats.sh [--top N] [--no-color] [--help]
#
# Works on any Linux box with bash, coreutils and procps (standard on
# virtually every distro). No root required, though some login-audit stats
# are only readable as root.

set -uo pipefail

export LC_ALL=C

TOP_N=5
CPU_SAMPLE=1
USE_COLOR=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --top N       Show N processes per list (default: 5)
  --no-color    Disable ANSI colors
  -h, --help    Show this help

Environment:
  CPU_SAMPLE    Seconds to sample CPU usage (default: 1)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --top)
            if [ $# -lt 2 ]; then
                echo "Error: --top requires a value" >&2
                exit 2
            fi
            TOP_N="$2"
            shift 2
            ;;
        --top=*)    TOP_N="${1#*=}"; shift ;;
        --no-color) USE_COLOR=0; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$TOP_N" in
    ''|*[!0-9]*) echo "Error: --top expects a positive integer" >&2; exit 2 ;;
esac
[ "$TOP_N" -ge 1 ] || { echo "Error: --top expects a positive integer" >&2; exit 2; }

# ---------------------------------------------------------------- presentation

if [ "$USE_COLOR" -eq 1 ] && [ -t 1 ]; then
    BOLD=$'\e[1m'; DIM=$'\e[2m'
    RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
    BLUE=$'\e[34m'; CYAN=$'\e[36m'; RESET=$'\e[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

header() {
    printf '\n%s%s%s\n' "$BOLD$CYAN" "$1" "$RESET"
    printf '%s\n' "${DIM}------------------------------------------------------------${RESET}"
}

kv() {
    printf '  %-18s %s\n' "$1" "$2"
}

pct_color() {
    awk -v p="$1" 'BEGIN {
        if (p >= 90) print "red";
        else if (p >= 75) print "yellow";
        else print "green";
    }'
}

# pct_ansi <percent> : ANSI color code for a usage percentage
pct_ansi() {
    case "$(pct_color "$1")" in
        red)    printf '%s' "$RED" ;;
        yellow) printf '%s' "$YELLOW" ;;
        *)      printf '%s' "$GREEN" ;;
    esac
}

# bar <percent> : 30 char usage bar
bar() {
    awk -v p="$1" -v w=30 'BEGIN {
        n = int((p / 100) * w + 0.5);
        if (n > w) n = w;
        if (n < 0) n = 0;
        s = "";
        for (i = 0; i < n; i++) s = s "#";
        for (i = n; i < w; i++) s = s "-";
        printf "[%s]", s;
    }'
}

# usage_line <label> <used> <total> <free> <percent>
usage_line() {
    local label="$1" used="$2" total="$3" free="$4" pct="$5"
    printf '  %-10s %8s / %-8s %s %s%6s%%%s  free: %s\n' \
        "$label" "$used" "$total" "$(bar "$pct")" \
        "$(pct_ansi "$pct")" "$pct" "$RESET" "$free"
}

# ---------------------------------------------------------------- helpers

have() { command -v "$1" >/dev/null 2>&1; }

trim_pct() { printf '%s' "${1%\%}"; }

fmt_kb() {
    awk -v kb="$1" 'BEGIN {
        split("KiB MiB GiB TiB PiB", u, " ");
        i = 1;
        while (kb >= 1024 && i < 5) { kb /= 1024; i++ }
        if (i == 1) printf "%d %s", kb, u[i];
        else printf "%.1f %s", kb, u[i];
    }'
}

# ---------------------------------------------------------------- preflight

if [ ! -r /proc/stat ] || [ ! -r /proc/meminfo ]; then
    echo "Error: /proc/stat and /proc/meminfo are required." >&2
    echo "This script targets Linux; it cannot run on $(uname -s)." >&2
    exit 1
fi

if [ "$(uname -s)" != "Linux" ]; then
    echo "Error: this script requires Linux." >&2
    exit 1
fi

# ---------------------------------------------------------------- system info

print_system_info() {
    header "SYSTEM"

    local os_name="Unknown" kernel arch host uptime_str
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        os_name=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-${NAME:-Unknown} ${VERSION:-}}")
    elif [ -r /etc/lsb-release ]; then
        # shellcheck disable=SC1091
        os_name=$(. /etc/lsb-release 2>/dev/null && printf '%s' "${DISTRIB_DESCRIPTION:-Unknown}")
    fi

    kernel="$(uname -r)"
    arch="$(uname -m)"
    host="$(uname -n)"

    if have uptime; then
        uptime_str="$(uptime -p 2>/dev/null)"
        [ -n "$uptime_str" ] || uptime_str="$(uptime | sed 's/.*up //; s/,[[:space:]]*[0-9]* users.*//')"
    else
        uptime_str="$(awk '{ d = int($1 / 86400); h = int(($1 % 86400) / 3600); m = int(($1 % 3600) / 60);
            out = ""; if (d) out = out d " days "; if (h) out = out h " hours "; out = out m " minutes";
            printf "up %s", out }' /proc/uptime)"
    fi

    local proc_count
    proc_count=$(ps -e --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${proc_count:-0}" -eq 0 ]; then
        proc_count=$(ps -e 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    fi

    kv "Hostname"      "$host"
    kv "OS"            "$os_name"
    kv "Kernel"        "$kernel ($arch)"
    kv "Uptime"        "$uptime_str"
    kv "Load average"  "$(cat /proc/loadavg | awk '{ printf "%s, %s, %s", $1, $2, $3 }')"
    kv "CPU cores"     "$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')"
    kv "Processes"     "$proc_count"
    kv "Current time"  "$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

# ---------------------------------------------------------------- CPU

print_cpu() {
    header "CPU USAGE"

    local t1 i1 t2 i2 dt di pct cores load
    read -r t1 i1 < <(awk '/^cpu /{ total = 0; for (i = 2; i <= NF; i++) total += $i; idle = $5 + $6; print total, idle; exit }' /proc/stat)

    sleep "$CPU_SAMPLE"

    read -r t2 i2 < <(awk '/^cpu /{ total = 0; for (i = 2; i <= NF; i++) total += $i; idle = $5 + $6; print total, idle; exit }' /proc/stat)

    dt=$((t2 - t1))
    di=$((i2 - i1))

    if [ "$dt" -le 0 ]; then
        echo "  Unable to sample CPU usage."
        return
    fi

    pct=$(awk -v dt="$dt" -v di="$di" 'BEGIN { printf "%.1f", (dt - di) * 100 / dt }')
    cores=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    load=$(awk '{ printf "%s %s %s", $1, $2, $3 }' /proc/loadavg)

    printf '  %-10s %s %s%6s%%%s   (sampled over %ss)\n' \
        "Total" "$(bar "$pct")" "$(pct_ansi "$pct")" "$pct" "$RESET" "$CPU_SAMPLE"
    kv "Cores"        "$cores"
    kv "Load average" "$load  (1, 5, 15 min)"
}

# ---------------------------------------------------------------- memory

print_memory() {
    header "MEMORY USAGE"

    local total_kb avail_kb used_kb pct
    read -r total_kb avail_kb < <(awk '
        /^MemTotal:/     { t = $2 }
        /^MemAvailable:/ { a = $2 }
        /^MemFree:/      { f = $2 }
        /^Buffers:/      { b = $2 }
        /^Cached:/       { c = $2 }
        END {
            if (a == "" || a == 0) a = f + b + c;
            printf "%d %d", t, a;
        }' /proc/meminfo)

    if [ "${total_kb:-0}" -le 0 ]; then
        echo "  Unable to read memory information."
        return
    fi

    used_kb=$((total_kb - avail_kb))
    pct=$(awk -v t="$total_kb" -v u="$used_kb" 'BEGIN { printf "%.1f", u * 100 / t }')

    usage_line "Memory" "$(fmt_kb "$used_kb")" "$(fmt_kb "$total_kb")" "$(fmt_kb "$avail_kb")" "$pct"

    local swap_total swap_free swap_used swap_pct
    read -r swap_total swap_free < <(awk '/^SwapTotal:/{t=$2} /^SwapFree:/{f=$2} END{printf "%d %d", t, f}' /proc/meminfo)
    if [ "${swap_total:-0}" -gt 0 ]; then
        swap_used=$((swap_total - swap_free))
        swap_pct=$(awk -v t="$swap_total" -v u="$swap_used" 'BEGIN { printf "%.1f", u * 100 / t }')
        usage_line "Swap" "$(fmt_kb "$swap_used")" "$(fmt_kb "$swap_total")" "$(fmt_kb "$swap_free")" "$swap_pct"
    else
        kv "Swap" "not configured"
    fi
}

# ---------------------------------------------------------------- disk

print_disk() {
    header "DISK USAGE (/)"

    local size used avail pct
    read -r size used avail pct < <(df -P / 2>/dev/null | awk 'NR == 2 {
        printf "%s %s %s %s", $2, $3, $4, $5
    }')

    if [ -z "${pct:-}" ]; then
        echo "  Unable to read disk usage."
        return
    fi

    usage_line "Root (/)" "$(fmt_kb "$used")" "$(fmt_kb "$size")" "$(fmt_kb "$avail")" "$(trim_pct "$pct")"
    kv "Filesystem"   "$(df -P / 2>/dev/null | awk 'NR == 2 { print $1 " -> " $6 }')"
    kv "Available"    "$(fmt_kb "$avail")"

    header "MOUNTED FILESYSTEMS"
    printf '  %-24s %-8s %-8s %-8s %-6s %s\n' "FILESYSTEM" "SIZE" "USED" "AVAIL" "USE%" "MOUNTED ON"
    if df -Ph -x tmpfs -x devtmpfs -x squashfs -x overlay >/dev/null 2>&1; then
        df -Ph -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR > 1 {
            printf "  %-24s %-8s %-8s %-8s %-6s %s\n", substr($1, 1, 24), $2, $3, $4, $5, $6
        }' | head -n 12
    else
        df -Ph 2>/dev/null | awk 'NR > 1 {
            printf "  %-24s %-8s %-8s %-8s %-6s %s\n", substr($1, 1, 24), $2, $3, $4, $5, $6
        }' | head -n 12
    fi
}

# ---------------------------------------------------------------- processes

print_processes() {
    local sort_by="$1" title="$2"

    header "$title"

    if ps -e -ww -o pid,user,pcpu,pmem,args --sort=-"$sort_by" >/dev/null 2>&1; then
        ps -e -ww -o pid,user,pcpu,pmem,args --sort=-"$sort_by" 2>/dev/null |
        awk -v n="$TOP_N" '
            NR == 1 {
                printf "  %-7s %-10s %6s %6s  %s\n", "PID", "USER", "%CPU", "%MEM", "COMMAND";
                next
            }
            NR <= n + 1 {
                cmd = "";
                for (i = 5; i <= NF; i++) cmd = cmd (i > 5 ? " " : "") $i;
                if (length(cmd) > 44) cmd = substr(cmd, 1, 43) "...";
                printf "  %-7s %-10s %6s %6s  %s\n", $1, substr($2, 1, 10), $3, $4, cmd;
            }'
    else
        # Fallback for busybox / older ps implementations
        ps aux 2>/dev/null |
        awk -v n="$TOP_N" -v key="$([ "$sort_by" = "pcpu" ] && echo 3 || echo 4)" '
            NR == 1 {
                printf "  %-7s %-10s %6s %6s  %s\n", "PID", "USER", "%CPU", "%MEM", "COMMAND";
                next
            }
            { print key "\t" $0 }' |
        sort -t"$(printf '\t')" -k1,1nr |
        cut -f2- |
        head -n "$TOP_N" |
        awk '{ printf "  %-7s %-10s %6s %6s  %s\n", $2, substr($1, 1, 10), $3, $4, substr($11, 1, 44) }'
    fi
}

# ---------------------------------------------------------------- logins

print_users() {
    header "LOGGED IN USERS"

    local count
    count=$(who 2>/dev/null | wc -l | tr -d ' ')

    kv "User count" "$count"
    if [ "$count" -gt 0 ]; then
        printf '  %-10s %-10s %-20s %s\n' "USER" "TTY" "LOGIN TIME" "FROM"
        who 2>/dev/null | head -n 10 | awk '{
            login = $3 " " $4;
            from = (NF >= 5) ? $5 : "-";
            printf "  %-10s %-10s %-20s %s\n", $1, $2, login, from;
        }'
    fi
}

print_failed_logins() {
    header "FAILED LOGIN ATTEMPTS"

    local count="" source=""

    if [ -r /var/log/auth.log ]; then
        count=$(grep -c "Failed password" /var/log/auth.log 2>/dev/null)
        source="/var/log/auth.log"
    elif [ -r /var/log/secure ]; then
        count=$(grep -c "Failed password" /var/log/secure 2>/dev/null)
        source="/var/log/secure"
    fi

    if [ -z "$source" ] && have journalctl; then
        count=$(journalctl -u sshd -u ssh --since "-7 days" --no-pager 2>/dev/null |
                grep -c "Failed password")
        [ "${count:-0}" -gt 0 ] 2>/dev/null && source="journald (sshd, last 7 days)"
    fi

    if [ -z "$source" ] && [ -r /var/log/btmp ] && have lastb; then
        count=$(lastb -n 1000 2>/dev/null | grep -c .)
        [ "${count:-0}" -gt 0 ] 2>/dev/null && source="/var/log/btmp (lastb)"
    fi

    if [ -n "$source" ]; then
        kv "Failed attempts" "${count:-0}   ${DIM}(${source})${RESET}"
    else
        kv "Failed attempts" "unavailable (no readable auth log; try running as root)"
    fi
}

# ---------------------------------------------------------------- main

main() {
    printf '%s\n' "${BOLD}=============== SERVER PERFORMANCE STATS ===============${RESET}"
    print_system_info
    print_cpu
    print_memory
    print_disk
    print_processes pcpu  "TOP $TOP_N PROCESSES BY CPU USAGE"
    print_processes pmem  "TOP $TOP_N PROCESSES BY MEMORY USAGE"
    print_users
    print_failed_logins
    printf '\n%s\n' "${DIM}Report generated $(date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"
}

main "$@"
