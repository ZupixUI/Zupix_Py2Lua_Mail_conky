#!/bin/bash

error_exit() {
    local MSG="$1"
    local SEKCJA="$2"
    zenity --error --width=520 --text="❌ Wystąpił problem: \n\n<b>$MSG</b>\n\nSekcja skryptu: <tt>$SEKCJA</tt>\n\nJeśli nie możesz rozwiązać problemu samodzielnie, zgłoś błąd autorowi projektu."
    exit 1
}

trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

if [ -z "$BASH_VERSION" ]; then
    echo "🔄 Przełączam powłokę na bash dla kompatybilności..."
    exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_DIR="$SCRIPT_DIR/lua"
DKJSON_URL="https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
DKJSON_LOCAL="$WIDGET_DIR/dkjson.lua"

TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
for t in "${TERMINALS[@]}"; do command -v "$t" &>/dev/null && { TERM="$t"; break; }; done
[ -z "$TERM" ] && { echo "Nie znaleziono terminala!"; exit 1; }

open_in_terminal_async() {
    local CMD="$1"
    local HOLD_CMD="$CMD; echo; echo '--- Instalacja zakończona. Naciśnij Enter, aby zamknąć terminal ---'; read -p ''"
    case "$TERM" in
        gnome-terminal)
            gnome-terminal -- bash --login -c "$HOLD_CMD" &
            ;;
        xfce4-terminal)
            xfce4-terminal --hold -e "bash --login -c \"$CMD\"" &
            ;;
        konsole)
            konsole -e bash --login -c "$HOLD_CMD" &
            ;;
        tilix)
            tilix -- bash --login -c "$HOLD_CMD" &
            ;;
        mate-terminal)
            mate-terminal -- bash --login -c "$HOLD_CMD" &
            ;;
        xterm)
            xterm -e "bash --login -c '$HOLD_CMD'" &
            ;;
        *)
            $TERM -- bash --login -c "$HOLD_CMD" &
            ;;
    esac
    echo $!
}

my_info() {
    local msg="$1"
    zenity --info --width=400 --text="$msg"
}

is_pkg_installed() {
    local pkg="$1"
    if [[ "$PM" == "apt-get" ]]; then
        command -v "${pkg%%-*}" &>/dev/null || dpkg -s "$pkg" &>/dev/null
    elif [[ "$PM" == "pacman" ]]; then
        command -v "${pkg%%-*}" &>/dev/null || pacman -Q "$pkg" &>/dev/null
	elif [[ "$PM" == "dnf" ]]; then
    	command -v "${pkg%%-*}" &>/dev/null || rpm -q "$pkg" &>/dev/null
    elif [[ "$PM" == "zypper" ]]; then
        command -v "${pkg%%-*}" &>/dev/null || zypper se --installed-only "$pkg" | grep -q "$pkg"
    elif [[ "$PM" == "eopkg" ]]; then
        # Sprawdzenie czy program jest w PATH lub pakiet jest zainstalowany
        command -v "${pkg%%-*}" &>/dev/null || eopkg list-installed | grep -q "^$pkg "
    else
        command -v "${pkg%%-*}" &>/dev/null
    fi
}



