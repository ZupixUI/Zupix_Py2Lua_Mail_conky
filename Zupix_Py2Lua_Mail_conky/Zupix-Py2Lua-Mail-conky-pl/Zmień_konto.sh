#!/bin/bash

MAX_IDX=3  # Liczba kont (dla trzech kont: 3, bo 0 = multikonto)
IDXFILE="/tmp/conky_mail_account"

# Lista nazw kont – w tej samej kolejności jak w LUA i PYTHON!
ACCOUNT_NAMES=(
    "Mulit-konto"
    "name_1@gmail.com"
    "name_2@gmail.com"
    "name_3@gmail.com"
)

# Wybierz konto przez zenity
CHOICE=$(zenity --list \
    --title="Wybierz konto" \
    --column="Dostępne konta" \
    "${ACCOUNT_NAMES[@]}")

# Jeżeli użytkownik nie wybrał (anulował), zakończ skrypt
if [ -z "$CHOICE" ]; then
    exit 0
fi

# Ustal numer wybranego konta
for i in "${!ACCOUNT_NAMES[@]}"; do
    if [[ "${ACCOUNT_NAMES[$i]}" == "$CHOICE" ]]; then
        next=$i
        break
    fi
done

echo "$next" > "$IDXFILE"

notify-send "Conky Mail" "Wybrano: ${ACCOUNT_NAMES[$next]} (numer $next)"

