#!/bin/bash

FILE="/tmp/conky_mail_scroll_offset"

offset=0
if [[ -f "$FILE" ]]; then
    offset=$(cat "$FILE")
fi

offset=$((offset - 1))  # WAŻNE: pozwól zejść poniżej zera

echo "$offset" > "$FILE"

