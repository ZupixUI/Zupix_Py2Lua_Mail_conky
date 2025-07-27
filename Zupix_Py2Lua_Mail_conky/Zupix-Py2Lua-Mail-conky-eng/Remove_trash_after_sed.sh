#!/bin/bash

cd "$(dirname "$0")"

TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
for t in "${TERMINALS[@]}"; do command -v "$t" &>/dev/null && { TERM="$t"; break; }; done

SHOW_AND_DELETE='
FILES=$(sudo find "$(pwd)" -maxdepth 1 -type f -name "sed*" -printf "%f\n")
if [ -z "$FILES" ]; then
    echo "No sed* files to delete."
else
    echo "sed* files to be deleted:"
    echo "$FILES"
    echo
    echo "Deleting..."
    sudo find "$(pwd)" -maxdepth 1 -type f -name "sed*" -exec rm -f {} \;
    echo "The above files have been deleted."
fi
'

if [ -z "$TERM" ]; then
    echo "No terminal found. Please run this in your terminal:"
    eval "$SHOW_AND_DELETE"
    exit 1
fi

case "$TERM" in
    gnome-terminal)
        gnome-terminal -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Done! You can now close this window.'; exec bash"
        ;;
    xfce4-terminal)
        xfce4-terminal --hold -e "bash -ic \"$SHOW_AND_DELETE; echo; echo 'Done! You can now close this window.'; exec bash\""
        ;;
    konsole)
        konsole -e bash -ic "$SHOW_AND_DELETE; echo; echo 'Done! You can now close this window.'; exec bash"
        ;;
    tilix)
        tilix -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Done! You can now close this window.'; exec bash"
        ;;
    mate-terminal)
        mate-terminal -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Done! You can now close this window.'; exec bash"
        ;;
    xterm)
        xterm -e "bash -ic '$SHOW_AND_DELETE; echo; echo \"Done! You can now close this window.\"; exec bash'"
        ;;
    *)
        $TERM -- bash -ic "$SHOW_AND_DELETE; echo; echo 'Done! You can now close this window.'; exec bash"
        ;;
esac
