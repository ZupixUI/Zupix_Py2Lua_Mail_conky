#!/bin/bash

cd "$(dirname "$0")"

TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
for t in "${TERMINALS[@]}"; do command -v "$t" &>/dev/null && { TERM="$t"; break; }; done

SHOW_AND_DELETE='
FILES=$(sudo find "$(pwd)" -maxdepth 1 -type f -name "sed*" -printf "%f\n")
if [ -z "$FILES" ]; then
    echo "Brak plików sed* do usunięcia."
else
    echo "Pliki sed* do usunięcia:"
    echo "$FILES"
    echo
    echo "Usuwam..."
    sudo find "$(pwd)" -maxdepth 1 -type f -name "sed*" -exec rm -f {} \;
    echo "Usunięto powyższe pliki."
fi
'

if [ -z "$TERM" ]; then
    echo "Nie znaleziono terminala. Uruchom to w swoim terminalu:"
    eval "$SHOW_AND_DELETE"
    exit 1
fi

case "$TERM" in
    gnome-terminal)
        gnome-terminal -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Gotowe! Możesz zamknąć to okno.'; exec bash"
        ;;
    xfce4-terminal)
        xfce4-terminal --hold -e "bash -ic \"$SHOW_AND_DELETE; echo; echo 'Gotowe! Możesz zamknąć to okno.'; exec bash\""
        ;;
    konsole)
        konsole -e bash -ic "$SHOW_AND_DELETE; echo; echo 'Gotowe! Możesz zamknąć to okno.'; exec bash"
        ;;
    tilix)
        tilix -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Gotowe! Możesz zamknąć to okno.'; exec bash"
        ;;
    mate-terminal)
        mate-terminal -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Gotowe! Możesz zamknąć to okno.'; exec bash"
        ;;
    xterm)
        xterm -e "bash -ic '$SHOW_AND_DELETE; echo; echo \"Gotowe! Możesz zamknąć to okno.\"; exec bash'"
        ;;
    *)
        $TERM -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Gotowe! Możesz zamknąć to okno.'; exec bash"
        ;;
esac