# --- TRYB AWARYJNY: Zenity nie jest zainstalowane ---
if ! command -v zenity &>/dev/null; then
    if [[ "$ZENITY_INSTALLED_ONCE" == "1" ]]; then
        echo "🔁 Już próbowałem zainstalować zenity, nie otwieram więcej terminali."
        exit 1
    fi
    export ZENITY_INSTALLED_ONCE=1

    DISTRO=""
    if command -v lsb_release &>/dev/null; then
        DISTRO=$(lsb_release -is 2>/dev/null)
    fi

    if [ -z "$DISTRO" ]; then
        echo "Nie znaleziono lsb_release. Podaj swoją dystrybucję:"
        echo "1) Ubuntu/Mint/Debian"
        echo "2) Arch/Manjaro/Garuda/EndeavourOS"
        echo "3) Fedora"
        echo "4) openSUSE"
        echo "5) Solus"
        echo "6) NixOS"
        read -p "Wybierz numer: " CHOICE
        case "$CHOICE" in
            1) DISTRO="debian";;
            2) DISTRO="arch";;
            3) DISTRO="fedora";;
            4) DISTRO="opensuse";;
            5) DISTRO="solus";;
            6) DISTRO="nixos";;
            *) echo "Nieznany wybór. Przerywam."; exit 1;;
        esac
    fi

    # NORMALIZACJA DISTRO
    DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

    case "$DISTRO" in
        arch*|manjaro*|garuda*|endeavouros|artix)
            INSTALL_HINT="sudo pacman -S zenity gtk4 libadwaita"
            ;;
        linuxmint|ubuntu|debian)
            INSTALL_HINT="sudo apt-get install -y zenity"
            ;;
        fedora)
            INSTALL_HINT="sudo dnf install -y zenity"
            ;;
        opensuse*)
            INSTALL_HINT="sudo zypper install -y zenity"
            ;;
        solus)
            INSTALL_HINT="sudo eopkg install zenity"
            ;;
        nixos)
            echo "Na NixOS zainstaluj zenity przez configuration.nix"; exit 1;;
        *)
            INSTALL_HINT="sudo apt-get install -y zenity"
            ;;
    esac

    echo ""
    echo "Brakuje wymaganego programu ZENITY."
    echo "W nowym oknie terminala zostanie uruchomione polecenie:"
    echo ""
    echo "    $INSTALL_HINT"
    echo ""
    read -p "Naciśnij Enter, aby rozpocząć instalację..."

    open_in_terminal_async "$INSTALL_HINT"
    read -p "Po zakończeniu instalacji zamknij terminal i naciśnij Enter tutaj, aby kontynuować... "

    exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
    exit 0
fi


# --- Wykrywanie dystrybucji ---
if ! command -v lsb_release &>/dev/null; then
    zenity --warning --width=480 --text="❗ <b>Nie znaleziono polecenia <tt>lsb_release</tt> w systemie.</b>\n\nTo polecenie służy do automatycznego wykrywania wersji systemu Linux.\n\nW kolejnym kroku <b>musisz wybrać ręcznie swoją dystrybucję z listy</b>.\n\nJeśli nie ma jej na liście, wybierz opcję 'Brak systemu na liście'."
    [ $? -ne 0 ] && error_exit "Użytkownik anulował wybór dystrybucji lub zamknął okno ostrzeżenia." "LSB_RELEASE"
fi

DISTRO=$(lsb_release -is 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
DISTRO_LABEL="$DISTRO"

if [ "$DISTRO" = "Unknown" ]; then
  DISTRO_LABEL=$(zenity --list --radiolist \
      --title="Wybierz swoją dystrybucję Linux" \
      --width=400 --height=340 \
      --column="" --column="Dystrybucja" \
      TRUE "Fedora" FALSE "Ubuntu" FALSE "Debian" FALSE "LinuxMint" \
      FALSE "Arch" FALSE "Manjaro" FALSE "Garuda" FALSE "EndeavourOS" \
      FALSE "Artix" FALSE "openSUSE" FALSE "Solus" FALSE "NixOS" \
      FALSE "Brak systemu na liście"
  )
  DISTRO=$(echo "$DISTRO_LABEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  echo "DEBUG: ręcznie wybrany DISTRO = [$DISTRO], LABEL = [$DISTRO_LABEL]"
  echo "DBG: DISTRO=[$DISTRO], LABEL=[$DISTRO_LABEL]"
  if [ $? -ne 0 ] || [ -z "$DISTRO" ] || [ "$DISTRO" = "braksystemunaliscie" ]; then
    error_exit "Nie znaleziono polecenia lsb_release, a użytkownik nie wybrał żadnej obsługiwanej dystrybucji." "WYKRYWANIE DYSTYBUCJI"
  fi
  VERSION="0"
fi


# --- notify-send ---
DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if ! command -v notify-send &>/dev/null; then
    case "$DISTRO" in
        linuxmint|ubuntu|debian)
            PKG_NOTIFY="libnotify-bin"
            INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY"
            ;;
        fedora)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo dnf install -y $PKG_NOTIFY"
            ;;
        arch*|manjaro*|garuda*|endeavouros|artix)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo pacman -S --noconfirm $PKG_NOTIFY"
            ;;
        opensuse*|suse*)
            PKG_NOTIFY="libnotify-tools"
            INSTALL_NOTIFY="sudo zypper install -y $PKG_NOTIFY"
            ;;
        solus)
            PKG_NOTIFY="libnotify"
            INSTALL_NOTIFY="sudo eopkg install $PKG_NOTIFY"
            ;;
        nixos)
            error_exit "Na NixOS zainstaluj notify-send przez configuration.nix" "notify-send"
            ;;
        *)
            PKG_NOTIFY="libnotify-bin"
            INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY"
            ;;
    esac
    my_info "🔔 Brakuje narzędzia <b>notify-send</b>.\n\nPakiet <tt>$PKG_NOTIFY</tt> zostanie zainstalowany."
    [ $? -ne 0 ] && error_exit "Użytkownik anulował instalację notify-send." "notify-send"
    open_in_terminal_async "$INSTALL_NOTIFY"
    read -p "Po zakończeniu instalacji zamknij terminal i naciśnij Enter tutaj, aby kontynuować... "
    command -v notify-send &>/dev/null || error_exit "notify-send nadal nie jest zainstalowane." "notify-send"
