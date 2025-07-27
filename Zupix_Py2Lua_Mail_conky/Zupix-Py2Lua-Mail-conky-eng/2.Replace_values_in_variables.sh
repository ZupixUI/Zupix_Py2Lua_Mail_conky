#!/bin/bash

# Zupix-Py2Lua-Mail-conky – 2.Variable_path_replace.sh

zen_echo() {
    zenity --info --title="Zupix-Py2Lua-Mail-conky – configuration" --no-wrap --text="$1"
}

zen_error() {
    zenity --error --title="Zupix-Py2Lua-Mail-conky – error" --no-wrap --text="$1"
}

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$PROJECT_DIR" =~ [[:space:]] ]]; then
    MSG="Spaces detected in the project path:\n$PROJECT_DIR\n\nPlease rename the directory or move the project to a path without spaces.\n(e.g. /home/user/Zupix-Py2Lua-Mail-conky)\n\nThis is a Conky limitation – files in such a path will not work!"
    if command -v zenity &>/dev/null; then
        zen_error "$MSG"
    else
        echo -e "$MSG"
    fi
    exit 1
fi

if ! command -v zenity &>/dev/null; then
    echo "Missing 'zenity'. Install it with: sudo apt install zenity"
    exit 1
fi

CONFIGS=(
    "lua/e-mail.lua|local NEW_MAIL_SOUND = \".*\"|local NEW_MAIL_SOUND = \"$PROJECT_DIR/sound/nowy_mail.wav\"|local NEW_MAIL_SOUND = \"$PROJECT_DIR/sound/nowy_mail.wav\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local ENVELOPE_IMAGE = \".*\"|local ENVELOPE_IMAGE = \"$PROJECT_DIR/icons/mail.png\"|local ENVELOPE_IMAGE = \"$PROJECT_DIR/icons/mail.png\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local ATTACHMENT_ICON_IMAGE = \".*\"|local ATTACHMENT_ICON_IMAGE = \"$PROJECT_DIR/icons/spinacz1.png\"|local ATTACHMENT_ICON_IMAGE = \"$PROJECT_DIR/icons/spinacz1.png\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local path = \".*\"|local path = \"$PROJECT_DIR/config/mail_conky_max\"|local path = \"$PROJECT_DIR/config/mail_conky_max\"|.e-mail.lua.bak"
    "lua/e-mail.lua|local SHAKE_SOUND = \".*\"|local SHAKE_SOUND = \"$PROJECT_DIR/sound/shake_2.wav\"|local SHAKE_SOUND = \"$PROJECT_DIR/sound/shake_2.wav\"|.e-mail.lua.bak"
    "conkyrc_mail|^ *lua_load *=.*|    lua_load = '$PROJECT_DIR/lua/e-mail.lua',|lua_load = '$PROJECT_DIR/lua/e-mail.lua'|.conkyrc_mail.bak"
)

for conf in "${CONFIGS[@]}"; do
    IFS="|" read -r FILE _ _ _ _ <<<"$conf"
    FULL_PATH="$PROJECT_DIR/$FILE"
    if [ ! -f "$FULL_PATH" ]; then
        zen_error "File not found: $FULL_PATH"
        exit 2
    fi
done

# Fixed-length separator
SEPARATOR=$(printf '%*s' 280 '' | tr ' ' -)

RESULTS=""
for conf in "${CONFIGS[@]}"; do
    IFS="|" read -r FILE SED_PATTERN SED_NEW RE_PATTERN BACKUP <<<"$conf"
    FULL_PATH="$PROJECT_DIR/$FILE"
    BACKUP_PATH="$(dirname "$FULL_PATH")/$BACKUP"

    cp "$FULL_PATH" "$BACKUP_PATH"
    sed -i "s|$SED_PATTERN|$SED_NEW|g" "$FULL_PATH"

    # Improved variable name extraction
    VAR_NAME=""
    if [[ "$SED_PATTERN" =~ ^\^.*lua_load ]]; then
        VAR_NAME="lua_load ="
    elif [[ "$SED_PATTERN" =~ local[[:space:]]+([A-Za-z0-9_]+)[[:space:]]*= ]]; then
        VAR_NAME="${BASH_REMATCH[1]} ="
    elif [[ "$SED_PATTERN" =~ os.execute ]]; then
        VAR_NAME="os.execute(...)"
    elif [[ "$SED_PATTERN" =~ open ]]; then
        VAR_NAME="open(...)"
    else
        VAR_NAME="$SED_PATTERN"
    fi

    if grep -qF "$RE_PATTERN" "$FULL_PATH"; then
        NEW_LINE=$(grep -m1 -F "$RE_PATTERN" "$FULL_PATH")
        [ -z "$NEW_LINE" ] && NEW_LINE="(could not find new value)"
        MSG="OK: Changed variable \"<b>$VAR_NAME</b>\" in file <b>$FILE</b> (backup: $BACKUP)\nNew variable value: <tt>$NEW_LINE</tt>"
    else
        MSG="ERROR: Could not replace value: \"$RE_PATTERN\" in file $FILE! (backup: $BACKUP)"
        zen_error "$MSG"
    fi

    RESULTS="$RESULTS$MSG\n$SEPARATOR\n"
done

SUMMARY_TEXT="<big><b>Replacement results:</b></big>\n$SEPARATOR\n$RESULTS\n<b>All backups have been created as hidden files in the target directories.</b>\n\n<big>Do you want to now run <b>3.START_script_and_conky.sh</b> and start the mail widget?</big>"

# --- Escape & for zenity/GTK
SUMMARY_TEXT_ESCAPED="${SUMMARY_TEXT//&/&amp;}"

if zenity --question \
    --title="Success! 🎉" \
    --width=900 \
    --ok-label="Yes" --cancel-label="No" \
    --text="$SUMMARY_TEXT_ESCAPED"
then
    # Yes
    if [ -f "$PROJECT_DIR/3.START_script_and_conky.sh" ]; then
        bash "$PROJECT_DIR/3.START_script_and_conky.sh" &
        exit 0
    else
        zen_error "File \"3.START_script_and_conky.sh\" not found!"
        exit 1
    fi
else
    # No or window closed
    zen_echo "✅ Configuration complete. You can now manually run the script: 3.START_script_and_conky.sh"
fi

exit 0

