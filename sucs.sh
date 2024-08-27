#!/bin/bash

############################################
# Slackin's UrbanTerror Colorizing Script
# Version 1.0
# Author: Slackin
# Date: 2024-08-26
# Usage: ./sucs.sh UrbanTerrorExecutable.x86_64
# Description: This script colorizes the output of UrbanTerror.
#              It takes the UrbanTerror executable as an argument.
#              The script checks if the executable exists, is a file,
#              is executable, and is a 64-bit executable.
#              The script then runs the executable and processes the
#              output to colorize it.
#              The script uses ANSI escape codes to colorize the output.
############################################

# Check if UrbanTerror executable is provided
if [ -z "$1" ]; then
    echo "Usage: $0 UrbanTerrorExecutable.x86_64"
    exit 1
fi

# Check if UrbanTerror executable exists
if [ ! -f "$1" ]; then
    echo "Error: $1 not found"
    exit 1
fi

# Check if UrbanTerror executable is a file
if [ ! -f "$1" ]; then
    echo "Error: $1 is not a file"
    exit 1
fi

# Check if UrbanTerror executable is executable
if [ ! -x "$1" ]; then
    echo "Error: $1 is not executable"
    exit 1
fi

# Check if UrbanTerror executable is a 64-bit executable
if ! file "$1" | grep -q "x86-64"; then
    echo "Error: $1 is not a 64-bit executable"
    exit 1
fi

# Run executable taking standard input and processing it to colorize the output
"$1" 2>&1 | sed -e 's/\^1/\x1b[1;31;49m/g' \
    -e 's/\^2/\x1b[1;32;49m/g' \
    -e 's/\^3/\x1b[1;33;49m/g' \
    -e 's/\^4/\x1b[1;34;49m/g' \
    -e 's/\^5/\x1b[1;36;49m/g' \
    -e 's/\^6/\x1b[1;35;49m/g' \
    -e 's/\^7/\x1b[1;37;49m/g' \
    -e 's/\^8/\x1b[32;49m/g' \
    -e 's/\^9/\x1b[33;49m/g' \
    -e 's/\^0/\x1b[1;30;47m/g'

echo -e "\x1b[0m"  # Reset color
