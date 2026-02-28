#!/bin/bash
# ==============================================================================
# slack-therm.sh — ncurses-style system thermal / fan / CPU frequency monitor
# Uses tput (terminfo) for cursor addressing, color, and box-drawing.
# Press 'q' or Ctrl-C to exit cleanly.
# ==============================================================================

# ──── Load configuration ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/slack-therm.conf"

if [[ ! -f "$CONF_FILE" ]]; then
	echo "ERROR: Configuration file not found: ${CONF_FILE}"
	echo "Run slack-therm-setup.sh to create one, or copy the example config."
	exit 1
fi

# shellcheck source=slack-therm.conf
source "$CONF_FILE"

# ──── Unicode box-drawing characters ─────────────────────────────────────────
BOX_TL="┌"
BOX_TR="┐"
BOX_BL="└"
BOX_BR="┘"
BOX_H="─"
BOX_V="│"
BOX_LT="├"
BOX_RT="┤"

# ──── tput color helpers ─────────────────────────────────────────────────────
C_RESET="$(tput sgr0)"
C_BOLD="$(tput bold)"
C_BLUE="${C_BOLD}$(tput setaf 4)"
C_GREEN="${C_BOLD}$(tput setaf 2)"
C_YELLOW="${C_BOLD}$(tput setaf 3)"
C_RED="${C_BOLD}$(tput setaf 1)"
C_WHITE="${C_BOLD}$(tput setaf 7)"
C_CYAN="${C_BOLD}$(tput setaf 6)"
C_DIM="$(tput dim)"

# ──── Terminal state management ──────────────────────────────────────────────
PANEL_WIDTH=68

function cleanup() {
	tput cnorm          # restore cursor
	tput rmcup          # restore saved screen
	tput sgr0           # reset attributes
	stty echo           # restore echo
	exit 0
}
trap cleanup EXIT INT TERM

tput smcup              # save screen & switch to alt buffer
tput civis              # hide cursor
stty -echo              # suppress keyboard echo

# ──── Detect CPU cores ───────────────────────────────────────────────────────
NUM_CORES=0
while [[ -e "/sys/devices/system/cpu/cpu${NUM_CORES}/cpufreq/scaling_cur_freq" ]]; do
	(( NUM_CORES++ ))
done

if (( NUM_CORES == 0 )); then
	echo "ERROR: No CPU frequency scaling info found."
	exit 1
fi

# Pairing: if >8 cores and even, pair first half with second half (HT/SMT siblings)
if (( NUM_CORES > 8 && NUM_CORES % 2 == 0 )); then
	HALF_CORES=$(( NUM_CORES / 2 ))
	PAIRED=1
	FREQ_ROWS=$HALF_CORES
else
	PAIRED=0
	FREQ_ROWS=$NUM_CORES
fi

# Dynamic layout offsets (rows relative to ORIGIN_R)
FREQ_START_OFF=10
STATUS_OFF=$(( FREQ_START_OFF + FREQ_ROWS + 2 ))
BOX_HEIGHT=$(( STATUS_OFF + 2 ))

# ──── Drawing primitives ─────────────────────────────────────────────────────

# draw_hline ROW COL WIDTH [CHAR]
function draw_hline() {
	local r=$1 c=$2 w=$3 ch="${4:-$BOX_H}"
	tput cup "$r" "$c"
	printf '%0.s'"$ch" $(seq 1 "$w")
}

