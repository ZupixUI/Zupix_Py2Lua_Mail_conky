#!/bin/bash
cd "$(dirname "$(readlink -f "$0")")"
exec 200>/tmp/.myconkyluadir.lock
flock -n 200 || { echo "Another instance of the script is running!"; exit 1; }

LUA_FILE="lua/e-mail.lua"
CONKY_FILE="conkyrc_mail"

declare -A ALIGNMENTS=(
    ["down"]="bottom_middle"
    ["up"]="top_middle"
    ["down_left"]="bottom_left"
    ["down_right"]="bottom_right"
    ["up_left"]="top_left"
    ["up_right"]="top_right"
    ["down_right_reversed"]="bottom_right"
    ["up_right_reversed"]="top_right"
)

ASCII_LAYOUT_FILE=$(mktemp)
cat <<EOF >"$ASCII_LAYOUT_FILE"
 _______________________________________________
|          [mail]                               |
|          [mail]                               | 
|          [mail]                               | - DOWN (window at the bottom, mail block upwards)
|          [mail]                               |
|[envelope][E-MAIL: Account] ------------------ |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[envelope][E-MAIL: Account] ------------------ |
|          [mail]                               | 
|          [mail]                               | - UP (window at the top, mail block downwards)
|          [mail]                               |
|          [mail]                               |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|          [mail]                               |
|          [mail]                               |
|          [mail]                               | - DOWN_RIGHT (window in the bottom right corner, mail block upwards)
|          [mail]                               |
|[envelope][E-MAIL: Account]------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[envelope][E-MAIL: Account]------------------- |
|          [mail]                               | 
|          [mail]                               | - UP_RIGHT (window in the top right corner, mail block downwards)
|          [mail]                               |
|          [mail]                               |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[mail]                                         |
|[mail]                                         |
|[mail]                                         | - DOWN_LEFT (window in the bottom left corner, mail block upwards)
|[mail]                                         |
|[E-MAIL: Account]------------------- [envelope]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[E-MAIL: Account]------------------- [envelope]|
|[mail]                                         | 
|[mail]                                         | - UP_LEFT (window in the top left corner, mail block downwards)
|[mail]                                         |
|[mail]                                         |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|                                         [mail]|
|                                         [mail]|
|                                         [mail]| - DOWN_RIGHT_REVERSED (bottom right corner, reversed mail block)
|                                         [mail]|
|[envelope] -------------------[E-MAIL: Account]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[envelope]  ------------------[E-MAIL: Account]|
|                                         [mail]| 
|                                         [mail]| - UP_RIGHT_REVERSED (top right corner, reversed mail block)
|                                         [mail]|
|                                         [mail]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
EOF

# 1. First, show the ASCII preview window (large)
zenity --text-info --title="Preview of all mail layouts (ASCII)" --font="monospace 10" --width=1000 --height=1300 --filename="$ASCII_LAYOUT_FILE" &
ASCII_PID=$!

# 2. After a short sleep, show the small layout selection window (on top)
sleep 0.3
zenity_layout=$(zenity --list --radiolist \
    --title="Choose mail layout" \
    --width=550 --height=420 \
    --column="" --column="Layout code" --column="Description (see preview window)" \
    TRUE "down" "window at the bottom, mail block upwards" \
    FALSE "up" "window at the top, mail block downwards" \
    FALSE "down_right" "bottom right corner, mail block upwards" \
    FALSE "up_right" "top right corner, mail block downwards" \
    FALSE "down_left" "bottom left corner, mail block upwards" \
    FALSE "up_left" "top left corner, mail block downwards" \
    FALSE "down_right_reversed" "bottom right corner, reversed mail block upwards" \
    FALSE "up_right_reversed" "top right corner, reversed mail block upwards" \
)

kill $ASCII_PID 2>/dev/null
rm -f "$ASCII_LAYOUT_FILE"

if [ -z "$zenity_layout" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "No layout selected – operation cancelled."
    exit 0
fi

SELECTED="$zenity_layout"

case "$SELECTED" in
    "down_right_reversed")
        MAILS_DIRECTION="down_right"
        RIGHT_LAYOUT_REVERSED=true
        ;;
    "up_right_reversed")
        MAILS_DIRECTION="up_right"
        RIGHT_LAYOUT_REVERSED=true
        ;;
    *)
        MAILS_DIRECTION="$SELECTED"
        RIGHT_LAYOUT_REVERSED=false
        ;;
esac

ALIGN_VAL="${ALIGNMENTS[$SELECTED]}"

# NOTE: sed commands corrected – improved syntax!
pkill -u "$USER" -f "conky.*$CONKY_FILE"
sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
sed -i "s|^\s*alignment\s*=.*|    alignment               = '$ALIGN_VAL',|" "$CONKY_FILE"

echo "Set: MAILS_DIRECTION = \"$MAILS_DIRECTION\", RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED, alignment = '$ALIGN_VAL' (Conky restarted)"
notify-send "Zupix_Py2Lua_Mail_conky" "Set MAILS_DIRECTION: $MAILS_DIRECTION, RIGHT_LAYOUT_REVERSED: $RIGHT_LAYOUT_REVERSED, alignment: $ALIGN_VAL (Conky restarted)"

sleep 1
rm -f /tmp/.myconkyluadir.lock

