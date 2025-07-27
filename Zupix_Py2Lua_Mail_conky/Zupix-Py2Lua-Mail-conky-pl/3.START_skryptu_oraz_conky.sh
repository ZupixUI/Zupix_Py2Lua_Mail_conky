#!/bin/bash

cd "$(dirname "$(readlink -f "$0")")"

LOCK_FILE="/tmp/loop_script.lock"
CONKY_CONF="conkyrc_mail"
PYTHON_SCRIPT="./py/python_mail_conky_lua.py"
MAIL_CACHE="/tmp/mail_cache.json"
MAX_WAIT=60  # ile sekund czekać na pojawienie się cache

RESPAWN_PID_FILE="/tmp/respawn_conky.pid"
RAM_PID_FILE="/tmp/ram_watchdog.pid"

exec 200>"$LOCK_FILE"
flock -n 200 || {
    notify-send "ℹ️ Już działa" "Skrypt jest już uruchomiony w tle. Druga instancja nie wystartuje."
    if command -v zenity >/dev/null 2>&1; then
        zenity --question \
            --title="Conky Mail – już działa!" \
            --text="<big><big><b>Zupix_Py2Lua_Mail_conky</b> już działa w tle!</big></big>\n\nCzy chcesz wyczyścić blokadę i zamknąć WSZYSTKIE powiązane z nim procesy?\n\n(Zabite zostanie okno <b>conky</b>, skrypt - <b>python_mail_conky_lua.py</b> oraz cache - <b>/tmp/mail_cache.json</b> + inne pliki tymczasowe.)"
if [ $? -eq 0 ]; then
    # Najpierw zabij watchdogi! 
    if [ -f "$RESPAWN_PID_FILE" ]; then
        kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null
        rm -f "$RESPAWN_PID_FILE"
    fi
    if [ -f "$RAM_PID_FILE" ]; then
        kill $(cat "$RAM_PID_FILE") 2>/dev/null
        rm -f "$RAM_PID_FILE"
    fi
    sleep 0.01  # Opcjonalny, krótki sleep na zamknięcie pętli
    
    # Dopiero TERAZ zabij Conky (i teraz już nie odpali się nowy)
    CONKY_PID=$(pgrep -f "conky.*-c $CONKY_CONF")
    if [ -n "$CONKY_PID" ]; then
        kill $CONKY_PID 2>/dev/null
    fi
            # Usuń plik blokady i flagi pierwszego uruchomienia
            rm -f "$LOCK_FILE"
            rm -f /tmp/mail_sound_played
			rm -f /tmp/mail_cache.err
			rm -f /tmp/mail_cache.json
            # Ubij powiązane pythony
            PIDS=$(pgrep -f "python3.*${PYTHON_SCRIPT}")
            if [ -n "$PIDS" ]; then
                kill $PIDS 2>/dev/null
            fi
            notify-send "✅ Wszystko wyłączone" "Procesy conky/py zostały zakończone, blokada usunięta."
            # Zapytaj o restart skryptu
            zenity --question \
                --title="Restart Conky Mail" \
                --text="Czy chcesz ponownie uruchomić skrypt 3.START_skryptu_oraz_conky.sh?"
            if [ $? -eq 0 ]; then
                notify-send "🔁 Restartuję!" "Ponownie uruchamiam 3.START_skryptu_oraz_conky.sh"
                exec "$0"
            else
                notify-send "🛑 Zakończono" "Nie uruchamiam ponownie. Wszystko zamknięte."
                exit 0
            fi
        fi
    fi
    exit 1
}

if [ ! -f "$PYTHON_SCRIPT" ]; then
    notify-send "❗ Brak pliku" "Nie znaleziono pliku $PYTHON_SCRIPT. Skrypt zostaje zakończony."
    echo "Nie znaleziono pliku $PYTHON_SCRIPT. Kończę działanie."
    exit 1
fi

MEM_LIMIT_MB=299

# --- Watchdog natychmiastowy respawn Conky jako luźna pętla ---
while true; do
    if ! pgrep -u "$USER" -f "conky.*-c $CONKY_CONF" >/dev/null; then
        conky -c "$CONKY_CONF" &
    fi
    sleep 0.15
done &
RESPAWN_PID=$!
echo $RESPAWN_PID > "$RESPAWN_PID_FILE"

# --- Watchdog RAM jako luźna pętla ---
while true; do
    CONKY_PIDS=$(pgrep -u "$USER" -f "conky.*-c $CONKY_CONF")
    for PID in $CONKY_PIDS; do
        MEM_KB=$(ps -o rss= -p "$PID" | awk '{print $1}')
        MEM_MB=$((MEM_KB / 1024))
        echo "$(date) PID:$PID RAM:${MEM_MB}MB" >> /tmp/conky_ram_watchdog.log
        if (( MEM_MB > MEM_LIMIT_MB )); then
            notify-send "⚠️ Restart Conky" "conkyrc_mail PID $PID przekroczył ${MEM_MB} MB RAM. Restartuję..."
            kill "$PID"
        fi
    done
    sleep 5
done &
RAM_PID=$!
echo $RAM_PID > "$RAM_PID_FILE"

# --- Uruchamianie skryptu Python i detekcja poprawnego startu ---
echo "Uruchamiam skrypt Pythona..."
notify-send "▶️ Start Pythona" "Uruchamiam $PYTHON_SCRIPT..."

python3 "$PYTHON_SCRIPT" &
PY_PID=$!

notify-send "⏳ Oczekiwanie" "Czekam na utworzenie $MAIL_CACHE przez Pythona..."

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
        notify-send "⏳ Nadal czekam" "To może potrwać dłużej jeśli pobieranych jest dużo maili..."
    fi
    sleep 1
done

if [ $success -eq 1 ]; then
    notify-send "✅ Python generuje cache" "Skrypt python_mail_conky_lua.py utworzył $MAIL_CACHE w ${ELAPSED}sek."
else
    notify-send "❌ Błąd uruchamiania!" "Nie utworzono $MAIL_CACHE – skrypt nie działa lub zakończył się błędem."
    [ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
    [ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
    pkill -f "conky.*-c $CONKY_CONF"
    kill $PY_PID 2>/dev/null
    rm -f "$LOCK_FILE"
    exit 1
fi

wait $PY_PID

# Po zakończeniu pythona ubijaj watchdogi i conky
[ -f "$RESPAWN_PID_FILE" ] && kill $(cat "$RESPAWN_PID_FILE") 2>/dev/null && rm -f "$RESPAWN_PID_FILE"
[ -f "$RAM_PID_FILE" ] && kill $(cat "$RAM_PID_FILE") 2>/dev/null && rm -f "$RAM_PID_FILE"
pkill -f "conky.*-c $CONKY_CONF"
rm -f "$LOCK_FILE"

exit 0