fi

# Wyłączamy tymczasowo globalny trap, bo sam obsługujesz exit code zenity
trap - ERR
my_info "<big>🖥️ <b>System operacyjny:</b> $DISTRO_LABEL\n<b>Wersja:</b> $VERSION</big>\n\nSkrypt dopasuje instalację do Twojej dystrybucji."
RET=$?
if [ "$RET" -ne 0 ]; then
    zenity --info --width=520 --text="❗ <b>Przerwano instalację.</b>\n\nUżytkownik zamknął okno instalatora lub anulował wybór.\n\nSkrypt kończy działanie."
    exit 0
fi
# Przywracamy trap na błędy
trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR


# --- DEBUG: wykrywanie dystrybucji i wersji ---
if command -v notify-send &>/dev/null; then
    notify-send "DBG: DISTRO=[$DISTRO] VERSION=[$VERSION]"
fi

# --- DOBÓR PAKIETÓW DO INSTALACJI (wymuszenie małych liter na DISTRO) ---
DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
echo "DBG: DISTRO przed funkcją case=[$DISTRO]" >> /tmp/distro_dbg_przed.txt
case "$DISTRO" in
  linuxmint|"linux mint"|mint)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    MAJOR_VER=$(echo "$VERSION" | cut -d. -f1 | tr -d '[:space:]')
    echo "DBG: Wchodzę do bloku Mint. MAJOR_VER=[$MAJOR_VER]" | tee -a /tmp/distro_dbg.txt
    if [[ "$MAJOR_VER" == "22" ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.4 liblua5.4-dev)
    elif [[ "$MAJOR_VER" == "21" ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    fi
    echo "DBG: REQUIRED_PACKAGES = [${REQUIRED_PACKAGES[*]}]" | tee -a /tmp/distro_dbg.txt
    ;;
  ubuntu)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget)
    if [[ "$VERSION" =~ ^24 ]]; then
      REQUIRED_PACKAGES+=(lua5.4 liblua5.4-dev)
    else
      REQUIRED_PACKAGES+=(lua5.3 liblua5.3-dev)
    fi
    ;;
  "pop!_os"|pop|pop-os)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    if [[ "$VERSION" =~ ^22 ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    elif [[ "$VERSION" =~ ^20 ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    fi
    ;;
  zorin*)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    if [[ "$VERSION" =~ ^17 ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    elif [[ "$VERSION" =~ ^16 ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    fi
    ;;
  elementary|elementary*)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    if [[ "$VERSION" =~ ^7 ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    elif [[ "$VERSION" =~ ^6 ]]; then
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    else
      REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    fi
    ;;
  feren*|feren)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    ;;
  linuxlite|"linux lite")
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    ;;
  peppermint*|"peppermint os"|peppermintos)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    ;;
  debian)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    ;;
  fedora)
    PM="dnf"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky wget lua lua-devel)
    ;;
  arch*|manjaro*|garuda*|endeavouros|artix)
    PM="pacman"; INSTALL="sudo $PM -S --noconfirm"
    REQUIRED_PACKAGES=(conky wget lua)
    ;;
  opensuse*|suse*)
    PM="zypper"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky wget lua)
    ;;
  solus)
    PM="eopkg"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky wget lua)
    ;;
  nixos)
    my_info "ℹ️ <b>NixOS wykryty.</b>\nZainstaluj ręcznie pakiety: conky, lua, wget przez configuration.nix."
    exit 0
    ;;
  *)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    ;;
