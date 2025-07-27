#!/bin/bash

FILE="/tmp/conky_mail_scroll_offset"

# Read current offset
offset=0
if [[ -f "$FILE" ]]; then
    offset=$(cat "$FILE")
fi

# Increase offset by 1
offset=$((offset + 1))

# Save new offset
echo "$offset" > "$FILE"

