#!/bin/bash

MOBO_HWMON="hwmon2"
CPU_HWMON="hwmon1"
NVME_HWMON="hwmon0"

############# CONFIG START ################

TEMP_RAW_LOC[0]="/sys/class/hwmon/${CPU_HWMON}/temp1_input"
TEMP_RAW_DIV[0]="1000"
TEMP_COOL[0]="55"
TEMP_WARM[0]="60"
TEMP_HOT[0]="65"
TEMP_DOWN[0]="84"
TEMP_UP[0]="70"
TEMP_LABEL[0]="Core"

TEMP_RAW_LOC[1]="/sys/class/hwmon/${CPU_HWMON}/temp3_input"
TEMP_RAW_DIV[1]="1000"
TEMP_COOL[1]="55"
TEMP_WARM[1]="65"
TEMP_HOT[1]="75"
TEMP_DOWN[1]="75"
TEMP_UP[1]="60"
TEMP_LABEL[1]="| CCD"

TEMP_RAW_LOC[2]="/sys/class/hwmon/${MOBO_HWMON}/temp8_input"
TEMP_RAW_DIV[2]="1000"
TEMP_COOL[2]="55"
TEMP_WARM[2]="65"
TEMP_HOT[2]="75"
TEMP_DOWN[2]="80"
TEMP_UP[2]="60"
TEMP_LABEL[2]="| CPU"

TEMP_RAW_LOC[3]="/sys/class/hwmon/${MOBO_HWMON}/temp1_input"
TEMP_RAW_DIV[3]="1000"
TEMP_COOL[3]="40"
TEMP_WARM[3]="45"
TEMP_HOT[3]="55"
TEMP_DOWN[3]="50"
TEMP_UP[3]="45"
TEMP_LABEL[3]="| System"

TEMP_RAW_LOC[4]="/sys/class/hwmon/${NVME_HWMON}/temp1_input"
TEMP_RAW_DIV[4]="1000"
TEMP_COOL[4]="55"
TEMP_WARM[4]="60"
TEMP_HOT[4]="65"
TEMP_LABEL[4]="NVMe"

TEMP_RAW_LOC[5]="/sys/class/hwmon/${NVME_HWMON}/temp2_input"
TEMP_RAW_DIV[5]="1000"
TEMP_COOL[5]="55"
TEMP_WARM[5]="60"
TEMP_HOT[5]="65"
TEMP_LABEL[5]="| SN1"

TEMP_RAW_LOC[6]="/sys/class/hwmon/${NVME_HWMON}/temp3_input"
TEMP_RAW_DIV[6]="1000"
TEMP_COOL[6]="55"
TEMP_WARM[6]="60"
TEMP_HOT[6]="65"
TEMP_LABEL[6]="| SN2"

FAN_RAW_LOC[0]="/sys/class/hwmon/${MOBO_HWMON}/fan1_input"
FAN_LOW[0]="500"
FAN_HIGH[0]="1800"
FAN_LABEL[0]="CPU: "

FAN_RAW_LOC[1]="/sys/class/hwmon/${MOBO_HWMON}/fan2_input"
FAN_LOW[1]="500"
FAN_HIGH[1]="2000"
FAN_LABEL[1]="| Case: "

FAN_RAW_LOC[2]="/sys/class/hwmon/${MOBO_HWMON}/fan3_input"
FAN_LOW[2]="500"
FAN_HIGH[2]="2000"
FAN_LABEL[2]="| Front: "

FAN_RAW_LOC[3]="/sys/class/hwmon/${MOBO_HWMON}/fan4_input"
FAN_LOW[3]="500"
FAN_HIGH[3]="2000"
FAN_LABEL[3]="| "

FAN_RAW_LOC[4]="/sys/class/hwmon/${MOBO_HWMON}/fan7_input"
FAN_LOW[4]="500"
FAN_HIGH[4]="2000"
FAN_LABEL[4]="| "

SLEEP_TIME=3

FREQ_LOW="2200"
FREQ_MID="3200"
FREQ_HIGH="4000"

FREQ_RAW_DIV="1000"

############### CONFIG END ################

core="0"
ThorCount="0"
ThorReset="0"