esac
echo "DEBUG po esac: DISTRO=[$DISTRO] VERSION=[$VERSION] PM=[$PM]" | tee /tmp/distro_dbg_esac.txt
# --- SPRAWDZANIE BRAKUJĄCYCH PAKIETÓW (odporny, uniwersalny blok!) ---
MISSING=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
    my_info "🔧 Zostaną zainstalowane pakiety:\n\n<tt>${MISSING[*]}</tt>\n\nZostanie otwarty terminal z instalacją."
    [ $? -ne 0 ] && error_exit "Użytkownik anulował instalację pakietów." "LISTA PAKIETÓW"
    INSTALL_CMD="$INSTALL ${MISSING[*]}"
    open_in_terminal_async "$INSTALL_CMD"
    sleep 2

    trap - ERR
    zenity --question --width=500 --text="<big><b>Czy wystąpił problem z instalacją pakietów w otwartym terminalu?</b></big>\n\nJeśli terminal zawiesił się, czeka na hasło, nic się nie instaluje lub pojawił się błąd – kliknij Tak, aby przejść do ręcznego trybu instalacji.\n\nKliknij Nie, aby kontynuować instalację automatyczną."
    answer=$?
    trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

    if [ "$answer" = "0" ]; then
        zenity --info --width=650 --text="Aby kontynuować instalację zamknij terminal, w którym polecenie sprawia problem.\n\n<b>Następnie skopiuj poniższe polecenie i uruchom w terminalu z uprawnieniami administratora:</b>\n\n<tt>$INSTALL ${MISSING[*]}</tt>\n\nPo zakończeniu ręcznej instalacji wróć tutaj i kliknij OK."
        [ $? -ne 0 ] && error_exit "Użytkownik anulował tryb ręczny instalacji." "MANUAL INSTALL"
    elif [ "$answer" = "1" ]; then
        :
    else
        error_exit "Użytkownik anulował instalację lub zamknął okno." "QUESTION DIALOG"
    fi

    # Ponowne sprawdzanie do skutku (odporny, uniwersalny blok!)
while :; do
    # Tworzymy nową listę brakujących pakietów
    MISSING_AGAIN=()
    for pkg in "${MISSING[@]}"; do
        if ! is_pkg_installed "$pkg"; then
            MISSING_AGAIN+=("$pkg")
        fi
    done
    if [ "${#MISSING_AGAIN[@]}" -eq 0 ]; then
        break  # Wszystko zainstalowane, wychodzimy z pętli
    fi

    zenity --question --width=500 --text="Następujące pakiety <b>nadal nie są zainstalowane</b>:\n\n<tt>$(printf '%s ' "${MISSING_AGAIN[@]}")</tt>\n\nCzy chcesz spróbować ponownie?\n\nKliknij Tak aby spróbować jeszcze raz, Nie aby przerwać."
    if [ $? -ne 0 ]; then
        zenity --info --width=520 --text="❗ <b>Przerwano instalację pakietów.</b>\n\nNastępujące pakiety <b>nadal nie są zainstalowane</b>:\n\n<tt>$(printf '%s ' "${MISSING_AGAIN[@]}")</tt>\n\n<b>Pamiętaj, że brak tych pakietów uniemożliwi uruchomienie widgetu.</b>\n\nSkrypt kończy działanie."
        exit 0
    fi
done
fi
    trap 'error_exit "Nieoczekiwany błąd w skrypcie!" "trap"' ERR

# --- SPRAWDZENIE CONKY/LUA I POBRANIE dkjson.lua (pozostaje bez zmian) ---
CONKY_VER=$(conky -v 2>/dev/null)
if echo "$CONKY_VER" | grep -q "Lua bindings"; then
    # Sprawdzamy wersję Lua wspieraną przez Conky
    if command -v lua5.4 &>/dev/null; then
        CONKY_LUA="5.4"
    elif command -v lua5.3 &>/dev/null; then
        CONKY_LUA="5.3"
    elif command -v lua &>/dev/null; then
        VER=$(lua -v 2>&1 | grep -oE '5\.[0-9]')
        if [ -n "$VER" ]; then
            CONKY_LUA="$VER"
        else
            CONKY_LUA="nieznana"
        fi
    elif command -v luajit &>/dev/null; then
        CONKY_LUA="luajit (5.1)"
    else
        CONKY_LUA="brak"
    fi
    HAS_LUA_IN_CONKY="yes"
else
    CONKY_LUA="brak"
    HAS_LUA_IN_CONKY="no"
fi

# Sprawdzamy wersję Lua obecnej w systemie
if command -v lua5.4 &>/dev/null; then
    SYS_LUA="5.4"
