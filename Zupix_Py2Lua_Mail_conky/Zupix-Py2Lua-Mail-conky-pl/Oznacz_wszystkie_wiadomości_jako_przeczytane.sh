#!/bin/bash

PYTHON_SCRIPT="./py/python_mail_conky_lua.py"
RESULTS=""

# Uwaga: python3 -u = unbuffered output (dla pewności!)
python3 -u - <<EOF | while IFS= read -r line
import imaplib
import sys
import json
import os

# Znajdź plik accounts.json obok głównego skryptu Python
base_dir = os.path.dirname(os.path.dirname(os.path.abspath("$PYTHON_SCRIPT")))
config_path = os.path.join(base_dir, "config", "accounts.json")
if not os.path.exists(config_path):
    print("[NOTIFY]❗ Brak pliku z kontami: %s" % config_path, flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)
with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)
if not accounts:
    print("[NOTIFY]❗ Brak kont w pliku accounts.json!", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

total = len(accounts)
for idx, acc in enumerate(accounts):
    try:
        with imaplib.IMAP4_SSL(acc["host"], acc["port"]) as imap:
            imap.login(acc["login"], acc["password"])
            imap.select("INBOX")
            typ, data = imap.search(None, "UNSEEN")
            if typ != "OK":
                print(f"[NOTIFY]❗ {acc['name']}: Nie można pobrać listy maili!", flush=True)
                continue
            uids = data[0].split()
            if not uids:
                print(f"[NOTIFY]ℹ️ {acc['name']}: Brak nieprzeczytanych wiadomości.", flush=True)
                continue
            for uid in uids:
                imap.store(uid, '+FLAGS', r'\\Seen')
            print(f"[NOTIFY]✅ {acc['name']}: Oznaczono jako przeczytane: {len(uids)} wiadomości.", flush=True)
            imap.logout()
    except Exception as e:
        print(f"[NOTIFY]❗ {acc['name']}: Problem: {e}", flush=True)
    progress = int((idx + 1) / total * 100)
    print(f"PROGRESS:{progress}", flush=True)
EOF
do
    if [[ "$line" == PROGRESS:* ]]; then
        pct="${line#PROGRESS:}"
        echo "$pct"    # To leci do Zenity przez potok!
    else
        # Wykonaj notify-send i zapisz do podsumowania
        echo "$line"
        if [[ "$line" == \[NOTIFY\]* ]]; then
            msg="${line#\[NOTIFY\]}"
            icon="dialog-information"
            [[ "$msg" == *❗* ]] && icon="dialog-error"
            [[ "$msg" == *✅* ]] && icon="dialog-ok"
            [[ "$msg" == *ℹ️* ]] && icon="dialog-information"
            notify-send "Mail" "$msg" -i "$icon"
            summary_msg=$(echo "$msg" | sed 's/^[^a-zA-Z0-9]*//')
            RESULTS+="$summary_msg\n"
        fi
    fi
done | zenity --progress --title="Oznaczanie maili" \
  --text="Oznaczanie wiadomości jako przeczytane...\nProszę czekać." \
  --no-cancel --auto-close

zenity --info --title="Oznaczanie maili - podsumowanie" --text="Zakończono!\n\n$RESULTS"