# Get the raw temp, then divide it by value set in config, then colorize it.
function GetRealTemp() {
	TEMP_RAW[$i]=`cat ${TEMP_RAW_LOC[$i]}`
	TEMP_REAL[$i]=$((${TEMP_RAW[$i]}/${TEMP_RAW_DIV[$i]}))
	ColorizeTemp
}

# Get the raw freq, then divide it by value set in config, then colorize it.
function GetRealFreq() {
	FREQ_RAW[$c]=`cat ${FREQ_RAW_LOC[$c]}`
	FREQ_REAL[$c]=$((${FREQ_RAW[$c]}/${FREQ_RAW_DIV}))
	ColorizeFreq
}

# Get the governor and then colorize it.
function GetGovernor() {
	FREQ_GOV[$c]=`cat /sys/devices/system/cpu/cpu${c}/cpufreq/scaling_governor`
	ColorizeGov
}

# Get the fan speed and then colorize it.
function GetFanSpeed() {
	FAN_SPEED[$f]=`cat ${FAN_RAW_LOC[$f]}`
	ColorizeFan
}

# Get the current cooling state.
function GetCoolingState() {
	coolcore=$1
	THERM_STATE[${coolcore}]=`cat ./${coolcore}cur_state_text.core`
	ColorizeState
}

function GetSpeed() {
	i=$1
	GetCoolingState ${i}
	if [ ${TEMP_REAL[$i]} -le ${TEMP_UP[$i]} ] ;
	then
		if [ ${THERM_STATE[$i]} -gt 0 ] ;
		then
		    SPEED=$((${THERM_STATE[$i]}-1))
		    return ;
		fi
	fi
	if [ ${TEMP_REAL[$i]} -le ${TEMP_DOWN[$i]} -a ${TEMP_REAL[$i]} -gt ${TEMP_UP[$i]} ] ;
	then
		SPEED=${THERM_STATE[$i]}
		return ;
	fi
	if [ ${TEMP_REAL[$i]} -gt ${TEMP_DOWN[$i]} ] ;
	then
		if [ ${THERM_STATE[$i]} -le 3 ] ;
		then
		    SPEED=$((${THERM_STATE[$i]}+1))
		    return ;
		fi
	fi
	SPEED=0
}

function CheckSpeed() {
	cores=$1
	if [ ${SPEED} -lt ${THERM_STATE[$cores]} -a ${THERM_STATE[$cores]} != 0 ] ;
	then
		NEW_STATE=$((${THERM_STATE[$cores]} - 1))
		ThorCores ${NEW_STATE} ${cores}
		echo ${NEW_STATE} > ./${cores}cur_state_text.core
		if [ ${cores} != 0 -a ${NEW_STATE} == 0 ] ;
		then
			cores=$((${cores}-1)) ;
		fi
		return ;
	fi
	if [ ${SPEED} -gt ${THERM_STATE[$cores]} -a ${THERM_STATE[$cores]} != 4 ] ;
	then
		NEW_STATE=$((${THERM_STATE[$cores]} + 1))
		if [ ${NEW_STATE} == 4 -a ${cores} != 4 ] ;
		then
			cores=$((${cores}+1))
			NEW_STATE="1" ;
		fi
		ThorCores ${NEW_STATE} ${cores}
		echo ${NEW_STATE} > ./${cores}cur_state_text.core
		return ;
	fi
}

function ThorCores() {
	case $1 in
	    0)
		echo 1 > /sys/devices/system/cpu/cpufreq/boost
		;;
	    1)
		max_freq="3600000"
		echo $max_freq > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq
		echo 0 > /sys/devices/system/cpu/cpufreq/boost
		;;
	    2)
		max_freq="2800000"
		echo $max_freq > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq
		;;
	    3)
		max_freq="2200000"
		echo $max_freq > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq
		;;
	    *)
		max_freq="2200000"
		echo $max_freq > /sys/devices/system/cpu/cpu$2/cpufreq/scaling_max_freq
		;;
	esac

}

