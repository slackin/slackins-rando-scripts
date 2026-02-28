#!/bin/bash
# ==============================================================================
# slack-therm-setup.sh — Interactive configuration wizard for slack-therm.sh
#
# Discovers hwmon devices and their sensors from /sys/class/hwmon, shows
# human-readable names and live readings, and walks you through building
# a slack-therm.conf file.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/slack-therm.conf"

# ──── Colors ─────────────────────────────────────────────────────────────────
B='\033[1m'
R='\033[0m'
CG='\033[1;32m'
CY='\033[1;33m'
CR='\033[1;31m'
CB='\033[1;34m'
CC='\033[1;36m'
DIM='\033[2m'

# ──── Helpers ────────────────────────────────────────────────────────────────

banner() {
    echo ""
    echo -e "${CC}╔══════════════════════════════════════════════════════════════╗${R}"
    echo -e "${CC}║${B}       slack-therm Configuration Wizard                      ${CC}║${R}"
    echo -e "${CC}╚══════════════════════════════════════════════════════════════╝${R}"
    echo ""
}

section() {
    echo ""
    echo -e "${CB}── $1 $( printf '─%.0s' $(seq 1 $(( 58 - ${#1} )) ) )${R}"
    echo ""
}

info()  { echo -e "  ${CG}✓${R} $*"; }
warn()  { echo -e "  ${CY}!${R} $*"; }
err()   { echo -e "  ${CR}✗${R} $*"; }

prompt_default() {
    # Usage: prompt_default "Prompt text" DEFAULT_VALUE
    # Sets REPLY to the entered value or the default.
    local prompt="$1" default="$2"
    read -rp "  ${prompt} [${default}]: " REPLY
    REPLY="${REPLY:-$default}"
}

prompt_yes_no() {
    # Usage: prompt_yes_no "Question?" [y|n]   — returns 0 for yes, 1 for no
    local prompt="$1" default="${2:-y}"
    local hint="Y/n"; [[ "$default" == "n" ]] && hint="y/N"
    read -rp "  ${prompt} (${hint}): " REPLY
    REPLY="${REPLY:-$default}"
    [[ "${REPLY,,}" == y* ]]
}

# ──── Discover hwmon devices ─────────────────────────────────────────────────

declare -a HWMON_PATHS=()
declare -a HWMON_NAMES=()
declare -a HWMON_IDS=()

