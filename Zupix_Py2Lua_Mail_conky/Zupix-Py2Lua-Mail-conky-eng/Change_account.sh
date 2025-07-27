#!/bin/bash

MAX_IDX=3  # Number of accounts (for three accounts: 3, because 0 = multi-account)
IDXFILE="/tmp/conky_mail_account"

# List of account names – in the same order as in LUA and PYTHON!
ACCOUNT_NAMES=(
    "Multi-account"
    "login_1@gmail.com"
    "login_2@gmail.com"
    "login_3@gmail.com"
)

# Select account via zenity
CHOICE=$(zenity --list \
    --title="Select account" \
    --column="Available accounts" \
    "${ACCOUNT_NAMES[@]}")

# If user didn't select (cancelled), exit script
if [ -z "$CHOICE" ]; then
    exit 0
fi

# Determine the number of the selected account
for i in "${!ACCOUNT_NAMES[@]}"; do
    if [[ "${ACCOUNT_NAMES[$i]}" == "$CHOICE" ]]; then
        next=$i
        break
    fi
done

echo "$next" > "$IDXFILE"

notify-send "Conky Mail" "Selected: ${ACCOUNT_NAMES[$next]} (index $next)"