# Function for colorizing a string.
function ColorizeStr() {

	# Case statement to set ascii color code from named color
	case "$1" in
		"blue" )
			color="\e[1;34m"
			;;
		"red" )
			color="\e[1;37;31m"
			;;
		"yellow" )
			color="\e[1;33m"
			;;
		"green" )
			color="\e[1;32m"
			;;
	esac
 
	# Do the actual echo, note the -e to use the escape codes
	# and notice the color reset at the end, always use that.
	CL_STR="${color}${2}\e[0m"
	
}

# Function to colorize the cooling state value.
function ColorizeState() {
	case ${THERM_STATE[$c]} in 
		"0" )
			ColorizeStr "green" ${THERM_STATE[$c]}
			STATE_STR[$c]=${CL_STR}
		;;
		"1" )
			ColorizeStr "yellow" ${THERM_STATE[$c]}
			STATE_STR[$c]=${CL_STR}
		;;
		"2" )
			ColorizeStr "red" ${THERM_STATE[$c]}
			STATE_STR[$c]=${CL_STR}
		;;
	esac
}

# Function to colorize the governor value.
function ColorizeGov() {
	case ${FREQ_GOV[$c]} in 
		"ondemand" )
			ColorizeStr "green" ${FREQ_GOV[$c]}
			GOV_STR[$c]=${CL_STR}
		;;
		"performance" )
			ColorizeStr "red" ${FREQ_GOV[$c]}
			GOV_STR[$c]=${CL_STR}
		;;
		"powersave" )
			ColorizeStr "blue" ${FREQ_GOV[$c]}
			GOV_STR[$c]=${CL_STR}
		;;
		"userspace" )
			ColorizeStr "yellow" ${FREQ_GOV[$c]}
			GOV_STR[$c]=${CL_STR}
		;;
		"conservative" )
			ColorizeStr "yellow" ${FREQ_GOV[$c]}
			GOV_STR[$c]=${CL_STR}
		;;
	esac
}

# Function to colorize the temp.
function ColorizeTemp() {
	if [ ${TEMP_REAL[$i]} -le ${TEMP_COOL[$i]} ] ;
	then
		ColorizeStr "blue" ${TEMP_REAL[$i]}
		TEMP_STR[$i]=${CL_STR}
		return ;
	fi
	if [ ${TEMP_REAL[$i]} -gt ${TEMP_COOL[$i]} -a ${TEMP_REAL[$i]} -le ${TEMP_WARM[$i]} ] ;
	then
		ColorizeStr "green" ${TEMP_REAL[$i]}
		TEMP_STR[$i]=${CL_STR}
		return ;
	fi
	if [ ${TEMP_REAL[$i]} -gt ${TEMP_WARM[$i]} -a ${TEMP_REAL[$i]} -le ${TEMP_HOT[$i]} ] ;
	then
		ColorizeStr "yellow" ${TEMP_REAL[$i]}
		TEMP_STR[$i]=${CL_STR}
		return ;
	fi
	if [ ${TEMP_REAL[$i]} -gt ${TEMP_HOT[$i]} ] ;
	then
		ColorizeStr "red" ${TEMP_REAL[$i]}
		TEMP_STR[$i]=${CL_STR}
		return ;
	fi
}
	
# Function to colorize the temp.
function ColorizeFan() {
	if [ ${FAN_SPEED[$f]} -le ${FAN_LOW[$f]} ] ;
	then
		ColorizeStr "red" ${FAN_SPEED[$f]}
		FAN_STR[$f]=${CL_STR}
		return ;
	fi
	if [ ${FAN_SPEED[$f]} -le ${FAN_HIGH[$f]} -a ${FAN_SPEED[$f]} -gt ${FAN_LOW[$f]} ] ;
	then
		ColorizeStr "green" ${FAN_SPEED[$f]}
		FAN_STR[$f]=${CL_STR}
		return ;
	fi
	if [ ${FAN_SPEED[$f]} -gt ${FAN_HIGH[$f]} ] ;
	then
		ColorizeStr "red" ${FAN_SPEED[$f]}
		FAN_STR[$f]=${CL_STR}
		return ;
	fi
}

