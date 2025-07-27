#!/bin/bash

FILE="/tmp/conky_mail_scroll_offset"

# Odczytaj aktualny offset
offset=0
if [[ -f "$FILE" ]]; then
    offset=$(cat "$FILE")
fi

# Zwiększ offset o 1
offset=$((offset + 1))

# Zapisz nowy offset
echo "$offset" > "$FILE"