# draw_box ROW COL WIDTH HEIGHT [TITLE]
function draw_box() {
	local r=$1 c=$2 w=$3 h=$4 title="$5"
	local inner=$((w - 2))

	# top border
	tput cup "$r" "$c"
	printf "${C_CYAN}%s" "$BOX_TL"
	printf '%0.s'"$BOX_H" $(seq 1 "$inner")
	printf "%s${C_RESET}" "$BOX_TR"

	# optional title
	if [[ -n "$title" ]]; then
		local tlen=${#title}
		local tpos=$(( c + (w - tlen - 2) / 2 ))
		tput cup "$r" "$tpos"
		printf "${C_CYAN}${BOX_H} ${C_WHITE}%s${C_CYAN} ${BOX_H}${C_RESET}" "$title"
	fi

	# sides
	for (( row = r + 1; row < r + h - 1; row++ )); do
		tput cup "$row" "$c"
		printf "${C_CYAN}%s${C_RESET}" "$BOX_V"
		tput cup "$row" $(( c + w - 1 ))
		printf "${C_CYAN}%s${C_RESET}" "$BOX_V"
	done

	# bottom border
	tput cup $(( r + h - 1 )) "$c"
	printf "${C_CYAN}%s" "$BOX_BL"
	printf '%0.s'"$BOX_H" $(seq 1 "$inner")
	printf "%s${C_RESET}" "$BOX_BR"
}

# draw_separator ROW COL WIDTH  — a mid-box horizontal rule
function draw_separator() {
	local r=$1 c=$2 w=$3
	local inner=$((w - 2))
	tput cup "$r" "$c"
	printf "${C_CYAN}%s" "$BOX_LT"
	printf '%0.s'"$BOX_H" $(seq 1 "$inner")
	printf "%s${C_RESET}" "$BOX_RT"
}

# mvprint ROW COL TEXT — print at position (text may contain tput escapes)
function mvprint() {
	tput cup "$1" "$2"
	shift 2
	printf "%b" "$@"
}

# clear_field ROW COL WIDTH — blank a field for overwriting
function clear_field() {
	tput cup "$1" "$2"
	printf "%-${3}s" ""
}

# ──── Color-value helpers (return via $CV_OUT) ───────────────────────────────
CV_OUT=""

function color_for_temp() {
	local val=$1 cool=$2 warm=$3 hot=$4
	if   (( val <= cool )); then CV_OUT="${C_BLUE}${val}°C${C_RESET}"
	elif (( val <= warm )); then CV_OUT="${C_GREEN}${val}°C${C_RESET}"
	elif (( val <= hot  )); then CV_OUT="${C_YELLOW}${val}°C${C_RESET}"
	else                         CV_OUT="${C_RED}${val}°C${C_RESET}"
	fi
}

function color_for_fan() {
	local val=$1 lo=$2 hi=$3
	if   (( val <= lo )); then CV_OUT="${C_RED}${val}${C_RESET}"
	elif (( val <= hi )); then CV_OUT="${C_GREEN}${val}${C_RESET}"
	else                       CV_OUT="${C_RED}${val}${C_RESET}"
	fi
}

function color_for_freq() {
	local val=$1
	local fval
	printf -v fval '%4d' "$val"
	if   (( val <= FREQ_LOW  )); then CV_OUT="${C_BLUE}${fval}${C_RESET}"
	elif (( val <= FREQ_MID  )); then CV_OUT="${C_GREEN}${fval}${C_RESET}"
	elif (( val <= FREQ_HIGH )); then CV_OUT="${C_YELLOW}${fval}${C_RESET}"
	else                              CV_OUT="${C_RED}${fval}${C_RESET}"
	fi
}

function color_for_gov() {
	local gov="$1"
	case "$gov" in
		ondemand)     CV_OUT="${C_GREEN}${gov}${C_RESET}" ;;
		performance)  CV_OUT="${C_RED}${gov}${C_RESET}" ;;
		powersave)    CV_OUT="${C_BLUE}${gov}${C_RESET}" ;;
		userspace|conservative) CV_OUT="${C_YELLOW}${gov}${C_RESET}" ;;
		*)            CV_OUT="${C_WHITE}${gov}${C_RESET}" ;;
	esac
}

function color_for_state() {
	local st=$1
	case $st in
		0) CV_OUT="${C_GREEN}${st}${C_RESET}" ;;
		1) CV_OUT="${C_YELLOW}${st}${C_RESET}" ;;
		*) CV_OUT="${C_RED}${st}${C_RESET}" ;;
	esac
}

