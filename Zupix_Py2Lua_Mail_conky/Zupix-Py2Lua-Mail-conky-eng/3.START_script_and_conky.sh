#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

LOCK_FILE="/tmp/loop_script.lock"
CONKY_CONF="conkyrc_mail"
PYTHON_SCRIPT="./py/python_mail_conky_lua.py"
MAIL_CACHE="/tmp/mail_cache.json"
MAX_WAIT=60  # seconds to wait for cache to appear

RESPAWN_PID_FILE="/tmp/respawn_conky.pid"
RAM_PID_FILE="/tmp/ram_watchdog.pid"

exec 200>"$LOCK_FILE"
flock -n 200 || {
    notify-send "ℹ️ Already running" "The script is already running in the background. Second instance will not start."
    if command -v zenity >/dev/null 2>&1; then
        zenity --question \
            --title="Conky Mail – already running!" \
            --text="<big><big><b>Zupix_Py2Lua_Mail_conky</b> is already running in the background!</big></big>\n\nDo you want to clear the lock and kill ALL related processes?\n\n(This will kill the <b>conky</b> window, the script <b>python_mail_conky_lua.py</b>, the cache <b>/tmp/mail_cache.json</b> and other temp files.)"
        if [ $? -eq 0 ]; then
            # First kill the watchdogs!
            if [ -f "$RESPAWN_PID_FILE" ]; then
                kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null
                rm -f "$RESPAWN_PID_FILE"
            fi
            if [ -f "$RAM_PID_FILE" ]; then
                kill $(cat "$RAM_PID_FILE") 2>/dev/null
                rm -f "$RAM_PID_FILE"
            fi
            sleep 0.01  # Optional short sleep for loop cleanup
            
            # NOW kill Conky (so it doesn't respawn)
            CONKY_PID=$(pgrep -f "conky.*-c $CONKY_CONF")
            if [ -n "$CONKY_PID" ]; then
                kill $CONKY_PID 2>/dev/null
            fi
            # Remove lock file and first-run flag
            rm -f "$LOCK_FILE"
            rm -f /tmp/mail_sound_played
            rm -f /tmp/mail_cache.err
            rm -f /tmp/mail_cache.json
            # Kill related python scripts
            PIDS=$(pgrep -f "python3.*${PYTHON_SCRIPT}")
            if [ -n "$PIDS" ]; then
                kill $PIDS 2>/dev/null
            fi
            notify-send "✅ Everything stopped" "conky/py processes killed, lock removed."
            # Ask about restarting the script
            zenity --question \
                --title="Restart Conky Mail" \
                --text="Do you want to run 3.START_script_and_conky.sh again?"
            if [ $? -eq 0 ]; then
                notify-send "🔁 Restarting!" "Restarting 3.START_script_and_conky.sh"
                exec "$0"
            else
                notify-send "🛑 Finished" "Not restarting. Everything stopped."
                exit 0
            fi
        fi
    fi
    exit 1
}

if [ ! -f "$PYTHON_SCRIPT" ]; then
    notify-send "❗ File missing" "File $PYTHON_SCRIPT not found. Exiting script."
    echo "File $PYTHON_SCRIPT not found. Exiting."
    exit 1
fi

MEM_LIMIT_MB=299

# --- Watchdog: instant respawn of Conky as loose loop ---
while true; do
    if ! pgrep -u "$USER" -f "conky.*-c $CONKY_CONF" >/dev/null; then
        conky -c "$CONKY_CONF" &
    fi
    sleep 0.15
done &
RESPAWN_PID=$!
echo $RESPAWN_PID > "$RESPAWN_PID_FILE"

# --- RAM watchdog as loose loop ---
while true; do
    CONKY_PIDS=$(pgrep -u "$USER" -f "conky.*-c $CONKY_CONF")
    for PID in $CONKY_PIDS; do
        MEM_KB=$(ps -o rss= -p "$PID" | awk '{print $1}')
        MEM_MB=$((MEM_KB / 1024))
        echo "$(date) PID:$PID RAM:${MEM_MB}MB" >> /tmp/conky_ram_watchdog.log
        if (( MEM_MB > MEM_LIMIT_MB )); then
            notify-send "⚠️ Restart Conky" "conkyrc_mail PID $PID exceeded ${MEM_MB} MB RAM. Restarting..."
            kill "$PID"
        fi
    done
    sleep 5
done &
RAM_PID=$!
echo $RAM_PID > "$RAM_PID_FILE"

# --- Run Python script and check for successful start ---
echo "Starting Python script..."
notify-send "▶️ Python start" "Starting $PYTHON_SCRIPT..."

python3 "$PYTHON_SCRIPT" &
PY_PID=$!

notify-send "⏳ Waiting" "Waiting for $MAIL_CACHE to be created by Python..."

success=0
START_WAIT=$(date +%s)
for ((i=1; i<=MAX_WAIT; i++)); do
    if [ -f "$MAIL_CACHE" ]; then
        success=1
        END_WAIT=$(date +%s)
        ELAPSED=$((END_WAIT - START_WAIT))
        break
    fi
    if ! ps -p $PY_PID >/dev/null; then
        break
    fi
    if [ $i -eq 30 ]; then
        notify-send "⏳ Still waiting" "This can take longer if many mails are being fetched..."
    fi
    sleep 1
done

if [ $success -eq 1 ]; then
    notify-send "✅ Python generates cache" "python_mail_conky_lua.py created $MAIL_CACHE in ${ELAPSED} seconds."
else
    notify-send "❌ Startup error!" "$MAIL_CACHE not created – the script is not running or exited with error."
    [ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
    [ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
    pkill -f "conky.*-c $CONKY_CONF"
    kill $PY_PID 2>/dev/null
    rm -f "$LOCK_FILE"
    exit 1
fi

wait $PY_PID

# After python finishes, kill watchdogs and conky
[ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
[ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
pkill -f "conky.*-c $CONKY_CONF"
rm -f "$LOCK_FILE"

exit 0

