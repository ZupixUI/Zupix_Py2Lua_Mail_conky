#!/bin/bash

PYTHON_SCRIPT="./py/python_mail_conky_lua.py"
RESULTS=""

# Run Python code to mark the 6 newest messages as unread for all accounts
python3 -u - <<EOF | while IFS= read -r line
import imaplib
import sys
import json
import os

# Locate the accounts.json file next to the main Python script
base_dir = os.path.dirname(os.path.dirname(os.path.abspath("$PYTHON_SCRIPT")))
config_path = os.path.join(base_dir, "config", "accounts.json")
if not os.path.exists(config_path):
    print("[NOTIFY]❗ Missing accounts file: %s" % config_path, flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)
with open(config_path, "r", encoding="utf-8") as f:
    accounts = json.load(f)
if not accounts:
    print("[NOTIFY]❗ No accounts found in accounts.json!", flush=True)
    print("PROGRESS:100", flush=True)
    sys.exit(1)

total = len(accounts)
for idx, acc in enumerate(accounts):
    try:
        with imaplib.IMAP4_SSL(acc["host"], acc["port"]) as imap:
            imap.login(acc["login"], acc["password"])
            imap.select("INBOX")
            typ, data = imap.search(None, "ALL")
            if typ != "OK":
                print(f"[NOTIFY]❗ {acc['name']}: Cannot retrieve message list!", flush=True)
                continue
            uids = data[0].split()
            if not uids:
                print(f"[NOTIFY]ℹ️ {acc['name']}: No messages in INBOX.", flush=True)
                continue
            # Take 6 newest UIDs (as in your example)
            latest_uids = uids[-6:]
            for uid in latest_uids:
                imap.store(uid, '-FLAGS', r'\\Seen')
            print(f"[NOTIFY]✅ {acc['name']}: Marked {len(latest_uids)} newest messages as unread.", flush=True)
            imap.logout()
    except Exception as e:
        print(f"[NOTIFY]❗ {acc['name']}: Problem: {e}", flush=True)
    # Show progress
    progress = int((idx + 1) / total * 100)
    print(f"PROGRESS:{progress}", flush=True)
EOF
do
    # Read progress and notification lines from Python
    if [[ "$line" == PROGRESS:* ]]; then
        pct="${line#PROGRESS:}"
        echo "$pct"
    else
        echo "$line"
        if [[ "$line" == \[NOTIFY\]* ]]; then
            msg="${line#\[NOTIFY\]}"
            icon="dialog-information"
            [[ "$msg" == *❗* ]] && icon="dialog-error"
            [[ "$msg" == *✅* ]] && icon="dialog-ok"
            [[ "$msg" == *ℹ️* ]] && icon="dialog-information"
            notify-send "Mail" "$msg" -i "$icon"
            # Prepare summary for final Zenity dialog
            summary_msg=$(echo "$msg" | sed 's/^[^a-zA-Z0-9]*//')
            RESULTS+="$summary_msg\n"
        fi
    fi
done | zenity --progress --title="Marking mails as unread" \
  --text="Marking the 6 newest messages as unread...\nPlease wait." \
  --no-cancel --auto-close

# Show final summary dialog with results
zenity --info --title="Mail marking – summary" --text="Done!\n\n$RESULTS"

