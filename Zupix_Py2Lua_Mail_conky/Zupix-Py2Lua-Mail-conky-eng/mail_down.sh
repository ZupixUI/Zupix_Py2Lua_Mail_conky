#!/bin/bash

FILE="/tmp/conky_mail_scroll_offset"

# Initialize offset variable
offset=0

# If the file exists, read the current offset value from it
if [[ -f "$FILE" ]]; then
    offset=$(cat "$FILE")
fi

# Decrease the offset by 1
offset=$((offset - 1))

# Save the new offset value back to the file
echo "$offset" > "$FILE"