discover_hwmon() {
    section "Discovering hardware monitors"

    local i=0
    for hwpath in /sys/class/hwmon/hwmon*; do
        [[ -d "$hwpath" ]] || continue
        local id name
        id="$(basename "$hwpath")"
        name="$(cat "${hwpath}/name" 2>/dev/null || echo "(unknown)")"
        HWMON_PATHS+=("$hwpath")
        HWMON_IDS+=("$id")
        HWMON_NAMES+=("$name")
        (( i++ )) || true
    done

    if (( i == 0 )); then
        err "No hwmon devices found under /sys/class/hwmon."
        exit 1
    fi

    echo -e "  Found ${B}${i}${R} hardware monitor(s):"
    echo ""
    for (( j=0; j<${#HWMON_IDS[@]}; j++ )); do
        printf "    ${CG}%2d)${R}  %-10s  ${DIM}%s${R}  — driver: ${B}%s${R}\n" \
            "$((j+1))" "${HWMON_IDS[$j]}" "${HWMON_PATHS[$j]}" "${HWMON_NAMES[$j]}"
    done
    echo ""
}

# ──── Pick hwmon aliases ─────────────────────────────────────────────────────

declare -A ALIAS_MAP   # alias -> hwmonN

pick_hwmon_aliases() {
    section "Assign hardware monitor roles"

    echo -e "  You can assign friendly aliases (e.g. CPU_HWMON, MOBO_HWMON, NVME_HWMON)"
    echo -e "  to the discovered hwmon devices.  These aliases are used to build sensor paths."
    echo ""

    local more="y"
    while [[ "$more" == "y"* ]]; do
        read -rp "  Alias name (e.g. CPU_HWMON): " alias_name
        [[ -z "$alias_name" ]] && { warn "Skipped."; continue; }
        alias_name="${alias_name^^}"  # uppercase

        echo ""
        echo -e "  Which hwmon device should ${B}${alias_name}${R} point to?"
        for (( j=0; j<${#HWMON_IDS[@]}; j++ )); do
            printf "    ${CG}%2d)${R}  %-10s  —  ${B}%s${R}\n" \
                "$((j+1))" "${HWMON_IDS[$j]}" "${HWMON_NAMES[$j]}"
        done
        read -rp "  Enter number: " choice
        choice=$((choice - 1))
        if (( choice < 0 || choice >= ${#HWMON_IDS[@]} )); then
            err "Invalid selection."; continue
        fi
        ALIAS_MAP["$alias_name"]="${HWMON_IDS[$choice]}"
        info "${alias_name} → ${HWMON_IDS[$choice]} (${HWMON_NAMES[$choice]})"
        echo ""
        prompt_yes_no "Add another alias?" "y" && more="y" || more="n"
    done
}

# ──── List sensors for a given hwmon path ────────────────────────────────────

list_temp_sensors() {
    # Prints a numbered list of temp*_input files for $1 (hwmon path)
    local hwpath="$1" idx=0
    # Collect and sort sensor files
    for f in "${hwpath}"/temp*_input; do
        [[ -f "$f" ]] || continue
        local base fname label raw val
        fname="$(basename "$f")"
        base="${fname%_input}"                          # e.g. temp1
        label="$(cat "${hwpath}/${base}_label" 2>/dev/null || echo "")"
        raw="$(cat "$f" 2>/dev/null || echo 0)"
        val="$(( raw / 1000 ))"
        printf "    ${CG}%2d)${R}  %-14s  " "$((idx+1))" "$fname"
        [[ -n "$label" ]] && printf "label: ${B}%-16s${R}  " "$label" \
                          || printf "label: ${DIM}%-16s${R}  " "(none)"
        printf "current: ${CY}%d°C${R}\n" "$val"
        (( idx++ )) || true
    done
    return $idx   # return count via exit status (abusing it a bit)
}

list_fan_sensors() {
    local hwpath="$1" idx=0
    for f in "${hwpath}"/fan*_input; do
        [[ -f "$f" ]] || continue
        local base fname label raw
        fname="$(basename "$f")"
        base="${fname%_input}"
        label="$(cat "${hwpath}/${base}_label" 2>/dev/null || echo "")"
        raw="$(cat "$f" 2>/dev/null || echo 0)"
        printf "    ${CG}%2d)${R}  %-14s  " "$((idx+1))" "$fname"
        [[ -n "$label" ]] && printf "label: ${B}%-16s${R}  " "$label" \
                          || printf "label: ${DIM}%-16s${R}  " "(none)"
        printf "current: ${CY}%d RPM${R}\n" "$raw"
        (( idx++ )) || true
    done
    return $idx
}

# ──── Configure temperature sensors ─────────────────────────────────────────

declare -a CFG_TEMP_LOC=()
declare -a CFG_TEMP_DIV=()
declare -a CFG_TEMP_COOL=()
declare -a CFG_TEMP_WARM=()
declare -a CFG_TEMP_HOT=()
declare -a CFG_TEMP_DOWN=()
declare -a CFG_TEMP_UP=()
declare -a CFG_TEMP_LABEL=()
# Store whether the path uses an alias variable or a raw path
declare -a CFG_TEMP_PATH_EXPR=()

configure_temp_sensors() {
    section "Configure temperature sensors"

    echo -e "  For each hwmon device, you'll see the available temperature sensors"
    echo -e "  with their sysfs labels (if any) and current readings."
    echo -e "  Select the ones you want to monitor and set color/throttle thresholds."
    echo ""

    local tidx=0

    for (( h=0; h<${#HWMON_PATHS[@]}; h++ )); do
        local hwpath="${HWMON_PATHS[$h]}"
        local hwid="${HWMON_IDS[$h]}"
        local hwname="${HWMON_NAMES[$h]}"

        # Check if any temp sensors exist
        local has_temps=0
        for f in "${hwpath}"/temp*_input; do [[ -f "$f" ]] && has_temps=1 && break; done
        (( has_temps )) || continue

        echo -e "  ${B}${hwid}${R} — ${hwname}:"
        echo ""

        # Build parallel arrays of this device's temp sensors
        local -a dev_files=() dev_labels=() dev_vals=()
        for f in "${hwpath}"/temp*_input; do
            [[ -f "$f" ]] || continue
            local fname base label raw val
            fname="$(basename "$f")"
            base="${fname%_input}"
            label="$(cat "${hwpath}/${base}_label" 2>/dev/null || echo "")"
            raw="$(cat "$f" 2>/dev/null || echo 0)"
            val="$(( raw / 1000 ))"
            dev_files+=("$fname")
            dev_labels+=("$label")
            dev_vals+=("$val")
        done

        for (( s=0; s<${#dev_files[@]}; s++ )); do
            printf "    ${CG}%2d)${R}  %-14s  " "$((s+1))" "${dev_files[$s]}"
            [[ -n "${dev_labels[$s]}" ]] \
                && printf "label: ${B}%-16s${R}  " "${dev_labels[$s]}" \
                || printf "label: ${DIM}%-16s${R}  " "(none)"
            printf "current: ${CY}%d°C${R}\n" "${dev_vals[$s]}"
        done
        echo ""

        if ! prompt_yes_no "Add temperature sensors from ${hwid} (${hwname})?" "y"; then
            echo ""; continue
        fi

        echo ""
        echo -e "  Enter sensor numbers to add (space-separated), or ${B}all${R}:"
        read -rp "  > " selection

        local -a picks=()
        if [[ "${selection,,}" == "all" ]]; then
            for (( s=0; s<${#dev_files[@]}; s++ )); do picks+=("$s"); done
        else
            for num in $selection; do
                if (( num >= 1 && num <= ${#dev_files[@]} )); then
                    picks+=("$(( num - 1 ))")
                fi
            done
        fi

        # Determine if there's an alias pointing to this hwmon
        local alias_var=""
        for akey in "${!ALIAS_MAP[@]}"; do
            if [[ "${ALIAS_MAP[$akey]}" == "$hwid" ]]; then
                alias_var="$akey"
                break
            fi
        done

        for pidx in "${picks[@]}"; do
            local fname="${dev_files[$pidx]}"
            local base="${fname%_input}"
            local label="${dev_labels[$pidx]}"
            local cur_val="${dev_vals[$pidx]}"

            echo ""
            echo -e "  ${B}── Sensor: ${fname}${R}"
            [[ -n "$label" ]] && echo -e "     sysfs label: ${CG}${label}${R}"
            echo -e "     current reading: ${CY}${cur_val}°C${R}"

            # Build path expression
            local path_expr
            if [[ -n "$alias_var" ]]; then
                path_expr="/sys/class/hwmon/\${${alias_var}}/${fname}"
            else
                path_expr="${hwpath}/${fname}"
            fi

            # Display label — prefer sysfs label, let user override
            local default_label="${label:-${base}}"
            prompt_default "Display label" "$default_label"
            local display_label="$REPLY"

            # Thresholds — offer sensible defaults based on current reading
            local def_cool=$(( cur_val + 10 ))
            local def_warm=$(( cur_val + 20 ))
            local def_hot=$(( cur_val + 30 ))
            # Clamp to reasonable maximums
            (( def_cool > 85 )) && def_cool=55
            (( def_warm > 90 )) && def_warm=65
            (( def_hot  > 95 )) && def_hot=75

            prompt_default "Cool threshold (blue ≤ this)" "$def_cool"
            local t_cool="$REPLY"
            prompt_default "Warm threshold (green ≤ this)" "$def_warm"
            local t_warm="$REPLY"
            prompt_default "Hot  threshold (yellow ≤ this, above = red)" "$def_hot"
            local t_hot="$REPLY"

            # Throttle thresholds (optional)
            local t_down="" t_up=""
            if prompt_yes_no "Set throttle thresholds for this sensor?" "n"; then
                prompt_default "Throttle-down temp (reduce cooling below this)" "$(( t_hot + 5 ))"
                t_down="$REPLY"
                prompt_default "Throttle-up temp (increase cooling above this)" "$(( t_warm ))"
                t_up="$REPLY"
            fi

            # Store
            CFG_TEMP_PATH_EXPR+=("$path_expr")
            CFG_TEMP_LOC+=("$path_expr")
            CFG_TEMP_DIV+=("1000")
            CFG_TEMP_COOL+=("$t_cool")
            CFG_TEMP_WARM+=("$t_warm")
            CFG_TEMP_HOT+=("$t_hot")
            CFG_TEMP_DOWN+=("$t_down")
            CFG_TEMP_UP+=("$t_up")
            CFG_TEMP_LABEL+=("$display_label")

            info "Added: [${tidx}] ${display_label} → ${path_expr}"
            (( tidx++ )) || true
        done
        echo ""
    done

    if (( tidx == 0 )); then
        warn "No temperature sensors configured."
    else
        info "Total temperature sensors configured: ${tidx}"
    fi
}

# ──── Configure fan sensors ──────────────────────────────────────────────────

declare -a CFG_FAN_LOC=()
declare -a CFG_FAN_LOW=()
declare -a CFG_FAN_HIGH=()
declare -a CFG_FAN_LABEL=()
declare -a CFG_FAN_PATH_EXPR=()

configure_fan_sensors() {
    section "Configure fan sensors"

    echo -e "  Select which fan inputs to monitor and set RPM thresholds."
    echo ""

    local fidx=0

    for (( h=0; h<${#HWMON_PATHS[@]}; h++ )); do
        local hwpath="${HWMON_PATHS[$h]}"
        local hwid="${HWMON_IDS[$h]}"
        local hwname="${HWMON_NAMES[$h]}"

        local has_fans=0
        for f in "${hwpath}"/fan*_input; do [[ -f "$f" ]] && has_fans=1 && break; done
        (( has_fans )) || continue

        echo -e "  ${B}${hwid}${R} — ${hwname}:"
        echo ""

        local -a dev_files=() dev_labels=() dev_vals=()
        for f in "${hwpath}"/fan*_input; do
            [[ -f "$f" ]] || continue
            local fname base label raw
            fname="$(basename "$f")"
            base="${fname%_input}"
            label="$(cat "${hwpath}/${base}_label" 2>/dev/null || echo "")"
            raw="$(cat "$f" 2>/dev/null || echo 0)"
            dev_files+=("$fname")
            dev_labels+=("$label")
            dev_vals+=("$raw")
        done

        for (( s=0; s<${#dev_files[@]}; s++ )); do
            printf "    ${CG}%2d)${R}  %-14s  " "$((s+1))" "${dev_files[$s]}"
            [[ -n "${dev_labels[$s]}" ]] \
                && printf "label: ${B}%-16s${R}  " "${dev_labels[$s]}" \
                || printf "label: ${DIM}%-16s${R}  " "(none)"
            printf "current: ${CY}%d RPM${R}\n" "${dev_vals[$s]}"
        done
        echo ""

        if ! prompt_yes_no "Add fan sensors from ${hwid} (${hwname})?" "y"; then
            echo ""; continue
        fi

        echo ""
        echo -e "  Enter sensor numbers to add (space-separated), or ${B}all${R}:"
        read -rp "  > " selection

        local -a picks=()
        if [[ "${selection,,}" == "all" ]]; then
            for (( s=0; s<${#dev_files[@]}; s++ )); do picks+=("$s"); done
        else
            for num in $selection; do
                if (( num >= 1 && num <= ${#dev_files[@]} )); then
                    picks+=("$(( num - 1 ))")
                fi
            done
        fi

        # Alias lookup
        local alias_var=""
        for akey in "${!ALIAS_MAP[@]}"; do
            if [[ "${ALIAS_MAP[$akey]}" == "$hwid" ]]; then
                alias_var="$akey"
                break
            fi
        done

        for pidx in "${picks[@]}"; do
            local fname="${dev_files[$pidx]}"
            local base="${fname%_input}"
            local label="${dev_labels[$pidx]}"
            local cur_rpm="${dev_vals[$pidx]}"

            echo ""
            echo -e "  ${B}── Fan: ${fname}${R}"
            [[ -n "$label" ]] && echo -e "     sysfs label: ${CG}${label}${R}"
            echo -e "     current reading: ${CY}${cur_rpm} RPM${R}"

            local path_expr
            if [[ -n "$alias_var" ]]; then
                path_expr="/sys/class/hwmon/\${${alias_var}}/${fname}"
            else
                path_expr="${hwpath}/${fname}"
            fi

            local default_label="${label:-${base}}"
            prompt_default "Display label" "$default_label"
            local display_label="$REPLY"

            prompt_default "Low RPM threshold (at or below = red)" "500"
            local f_low="$REPLY"
            prompt_default "High RPM threshold (at or above = red)" "2000"
            local f_high="$REPLY"

            CFG_FAN_PATH_EXPR+=("$path_expr")
            CFG_FAN_LOC+=("$path_expr")
            CFG_FAN_LOW+=("$f_low")
            CFG_FAN_HIGH+=("$f_high")
            CFG_FAN_LABEL+=("$display_label")

            info "Added: [${fidx}] ${display_label} → ${path_expr}"
            (( fidx++ )) || true
        done
        echo ""
    done

    if (( fidx == 0 )); then
        warn "No fan sensors configured."
    else
        info "Total fan sensors configured: ${fidx}"
    fi
}

# ──── Configure general settings ─────────────────────────────────────────────

CFG_SLEEP_TIME=""
CFG_FREQ_LOW=""
CFG_FREQ_MID=""
CFG_FREQ_HIGH=""
CFG_FREQ_RAW_DIV=""

configure_general() {
    section "General settings"

    prompt_default "Dashboard refresh interval (seconds)" "3"
    CFG_SLEEP_TIME="$REPLY"

    section "CPU frequency color thresholds (MHz)"
    echo -e "  These control the bar colors for per-core frequency display."

    prompt_default "Low  (blue  ≤ this MHz)" "2200"
    CFG_FREQ_LOW="$REPLY"
    prompt_default "Mid  (green ≤ this MHz)" "3200"
    CFG_FREQ_MID="$REPLY"
    prompt_default "High (yellow ≤ this MHz, above = red)" "4000"
    CFG_FREQ_HIGH="$REPLY"

    prompt_default "Freq raw divisor (usually 1000)" "1000"
    CFG_FREQ_RAW_DIV="$REPLY"
}

# ──── Write config file ─────────────────────────────────────────────────────

write_config() {
    section "Writing configuration"

    local tmpfile
    tmpfile="$(mktemp)"

    cat > "$tmpfile" <<'HEADER'
# ==============================================================================
# slack-therm.conf — Configuration for slack-therm.sh
# Generated by slack-therm-setup.sh
#
# Edit manually or re-run slack-therm-setup.sh to reconfigure.
# ==============================================================================
HEADER

    # Aliases
    {
        echo ""
        echo "# ──── Hardware monitor aliases ─────────────────────────────────────────────"
        for akey in $(echo "${!ALIAS_MAP[@]}" | tr ' ' '\n' | sort); do
            echo "${akey}=\"${ALIAS_MAP[$akey]}\""
        done
    } >> "$tmpfile"

    # Temperature sensors
    {
        echo ""
        echo "# ──── Temperature sensors ────────────────────────────────────────────────────"
        for (( i=0; i<${#CFG_TEMP_LOC[@]}; i++ )); do
            echo ""
            echo "TEMP_RAW_LOC[${i}]=\"${CFG_TEMP_LOC[$i]}\""
            echo "TEMP_RAW_DIV[${i}]=\"${CFG_TEMP_DIV[$i]}\""
            echo "TEMP_COOL[${i}]=\"${CFG_TEMP_COOL[$i]}\""
            echo "TEMP_WARM[${i}]=\"${CFG_TEMP_WARM[$i]}\""
            echo "TEMP_HOT[${i}]=\"${CFG_TEMP_HOT[$i]}\""
            [[ -n "${CFG_TEMP_DOWN[$i]}" ]] && echo "TEMP_DOWN[${i}]=\"${CFG_TEMP_DOWN[$i]}\""
            [[ -n "${CFG_TEMP_UP[$i]}" ]]   && echo "TEMP_UP[${i}]=\"${CFG_TEMP_UP[$i]}\""
            echo "TEMP_LABEL[${i}]=\"${CFG_TEMP_LABEL[$i]}\""
        done
    } >> "$tmpfile"

    # Fan sensors
    {
        echo ""
        echo "# ──── Fan sensors ────────────────────────────────────────────────────────────"
        for (( i=0; i<${#CFG_FAN_LOC[@]}; i++ )); do
            echo ""
            echo "FAN_RAW_LOC[${i}]=\"${CFG_FAN_LOC[$i]}\""
            echo "FAN_LOW[${i}]=\"${CFG_FAN_LOW[$i]}\""
            echo "FAN_HIGH[${i}]=\"${CFG_FAN_HIGH[$i]}\""
            echo "FAN_LABEL[${i}]=\"${CFG_FAN_LABEL[$i]}\""
        done
    } >> "$tmpfile"

    # General settings
    {
        echo ""
        echo "# ──── Refresh interval ───────────────────────────────────────────────────────"
        echo "SLEEP_TIME=${CFG_SLEEP_TIME}"
        echo ""
        echo "# ──── CPU frequency color thresholds (MHz) ───────────────────────────────────"
        echo "FREQ_LOW=\"${CFG_FREQ_LOW}\""
        echo "FREQ_MID=\"${CFG_FREQ_MID}\""
        echo "FREQ_HIGH=\"${CFG_FREQ_HIGH}\""
        echo ""
        echo "# ──── CPU frequency raw divisor ──────────────────────────────────────────────"
        echo "FREQ_RAW_DIV=\"${CFG_FREQ_RAW_DIV}\""
    } >> "$tmpfile"

    # Back up existing config if present
    if [[ -f "$CONF_FILE" ]]; then
        local backup="${CONF_FILE}.bak.$(date '+%Y%m%d%H%M%S')"
        cp "$CONF_FILE" "$backup"
        info "Existing config backed up to: ${backup}"
    fi

    mv "$tmpfile" "$CONF_FILE"
    info "Configuration written to: ${CONF_FILE}"
}

# ──── Summary ────────────────────────────────────────────────────────────────

print_summary() {
    section "Configuration summary"

    echo -e "  ${B}Aliases:${R}"
    for akey in $(echo "${!ALIAS_MAP[@]}" | tr ' ' '\n' | sort); do
        echo -e "    ${akey} = ${ALIAS_MAP[$akey]}"
    done

    echo ""
    echo -e "  ${B}Temperature sensors:${R} ${#CFG_TEMP_LOC[@]}"
    for (( i=0; i<${#CFG_TEMP_LOC[@]}; i++ )); do
        echo -e "    [${i}] ${CFG_TEMP_LABEL[$i]}  cool≤${CFG_TEMP_COOL[$i]}  warm≤${CFG_TEMP_WARM[$i]}  hot≤${CFG_TEMP_HOT[$i]}"
    done

    echo ""
    echo -e "  ${B}Fan sensors:${R} ${#CFG_FAN_LOC[@]}"
    for (( i=0; i<${#CFG_FAN_LOC[@]}; i++ )); do
        echo -e "    [${i}] ${CFG_FAN_LABEL[$i]}  low≤${CFG_FAN_LOW[$i]}  high≤${CFG_FAN_HIGH[$i]}"
    done

    echo ""
    echo -e "  ${B}Refresh:${R} ${CFG_SLEEP_TIME}s"
    echo -e "  ${B}Freq thresholds:${R} low=${CFG_FREQ_LOW} mid=${CFG_FREQ_MID} high=${CFG_FREQ_HIGH} MHz"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════════════════

banner
discover_hwmon
pick_hwmon_aliases
configure_temp_sensors
configure_fan_sensors
configure_general
print_summary

if prompt_yes_no "Write this configuration to ${CONF_FILE}?" "y"; then
    write_config
    echo ""
    info "Done!  Run ${B}slack-therm.sh${R} to start the monitor."
else
    warn "Configuration discarded."
fi

echo ""
