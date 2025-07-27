# -*- coding: utf-8 -*-
"""
Zupix-Py2Lua-Mail-conky – Persistent IMAP connections, multi-account
Copyright © 2025 Zupix
GPL v3+

Utrzymuje stałe sesje IMAP na każde konto, cyklicznie pobiera nowe maile, nie loguje się w kółko.
"""

import imaplib
import email
from email.header import decode_header
import quopri
import html
import json
import threading
import time
import re
import os
import sys
import socket

imaplib.IMAP4_SSL.timeout = 1  # Ustawia timeout dla nowych połączeń imaplib
socket.setdefaulttimeout(1)  # Ustawia globalny timeout na sockety

max_mails = 20  # ile maili pobierać na konto (możesz zmienić)

def load_accounts_json():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    config_path = os.path.join(base_dir, "config", "accounts.json")
    if not os.path.exists(config_path):
        print(f"Brak pliku kont: {config_path}")
        sys.exit(1)
    with open(config_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data

ACCOUNTS = load_accounts_json()

CACHE_WRITE_INTERVAL = 1  # co ile sekund generować plik cache (float, np. 0.5, 2)
UPDATE_INTERVAL = 1  # co ile sekund pobierać nowe dane dla każdego konta

# --- DEKODOWANIE I UTYLITY ---
def decode_mime_header(header):
    if not header:
        return ""
    decoded_parts = decode_header(header)
    result = ""
    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            try:
                result += part.decode(encoding or "utf-8", errors="replace")
            except Exception:
                result += part.decode("utf-8", errors="replace")
        else:
            result += part
    result = re.sub(r"[\r\n\t]+", " ", result)
    return result.strip()

def decode_quoted_printable(text):
    if not text:
        return ""
    if isinstance(text, str):
        text = text.encode("utf-8", errors="replace")
    try:
        return quopri.decodestring(text).decode("utf-8", errors="replace")
    except Exception:
        return text.decode("utf-8", errors="replace")

def decode_html_entities(text):
    return html.unescape(text or "")

def clean_html(text):
    text = re.sub(r'(?is)<head.*?>.*?</head>', '', text)
    text = re.sub(r'(?is)<style.*?>.*?</style>', '', text)
    text = re.sub(r'(?is)<script.*?>.*?</script>', '', text)
    text = re.sub(r'(?is)<!--.*?-->', '', text)
    text = re.sub(r'(?is)<meta.*?>', '', text)
    text = re.sub(r'(?i)<br\s*/?>', '\n', text)
    text = re.sub(r'(?i)</p\s*>', '\n', text)
    text = re.sub(r'(?i)</li\s*>', '\n', text)
    text = re.sub(r'(?i)</div\s*>', '\n', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = decode_html_entities(text)
    text = re.sub(r'\n\s*\n+', '\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    return text.strip()

def line_priority(line):
    l = line.lower().strip()
    powitania = [
        "dzień dobry", "witam", "cześć", "witaj", "hello", "dear", "hej", "hi"
    ]
    for pow in powitania:
        if l.startswith(pow):
            return 100
    if sum(c.isalpha() for c in line) > 10 and 15 < len(line) < 120:
        return 80
    if 10 < len(line) < 160:
        return 60
    return 10

def clean_preview(text, line_mode, sort_preview=True):
    if not text:
        return ""
    text = decode_quoted_printable(text)
    text = clean_html(text)
    lines = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        lines.append(line)
    if sort_preview:
        lines = sorted(lines, key=line_priority, reverse=True)
    if line_mode == "auto" or int(line_mode or 0) == 0:
        preview_lines = lines
    else:
        max_lines = int(line_mode or 2)
        preview_lines = lines[:max_lines]
    out = " ".join(preview_lines)
    if len(out) > 240:
        out = out[:240] + "..."
    return out

def remove_invisible_unicode(text):
    if not text:
        return ""
    invisible = (
        u"\u200b"  # Zero width space
        u"\u200c"  # Zero width non-joiner
        u"\u200d"  # Zero width joiner
        u"\u200e"  # Left-to-right mark
        u"\u200f"  # Right-to-left mark
        u"\u00a0"  # No-break space
    )
    text = re.sub(f"[{invisible}]", "", text)
    text = re.sub(r"^([ .]+)$", "", text, flags=re.MULTILINE)
    return text

def extract_sender_name(from_header):
    m = re.match(r'^"?([^"<]+)"?\s*<[^>]+>$', from_header or "")
    if m:
        return m.group(1).strip()
    return from_header or ""

def get_mail_preview(msg, line_mode, sort_preview=False):
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            disp = part.get("Content-Disposition", "")
            if ctype == "text/plain" and "attachment" not in (disp or ""):
                payload = part.get_payload(decode=True)
                charset = part.get_content_charset() or "utf-8"
                text = payload.decode(charset, errors="replace")
                return clean_preview(text, line_mode, sort_preview)
        for part in msg.walk():
            ctype = part.get_content_type()
            if ctype == "text/html":
                payload = part.get_payload(decode=True)
                charset = part.get_content_charset() or "utf-8"
                text = payload.decode(charset, errors="replace")
                return clean_preview(text, line_mode, sort_preview)
    else:
        payload = msg.get_payload(decode=True)
        charset = msg.get_content_charset() or "utf-8"
        text = payload.decode(charset, errors="replace")
        return clean_preview(text, line_mode, sort_preview)
    return "(brak podglądu)"

def get_unread_count(imap):
    typ, data = imap.search(None, "UNSEEN")
    uids = data[0].split()
    return len(uids), uids

def get_last_mails_for_account(imap, account, n=6, show_all=False, preview_lines=3, sort_preview=False):
    mails = []
    unread_count = 0
    imap.select("INBOX")
    unread_count, unread_uids = get_unread_count(imap)
    if show_all:
        typ, data = imap.search(None, "ALL")
    else:
        typ, data = imap.search(None, "UNSEEN")
    uids = data[0].split()
    if not uids:
        return unread_count, []
    uids = uids[-n:]
    for uid in reversed(uids):
        typ, msg_data = imap.fetch(uid, "(BODY.PEEK[])")
        if typ != "OK":
            continue
        raw_msg = msg_data[0][1]
        msg = email.message_from_bytes(raw_msg)
        raw_from = msg.get("From", "")
        raw_subject = msg.get("Subject", "")
        subject = decode_mime_header(raw_subject)
        from_addr = decode_mime_header(raw_from)
        from_name = extract_sender_name(from_addr)
        preview = get_mail_preview(msg, preview_lines, sort_preview)
        preview = remove_invisible_unicode(preview)
        has_attachment = False
        if msg.is_multipart():
            for part in msg.walk():
                content_disposition = part.get("Content-Disposition", "")
                if content_disposition and "attachment" in content_disposition.lower():
                    has_attachment = True
                    break
        mail_dict = {
            "from": from_addr,
            "from_name": from_name,
            "subject": subject,
            "preview": preview,
            "account": account["name"],
            "has_attachment": has_attachment
        }
        mails.append(mail_dict)
    return unread_count, mails

# --- GŁÓWNA LOGIKA POBIERANIA MAILI – WĄTEK NA KONTO ---

class AccountWorker(threading.Thread):
    def __init__(self, account, acc_idx, config):
        super().__init__()
        self.account = account
        self.acc_idx = acc_idx
        self.config = config
        self.imap = None
        self.connected = False
        self.last_error = None
        self.unread = 0
        self.mails = []
        self.daemon = True

    def connect(self):
        try:
            self.imap = imaplib.IMAP4_SSL(self.account["host"], self.account["port"])
            self.imap.login(self.account["login"], self.account["password"])
            self.connected = True
            self.last_error = None
            print(f"[{self.account['name']}] Połączono z IMAP.")
        except Exception as e:
            self.connected = False
            self.last_error = f"[Błąd konta {self.account['name']}] {e}"
            print(f"[{self.account['name']}] Błąd przy łączeniu: {e}")

    def run(self):
        import traceback
        while True:
            if self.connected:
                try:
                    print(f"[{self.account['name']}] NOOP próbuję…")
                    self.imap.noop()
                    print(f"[{self.account['name']}] NOOP OK")
                except Exception as e:
                    print(f"[{self.account['name']}] NOOP FAIL: {repr(e)}")
                    traceback.print_exc()
                    self.connected = False
                    self.last_error = f"[Błąd konta {self.account['name']}] Połączenie przerwane (NOOP): {e}"
                    try:
                        self.imap.logout()
                    except:
                        pass
                    self.imap = None

            if not self.connected:
                self.connect()
                if not self.connected:
                    self.last_error = f"[Błąd konta {self.account['name']}] Brak połączenia z internetem lub serwerem IMAP"
                    time.sleep(UPDATE_INTERVAL)
                    continue

            try:
                unread, mails = get_last_mails_for_account(
                    self.imap, self.account,
                    n=self.config["max_mails"],
                    show_all=self.config["show_all"],
                    preview_lines=self.config["preview_lines"],
                    sort_preview=self.config["sort_preview"]
                )
                for mail in mails:
                    mail["account_idx"] = self.acc_idx
                self.unread = unread
                self.mails = mails
                self.last_error = None  # <-- PO UDANYM POBRANIU ZAWSZE CZYŚĆ BŁĄD
                print(f"[{self.account['name']}] Pobranie maili OK ({self.unread} nieprzeczytanych)")
            except Exception as e:
                print(f"[{self.account['name']}] BŁĄD pobierania maili: {repr(e)}")
                traceback.print_exc()
                self.last_error = f"[Błąd konta {self.account['name']}] {e}"
                try:
                    self.imap.logout()
                except:
                    pass
                self.connected = False
                self.imap = None
            time.sleep(UPDATE_INTERVAL)



if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Mail fetcher for Conky Lua – persistent connections, multi-account")
    parser.add_argument("--max-mails", type=int, default=max_mails, help="Number of mails per account")
    parser.add_argument("--show-all", action="store_true", help="Show all mails (not only unseen)")
    parser.add_argument("--preview-lines", default=3, help="Lines in preview (number or 'auto')")
    parser.add_argument("--sort-preview", action="store_true", help="Sort preview lines by importance")
    parser.add_argument("--output", help="Output file (if not set, print to stdout)")
    parser.add_argument("--cache-interval", type=float, default=CACHE_WRITE_INTERVAL,
        help="Co ile sekund generować plik cache (domyślnie: 3)")
    args = parser.parse_args()

    config = {
        "max_mails": args.max_mails,
        "show_all": args.show_all,
        "preview_lines": args.preview_lines,
        "sort_preview": args.sort_preview
    }

    CACHE_WRITE_INTERVAL = args.cache_interval

    workers = []
    for idx, acc in enumerate(ACCOUNTS):
        worker = AccountWorker(acc, idx, config)
        worker.start()
        workers.append(worker)

    last_write = 0  # tu się ustawia raz
    while True:
        now = time.time()
        if now - last_write >= CACHE_WRITE_INTERVAL:
            all_mails = []
            total_unread = 0
            error_messages = []
            for w in workers:
                total_unread += w.unread
                all_mails.extend(w.mails)
                if w.last_error:
                    error_messages.append(w.last_error)
            result_json = json.dumps({"unread": total_unread, "mails": all_mails}, ensure_ascii=False)

            # ATOMOWY ZAPIS CACHE
            tmp_cache_file = "/tmp/mail_cache.json.tmp"
            final_cache_file = "/tmp/mail_cache.json"
            with open(tmp_cache_file, "w", encoding="utf-8") as f:
                f.write(result_json)
            os.replace(tmp_cache_file, final_cache_file)

            # ATOMOWY ZAPIS ERR
            tmp_err_file = "/tmp/mail_cache.err.tmp"
            final_err_file = "/tmp/mail_cache.err"
            with open(tmp_err_file, "w", encoding="utf-8") as f:
                if error_messages:
                    f.write("\n".join(error_messages))
                else:
                    f.write("")
            os.replace(tmp_err_file, final_err_file)

            # loguj czas utworzenia pliku cache (mtime)
            try:
                stat = os.stat(final_cache_file)
                mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(stat.st_mtime))
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Utworzono {final_cache_file} | mtime pliku: {mtime}", flush=True)
            except Exception as e:
                print(f"Błąd pobierania mtime: {e}")
            last_write = now
        time.sleep(1)  # lub mniej, według uznania (np. 0.1)