elif command -v lua5.3 &>/dev/null; then
    SYS_LUA="5.3"
elif command -v lua &>/dev/null; then
    VER=$(lua -v 2>&1 | grep -oE '5\.[0-9]')
    if [ -n "$VER" ]; then
        SYS_LUA="$VER"
    else
        SYS_LUA="nieznana"
    fi
elif command -v luajit &>/dev/null; then
    SYS_LUA="luajit (5.1)"
else
    SYS_LUA="brak"
fi

# Nowy intuicyjny blok komunikatów
if [[ "$HAS_LUA_IN_CONKY" != "yes" ]]; then
    my_info "⚠️ Conky zainstalowany w systemie NIE obsługuje Lua. Widżet mailowy nie zadziała."
    [ $? -ne 0 ] && error_exit "Użytkownik anulował komunikat o niezgodności Lua." "CHECK CONKY LUA"
elif [[ "$CONKY_LUA" == "brak" ]]; then
    my_info "⚠️ <b>Conky -v</b> nie zwraca wsparcia dla Lua. Widżet mailowy nie zadziała."
elif [[ "$CONKY_LUA" == "$SYS_LUA" ]]; then
    if [[ "$CONKY_LUA" == "nieznana" ]]; then
        my_info "ℹ️ <b>Zgodność:</b> Wykryto Lua w systemie, ale nie udało się ustalić jej wersji.\nWidżet mailowy prawdopodobnie będzie rysować się poprawnie."
    else
        my_info "✅ <b>Zgodność:</b> Conky obsługuje Lua - <b>$CONKY_LUA</b>.\nWidżet mailowy będzie rysować się poprawnie."
    fi
elif [[ "$SYS_LUA" == luajit* ]]; then
    my_info "ℹ️ <b>Zgodność:</b> W systemie wykryto LuaJIT - <b>($SYS_LUA)</b>. Widżet mailowy prawdopodobnie będzie rysować się poprawnie."
elif [[ "$SYS_LUA" == "nieznana" ]]; then
	my_info "ℹ️ <b>Uwaga:</b> Lua wykryta w systemie, ale nie udało się ustalić jej wersji.\nConky wykrywa Lua: <b>$CONKY_LUA</b>. Widżet mailowy prawdopodobnie będzie rysować się poprawnie"
elif [[ "$SYS_LUA" == "brak" ]]; then
    my_info "⚠️ <b>Brak Lua w systemie!</b> Conky oczekuje Lua: <b>$CONKY_LUA</b>"
else
    my_info "⚠️ <b>Wykryto rozbieżność:</b>\n\n<b>Conky:</b> Lua <b>$CONKY_LUA</b>\n<b>System:</b> Lua <b>$SYS_LUA</b>"
fi


check_internet() {
    ping -c1 -W1 github.com &>/dev/null || error_exit "Brak połączenia z internetem." "check_internet"
}

if [ ! -f "$DKJSON_LOCAL" ]; then
    check_internet
    mkdir -p "$WIDGET_DIR"
    if ! wget -q "$DKJSON_URL" -O "$DKJSON_LOCAL"; then
        error_exit "Błąd podczas pobierania dkjson.lua" "DKJSON.LUA (wget)"
    fi
    my_info "<big>✅ Plik dkjson.lua został pobrany!</big>\n\n📂 Lokalizacja:\n<tt>$DKJSON_LOCAL</tt>"
else
    my_info "<big>✅ dkjson.lua już istnieje.</big>\n\n📂 Lokalizacja:\n<tt>$DKJSON_LOCAL</tt>"
fi

if zenity --question --title="Sukces! 🎉" --text="<big>Skrypt wykonał swoje zadanie!\nCzy chcesz teraz uruchomić konfigurator zmiennych (2.Podmiana_wartości_w_zmiennych.sh)?</big>" --ok-label="Tak" --cancel-label="Nie"; then
    if [ -f "2.Podmiana_wartości_w_zmiennych.sh" ]; then
        bash "2.Podmiana_wartości_w_zmiennych.sh" &
        exit 0
    else
        zenity --error --text="Nie znaleziono pliku \"2.Podmiana_wartości_w_zmiennych.sh\"!"
        exit 1
    fi
else
    zenity --info --text="✅ Zakończono instalację. Możesz teraz ręcznie uruchomić skrypt: 2.Podmiana_wartości_w_zmiennych.sh"
fi

exit 0