# ──── Throttle / cooling logic (unchanged from original) ─────────────────────
core="0"
ThorCount="0"
ThorReset="0"

function GetCoolingState() {
	local coolcore=$1
	THERM_STATE[${coolcore}]=$(cat ./${coolcore}cur_state_text.core 2>/dev/null || echo 0)
}

function GetSpeed() {
	local idx=$1
	GetCoolingState ${idx}
	if (( TEMP_REAL[idx] <= TEMP_UP[idx] )); then
		if (( THERM_STATE[idx] > 0 )); then
			SPEED=$(( THERM_STATE[idx] - 1 )); return
		fi
	fi
	if (( TEMP_REAL[idx] <= TEMP_DOWN[idx] && TEMP_REAL[idx] > TEMP_UP[idx] )); then
		SPEED=${THERM_STATE[$idx]}; return
	fi
	if (( TEMP_REAL[idx] > TEMP_DOWN[idx] )); then
		if (( THERM_STATE[idx] <= 3 )); then
			SPEED=$(( THERM_STATE[idx] + 1 )); return
		fi
	fi
	SPEED=0
}

function CheckSpeed() {
	local cores=$1
	if (( SPEED < THERM_STATE[cores] && THERM_STATE[cores] != 0 )); then
		local NEW_STATE=$(( THERM_STATE[cores] - 1 ))
		ThorCores ${NEW_STATE} ${cores}
		echo ${NEW_STATE} > ./${cores}cur_state_text.core
		if (( cores != 0 && NEW_STATE == 0 )); then
			cores=$(( cores - 1 ))
		fi
		return
	fi
	if (( SPEED > THERM_STATE[cores] && THERM_STATE[cores] != 4 )); then
		local NEW_STATE=$(( THERM_STATE[cores] + 1 ))
		if (( NEW_STATE == 4 && cores != 4 )); then
			cores=$(( cores + 1 ))
			NEW_STATE=1
		fi
		ThorCores ${NEW_STATE} ${cores}
		echo ${NEW_STATE} > ./${cores}cur_state_text.core
		return
	fi
}

function ThorCores() {
	case $1 in
		0) echo 1 > /sys/devices/system/cpu/cpufreq/boost ;;
		1) echo 3600000 > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq
		   echo 0 > /sys/devices/system/cpu/cpufreq/boost ;;
		2) echo 2800000 > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq ;;
		3) echo 2200000 > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq ;;
		*) echo 2200000 > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq ;;
	esac
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN LOOP
# ══════════════════════════════════════════════════════════════════════════════

# Layout constants — all relative to origin (1,1) leaving a 1-cell margin
ORIGIN_R=1
ORIGIN_C=2

first_draw=1

