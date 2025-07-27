#!/bin/bash
cd "$(dirname "$(readlink -f "$0")")"
exec 200>/tmp/.myconkyluadir.lock
flock -n 200 || { echo "Inna instancja skryptu działa!"; exit 1; }

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
|         [mail]                                |
|         [mail]                                | 
|         [mail]                                | - DOWN (okno na dole, blok maili w górę)
|         [mail]                                |
|[koperta][E-MAIL: Konto] --------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta][E-MAIL: Konto] --------------------- |
|         [mail]                                | 
|         [mail]                                | - UP (okno na górze, blok maili w dół)
|         [mail]                                |
|         [mail]                                |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|         [mail]                                |
|         [mail]                                |
|         [mail]                                | - DOWN_RIGHT (okno w dolnym prawym rogu, blok maili w górę)
|         [mail]                                |
|[koperta][E-MAIL: Konto]---------------------- |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta][E-MAIL: Konto]---------------------- |
|         [mail]                                | 
|         [mail]                                | - UP_RIGHT (okno w górnym prawym rogu, blok maili w dół)
|         [mail]                                |
|         [mail]                                |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[mail]                                         |
|[mail]                                         |
|[mail]                                         | - DOWN_LEFT (okno w dolnym lewym rogu, blok maili w górę)
|[mail]                                         |
|[E-MAIL: Konto]---------------------- [koperta]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[E-MAIL: Konto]---------------------- [koperta]|
|[mail]                                         | 
|[mail]                                         | - UP_LEFT (okno w górnym lewym rogu, blok maili w dół)
|[mail]                                         |
|[mail]                                         |
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|                                         [mail]|
|                                         [mail]|
|                                         [mail]| - DOWN_RIGHT_REVERSED (dolny prawy róg, odwrócony blok maili)
|                                         [mail]|
|[koperta] ----------------------[E-MAIL: Konto]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
 _______________________________________________
|[koperta]  ---------------------[E-MAIL: Konto]|
|                                         [mail]| 
|                                         [mail]| - UP_RIGHT_REVERSED (górny prawy róg, odwrócony blok maili)
|                                         [mail]|
|                                         [mail]|
 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
EOF

# 1. Najpierw okno podglądu ASCII (duże)
zenity --text-info --title="Podgląd wszystkich układów maili (ASCII)" --font="monospace 10" --width=1000 --height=1300 --filename="$ASCII_LAYOUT_FILE" &
ASCII_PID=$!

# 2. Po krótkim sleep pokazujemy małe okno wyboru layoutu (na wierzchu)
sleep 0.3
zenity_layout=$(zenity --list --radiolist \
    --title="Wybierz układ maili" \
    --width=550 --height=420 \
    --column="" --column="Kod układu" --column="Opis (patrz podgląd w tle)" \
    TRUE "down" "okno na dole, blok maili w górę" \
    FALSE "up" "okno na górze, blok maili w dół" \
    FALSE "down_right" "dolny prawy róg, blok maili w górę" \
    FALSE "up_right" "górny prawy róg, blok maili w dół" \
    FALSE "down_left" "dolny lewy róg, blok maili w górę" \
    FALSE "up_left" "górny lewy róg, blok maili w dół" \
    FALSE "down_right_reversed" "dolny prawy róg, odwrócony blok maili w górę" \
    FALSE "up_right_reversed" "górny prawy róg, odwrócony blok maili w górę" \
)

kill $ASCII_PID 2>/dev/null
rm -f "$ASCII_LAYOUT_FILE"

if [ -z "$zenity_layout" ]; then
    notify-send "Zupix_Py2Lua_Mail_conky" "Nie wybrano układu – operacja anulowana."
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

# UWAGA: poprawka do poleceń sed – poprawiona składnia!
pkill -u "$USER" -f "conky.*$CONKY_FILE"
sed -i "s|^local MAILS_DIRECTION = \".*\"|local MAILS_DIRECTION = \"$MAILS_DIRECTION\"|" "$LUA_FILE"
sed -i "s|^local RIGHT_LAYOUT_REVERSED = .*|local RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED|" "$LUA_FILE"
sed -i "s|^\s*alignment\s*=.*|    alignment               = '$ALIGN_VAL',|" "$CONKY_FILE"

echo "Ustawiono: MAILS_DIRECTION = \"$MAILS_DIRECTION\", RIGHT_LAYOUT_REVERSED = $RIGHT_LAYOUT_REVERSED, alignment = '$ALIGN_VAL' (Conky zrestartowany)"
notify-send "Zupix_Py2Lua_Mail_conky" "Ustawiono MAILS_DIRECTION: $MAILS_DIRECTION, RIGHT_LAYOUT_REVERSED: $RIGHT_LAYOUT_REVERSED, alignment: $ALIGN_VAL (Conky zrestartowany)"

sleep 1
rm -f /tmp/.myconkyluadir.lock