# Function to colorize the frequency.
function ColorizeFreq() {
	if [ ${FREQ_REAL[$c]} -le ${FREQ_LOW} ] ;
	then
		ColorizeStr "blue" ${FREQ_REAL[$c]}
		FREQ_STR[$c]=${CL_STR}
		return ;
	fi
	if [ ${FREQ_REAL[$c]} -gt ${FREQ_LOW} -a ${FREQ_REAL[$c]} -le ${FREQ_MID} ] ;
	then
		ColorizeStr "green" ${FREQ_REAL[$c]}
		FREQ_STR[$c]=${CL_STR}
		return ;
	fi
	if [ ${FREQ_REAL[$c]} -gt ${FREQ_MID} -a ${FREQ_REAL[$c]} -le ${FREQ_HIGH} ] ;
	then
		ColorizeStr "yellow" ${FREQ_REAL[$c]}
		FREQ_STR[$c]=${CL_STR}
		return ;
	fi
	if [ ${FREQ_REAL[$c]} -gt ${FREQ_HIGH} ] ;
	then
		ColorizeStr "red" ${FREQ_REAL[$c]}
		FREQ_STR[$c]=${CL_STR}
		return ;
	fi
}

# Start of program loop.
while [ TRUE ]
do

	# Loop for gathering CPU temp sensor information.
	for i in {0..3} ;
	do 
		#echo -e ${i}
		if [ -z ${TEMP_RAW_LOC[$i]} ] ;
		then
			break ;
		fi
		GetRealTemp
		if [ "${TEMP_LABEL[$i]}" == "Core" ] ;
		then
			GetSpeed $i ;
		fi
		TEMP_OUT="${TEMP_OUT}\e[1;37m ${TEMP_LABEL[$i]}: ${TEMP_STR[$i]}\e[1;37mc\e[0m"
	done

	# Loop for gathering NVMe temp sensor information.
	for i in {4..6} ;
	do 
		#echo -e ${TEMP_RAW_LOC[$i]}
		if [ -z ${TEMP_RAW_LOC[$i]} ] ;
		then
			break ;
		fi
		GetRealTemp
		NVME_OUT="${NVME_OUT}\e[1;37m ${TEMP_LABEL[$i]}: ${TEMP_STR[$i]}\e[1;37mc\e[0m"
	done

	# Loop for gathering fan information.
	for f in {0..7} ;
	do 
		if [ -z ${FAN_RAW_LOC[$f]} ] ;
		then
			break ;
		fi
		GetFanSpeed
		FAN_OUT="${FAN_OUT}\e[1;37m ${FAN_LABEL[$f]}${FAN_STR[$f]}\e[1;37m\e[0m"
	done

	# Loop for gathering cpufreq information.
	for c in {0..15} ;
	do
		FREQ_RAW_LOC[$c]="/sys/devices/system/cpu/cpu${c}/cpufreq/scaling_cur_freq"
		if [ ! -e ${FREQ_RAW_LOC[$c]} ] ;
		then
			break ;
		fi
		GetGovernor
		GetRealFreq
		GetCoolingState ${c}
		if [ $ThorCount -eq 5 ] ;
		then
		    CheckSpeed ${c}
		    ThorReset="1"
		fi
	done

	for j in {0..7} ;
	do
		k=$((j + 8))
		if [ $k -eq 8 -o $k -eq 9 ] ;
		then
		    k_out="$j-$k "
		else
		    k_out="$j-$k"
		fi
		FREQ_OUT[$j]="\e[1;37m Core\e[0m:\e[1;32m$k_out\e[1;37m\e[0m \e[1;37m|\e[0m ${FREQ_STR[$j]}-${FREQ_STR[$k]}\e[1;37mMhz |\e[0m ${STATE_STR[$j]}/${STATE_STR[$k]} ${GOV_STR[$j]}\e[0m"
	done
	### Start output
	
	echo "<=============================================>"
	echo -e ${TEMP_OUT}
	echo -e ${NVME_OUT}
	echo -e ${FAN_OUT}

	# Loop for cpufreq output.
	for OUT in "${FREQ_OUT[@]}" ;
	do
		echo -e ${OUT}
	done
	
	# Clear TEMP_OUT var
	if [ $ThorReset -eq 1 ] ;
	then
	    ThorCount="0"
	    ThorReset="0"
	else
	    ((ThorCount++))
	fi
	TEMP_OUT=""
	FAN_OUT=""
	NVME_OUT=""
	# Sleep for time set in config.
	sleep $SLEEP_TIME
done