while true; do
	# ── Detect terminal size and centre the panel ──
	TERM_ROWS=$(tput lines)
	TERM_COLS=$(tput cols)
	ORIGIN_R=$(( (TERM_ROWS - BOX_HEIGHT) / 2 ))
	ORIGIN_C=$(( (TERM_COLS - PANEL_WIDTH) / 2 ))
	(( ORIGIN_R < 0 )) && ORIGIN_R=0
	(( ORIGIN_C < 0 )) && ORIGIN_C=0

	# ── Outer box (drawn once, or on resize) ──
	if (( first_draw )); then
		tput clear
		draw_box $ORIGIN_R $ORIGIN_C $PANEL_WIDTH $BOX_HEIGHT "System Monitor"

		# Section headers
		row=$(( ORIGIN_R + 1 ))
		draw_separator $(( ORIGIN_R + 3 )) $ORIGIN_C $PANEL_WIDTH
		mvprint $(( ORIGIN_R + 1 )) $(( ORIGIN_C + 2 )) "${C_WHITE} CPU / Board Temps${C_RESET}"
		draw_separator $(( ORIGIN_R + 5 )) $ORIGIN_C $PANEL_WIDTH
		mvprint $(( ORIGIN_R + 4 )) $(( ORIGIN_C + 2 )) "${C_WHITE} NVMe Temps${C_RESET}"
		draw_separator $(( ORIGIN_R + 7 )) $ORIGIN_C $PANEL_WIDTH
		mvprint $(( ORIGIN_R + 6 )) $(( ORIGIN_C + 2 )) "${C_WHITE} Fan Speeds  ${C_DIM}(RPM)${C_RESET}"
		draw_separator $(( ORIGIN_R + 9 )) $ORIGIN_C $PANEL_WIDTH
		mvprint $(( ORIGIN_R + 8 )) $(( ORIGIN_C + 2 )) "${C_WHITE} CPU Freq / Governor${C_RESET}"

		# Footer
		mvprint $(( ORIGIN_R + BOX_HEIGHT )) $(( ORIGIN_C )) \
			"${C_DIM}  Press 'q' to quit  │  Refresh: ${SLEEP_TIME}s${C_RESET}"
		first_draw=0
	fi

	# ──────────── Gather & display: CPU / Board temps ────────────
	ROW=$(( ORIGIN_R + 2 ))
	COL=$(( ORIGIN_C + 3 ))
	clear_field $ROW $COL $(( PANEL_WIDTH - 4 ))
	tput cup $ROW $COL
	for i in {0..3}; do
		[[ -z "${TEMP_RAW_LOC[$i]}" ]] && break
		TEMP_RAW[$i]=$(cat "${TEMP_RAW_LOC[$i]}" 2>/dev/null || echo 0)
		TEMP_REAL[$i]=$(( TEMP_RAW[i] / TEMP_RAW_DIV[i] ))
		color_for_temp ${TEMP_REAL[$i]} ${TEMP_COOL[$i]} ${TEMP_WARM[$i]} ${TEMP_HOT[$i]}
		printf " ${C_WHITE}%-6s${C_RESET} %b " "${TEMP_LABEL[$i]}" "$CV_OUT"
		# Throttle logic for Core
		if [[ "${TEMP_LABEL[$i]}" == "Core" ]]; then
			GetSpeed $i
		fi
	done

	# ──────────── Gather & display: NVMe temps ───────────────────
	ROW=$(( ORIGIN_R + 4 + 1 ))
	COL=$(( ORIGIN_C + 3 ))
	clear_field $(( ORIGIN_R + 5 - 1 )) $COL $(( PANEL_WIDTH - 4 ))
	tput cup $(( ORIGIN_R + 5 - 1 )) $COL
	for i in {4..6}; do
		[[ -z "${TEMP_RAW_LOC[$i]}" ]] && break
		TEMP_RAW[$i]=$(cat "${TEMP_RAW_LOC[$i]}" 2>/dev/null || echo 0)
		TEMP_REAL[$i]=$(( TEMP_RAW[i] / TEMP_RAW_DIV[i] ))
		color_for_temp ${TEMP_REAL[$i]} ${TEMP_COOL[$i]} ${TEMP_WARM[$i]} ${TEMP_HOT[$i]}
		printf " ${C_WHITE}%-5s${C_RESET} %b " "${TEMP_LABEL[$i]}" "$CV_OUT"
	done

	# ──────────── Gather & display: Fan speeds ───────────────────
	ROW=$(( ORIGIN_R + 6 + 1 ))
	clear_field $(( ORIGIN_R + 7 - 1 )) $COL $(( PANEL_WIDTH - 4 ))
	tput cup $(( ORIGIN_R + 7 - 1 )) $COL
	for f in {0..7}; do
		[[ -z "${FAN_RAW_LOC[$f]}" ]] && break
		FAN_SPEED[$f]=$(cat "${FAN_RAW_LOC[$f]}" 2>/dev/null || echo 0)
		color_for_fan ${FAN_SPEED[$f]} ${FAN_LOW[$f]} ${FAN_HIGH[$f]}
		printf " ${C_WHITE}%-5s${C_RESET} %b " "${FAN_LABEL[$f]}" "$CV_OUT"
	done

	# ──────────── Gather & display: CPU Freq / Governor ──────────
	ROW=$(( ORIGIN_R + 10 ))
	# Gather data for all cores
	for (( c = 0; c < NUM_CORES; c++ )); do
		FREQ_RAW_LOC[$c]="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_cur_freq"
		FREQ_RAW[$c]=$(cat "${FREQ_RAW_LOC[$c]}" 2>/dev/null || echo 0)
		FREQ_REAL[$c]=$(( FREQ_RAW[c] / FREQ_RAW_DIV ))
		FREQ_GOV[$c]=$(cat "/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor" 2>/dev/null || echo "?")
		GetCoolingState ${c}
		if (( ThorCount == 5 )); then
			CheckSpeed ${c}
			ThorReset=1
		fi
	done

	# Display CPU frequency rows (paired or individual based on detected cores)
	if (( PAIRED )); then
		for (( j = 0; j < HALF_CORES; j++ )); do
			k=$(( j + HALF_CORES ))
			clear_field $(( ROW + j )) $(( ORIGIN_C + 2 )) $(( PANEL_WIDTH - 3 ))
			tput cup $(( ROW + j )) $(( ORIGIN_C + 2 ))

			# Core pair label
			printf " ${C_WHITE}Core ${C_GREEN}%d-%d${C_RESET} " "$j" "$k"

			# Frequencies
			color_for_freq ${FREQ_REAL[$j]:-0}; f1="$CV_OUT"
			color_for_freq ${FREQ_REAL[$k]:-0}; f2="$CV_OUT"
			printf "${C_DIM}│${C_RESET} %b-%b ${C_WHITE}MHz${C_RESET}" "$f1" "$f2"

			# Cooling state
			color_for_state ${THERM_STATE[$j]:-0}; s1="$CV_OUT"
			color_for_state ${THERM_STATE[$k]:-0}; s2="$CV_OUT"
			printf " ${C_DIM}│${C_RESET} %b/%b" "$s1" "$s2"

			# Governor
			color_for_gov "${FREQ_GOV[$j]:-?}"
			printf " %b" "$CV_OUT"
		done
	else
		for (( j = 0; j < NUM_CORES; j++ )); do
			clear_field $(( ROW + j )) $(( ORIGIN_C + 2 )) $(( PANEL_WIDTH - 3 ))
			tput cup $(( ROW + j )) $(( ORIGIN_C + 2 ))

			# Core label
			printf " ${C_WHITE}Core ${C_GREEN}%d${C_RESET}  " "$j"

			# Frequency
			color_for_freq ${FREQ_REAL[$j]:-0}
			printf "${C_DIM}│${C_RESET} %b ${C_WHITE}MHz${C_RESET}" "$CV_OUT"

			# Cooling state
			color_for_state ${THERM_STATE[$j]:-0}
			printf " ${C_DIM}│${C_RESET} %b" "$CV_OUT"

			# Governor
			color_for_gov "${FREQ_GOV[$j]:-?}"
			printf " %b" "$CV_OUT"
		done
	fi

	# ──────────── Bottom status line ─────────────────────────────
	mvprint $(( ORIGIN_R + STATUS_OFF )) $(( ORIGIN_C + 2 )) \
		"${C_DIM}  Last update: $(date '+%H:%M:%S')    Thor: ${ThorCount}/5${C_RESET}          "

	# ──────────── Throttle bookkeeping ───────────────────────────
	if (( ThorReset == 1 )); then
		ThorCount=0
		ThorReset=0
	else
		(( ThorCount++ ))
	fi

	# ──────────── Wait for SLEEP_TIME, but check for 'q' key ────
	for (( _t = 0; _t < SLEEP_TIME * 10; _t++ )); do
		read -rsn1 -t 0.1 key 2>/dev/null
		if [[ "$key" == "q" || "$key" == "Q" ]]; then
			cleanup
		fi
	done
done
