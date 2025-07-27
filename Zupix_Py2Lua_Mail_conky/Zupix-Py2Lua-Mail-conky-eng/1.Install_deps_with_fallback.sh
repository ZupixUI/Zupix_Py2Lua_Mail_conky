#!/bin/bash

error_exit() {
    local MSG="$1"
    local SECTION="$2"
    zenity --error --width=520 --text="❌ An error occurred: \n\n<b>$MSG</b>\n\nScript section: <tt>$SECTION</tt>\n\nIf you can't resolve the problem yourself, please report the bug to the author."
    exit 1
}

trap 'error_exit "Unexpected error in script!" "trap"' ERR

if [ -z "$BASH_VERSION" ]; then
    echo "🔄 Switching shell to bash for compatibility..."
    exec bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_DIR="$SCRIPT_DIR/lua"
DKJSON_URL="https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
DKJSON_LOCAL="$WIDGET_DIR/dkjson.lua"

TERMINALS=(gnome-terminal xfce4-terminal konsole tilix mate-terminal x-terminal-emulator xterm)
for t in "${TERMINALS[@]}"; do command -v "$t" &>/dev/null && { TERM="$t"; break; }; done
[ -z "$TERM" ] && { echo "No terminal found!"; exit 1; }

open_in_terminal_async() {
    local CMD="$1"
    local HOLD_CMD="$CMD; echo; echo '--- Installation finished. Press Enter to close terminal ---'; read -p ''"
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
        # Check if the program is in PATH or package is installed
        command -v "${pkg%%-*}" &>/dev/null || eopkg list-installed | grep -q "^$pkg "
    else
        command -v "${pkg%%-*}" &>/dev/null
    fi
}



# --- SAFE MODE: Zenity is not installed ---
if ! command -v zenity &>/dev/null; then
    if [[ "$ZENITY_INSTALLED_ONCE" == "1" ]]; then
        echo "🔁 Already tried to install zenity, not opening more terminals."
        exit 1
    fi
    export ZENITY_INSTALLED_ONCE=1

    DISTRO=""
    if command -v lsb_release &>/dev/null; then
        DISTRO=$(lsb_release -is 2>/dev/null)
    fi

    if [ -z "$DISTRO" ]; then
        echo "lsb_release not found. Please specify your distribution:"
        echo "1) Ubuntu/Mint/Debian"
        echo "2) Arch/Manjaro/Garuda/EndeavourOS"
        echo "3) Fedora"
        echo "4) openSUSE"
        echo "5) Solus"
        echo "6) NixOS"
        read -p "Choose a number: " CHOICE
        case "$CHOICE" in
            1) DISTRO="debian";;
            2) DISTRO="arch";;
            3) DISTRO="fedora";;
            4) DISTRO="opensuse";;
            5) DISTRO="solus";;
            6) DISTRO="nixos";;
            *) echo "Unknown choice. Exiting."; exit 1;;
        esac
    fi

    # NORMALIZE DISTRO
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
            echo "On NixOS, install zenity via configuration.nix"; exit 1;;
        *)
            INSTALL_HINT="sudo apt-get install -y zenity"
            ;;
    esac

    echo ""
    echo "The required program ZENITY is missing."
    echo "A new terminal window will run the following command:"
    echo ""
    echo "    $INSTALL_HINT"
    echo ""
    read -p "Press Enter to begin installation..."

    open_in_terminal_async "$INSTALL_HINT"
    read -p "After installation, close the terminal and press Enter here to continue... "

    exec env ZENITY_INSTALLED_ONCE=1 "$0" "$@"
    exit 0
fi


# --- Detect distribution ---
if ! command -v lsb_release &>/dev/null; then
    zenity --warning --width=480 --text="❗ <b>Could not find the <tt>lsb_release</tt> command in your system.</b>\n\nThis command is used for automatic detection of Linux version.\n\nIn the next step, <b>you will have to manually choose your distribution from the list</b>.\n\nIf your system is not listed, choose 'My system is not listed'."
    [ $? -ne 0 ] && error_exit "User cancelled distro selection or closed the warning window." "LSB_RELEASE"
fi

DISTRO=$(lsb_release -is 2>/dev/null || echo "Unknown")
VERSION=$(lsb_release -rs 2>/dev/null || echo "0")
DISTRO_LABEL="$DISTRO"

if [ "$DISTRO" = "Unknown" ]; then
  DISTRO_LABEL=$(zenity --list --radiolist \
      --title="Select your Linux distribution" \
      --width=400 --height=340 \
      --column="" --column="Distribution" \
      TRUE "Fedora" FALSE "Ubuntu" FALSE "Debian" FALSE "LinuxMint" \
      FALSE "Arch" FALSE "Manjaro" FALSE "Garuda" FALSE "EndeavourOS" \
      FALSE "Artix" FALSE "openSUSE" FALSE "Solus" FALSE "NixOS" \
      FALSE "My system is not listed"
  )
  DISTRO=$(echo "$DISTRO_LABEL" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  echo "DEBUG: manually selected DISTRO = [$DISTRO], LABEL = [$DISTRO_LABEL]"
  echo "DBG: DISTRO=[$DISTRO], LABEL=[$DISTRO_LABEL]"
  if [ $? -ne 0 ] || [ -z "$DISTRO" ] || [ "$DISTRO" = "mysystemisnotlisted" ]; then
    error_exit "Could not find lsb_release and the user did not select any supported distribution." "DETECTING DISTRIBUTION"
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
            error_exit "On NixOS, install notify-send via configuration.nix" "notify-send"
            ;;
        *)
            PKG_NOTIFY="libnotify-bin"
            INSTALL_NOTIFY="sudo apt-get install -y $PKG_NOTIFY"
            ;;
    esac
    my_info "🔔 The <b>notify-send</b> tool is missing.\n\nPackage <tt>$PKG_NOTIFY</tt> will be installed."
    [ $? -ne 0 ] && error_exit "User cancelled notify-send installation." "notify-send"
    open_in_terminal_async "$INSTALL_NOTIFY"
    read -p "After installation, close the terminal and press Enter here to continue... "
    command -v notify-send &>/dev/null || error_exit "notify-send is still not installed." "notify-send"
fi

# Temporarily disable the global trap, as you handle zenity exit codes yourself
trap - ERR
my_info "<big>🖥️ <b>Operating system:</b> $DISTRO_LABEL\n<b>Version:</b> $VERSION</big>\n\nThe script will adjust the installation for your distribution."
RET=$?
if [ "$RET" -ne 0 ]; then
    zenity --info --width=520 --text="❗ <b>Installation cancelled.</b>\n\nThe user closed the installer window or cancelled selection.\n\nThe script will now exit."
    exit 0
fi
# Restore trap for errors
trap 'error_exit "Unexpected error in script!" "trap"' ERR


# --- DEBUG: detect distribution and version ---
if command -v notify-send &>/dev/null; then
    notify-send "DBG: DISTRO=[$DISTRO] VERSION=[$VERSION]"
fi

# --- CHOOSE PACKAGES TO INSTALL (lowercase for DISTRO) ---
DISTRO=$(echo "$DISTRO" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
echo "DBG: DISTRO before case function=[$DISTRO]" >> /tmp/distro_dbg_przed.txt
case "$DISTRO" in
  linuxmint|"linux mint"|mint)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    MAJOR_VER=$(echo "$VERSION" | cut -d. -f1 | tr -d '[:space:]')
    echo "DBG: Entering Mint block. MAJOR_VER=[$MAJOR_VER]" | tee -a /tmp/distro_dbg.txt
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
    my_info "ℹ️ <b>NixOS detected.</b>\nInstall the following packages manually via configuration.nix: conky, lua, wget."
    exit 0
    ;;
  *)
    PM="apt-get"; INSTALL="sudo $PM install -y"
    REQUIRED_PACKAGES=(conky-all wget lua5.3 liblua5.3-dev)
    ;;
esac
echo "DEBUG after esac: DISTRO=[$DISTRO] VERSION=[$VERSION] PM=[$PM]" | tee /tmp/distro_dbg_esac.txt
# --- CHECK FOR MISSING PACKAGES (robust universal block!) ---
MISSING=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
    my_info "🔧 The following packages will be installed:\n\n<tt>${MISSING[*]}</tt>\n\nA terminal window will open for installation."
    [ $? -ne 0 ] && error_exit "User cancelled package installation." "PACKAGE LIST"
    INSTALL_CMD="$INSTALL ${MISSING[*]}"
    open_in_terminal_async "$INSTALL_CMD"
    sleep 2

    trap - ERR
    zenity --question --width=500 --text="<big><b>Did you encounter a problem installing packages in the open terminal?</b></big>\n\nIf the terminal is frozen, waiting for a password, nothing is installing or there was an error – click Yes to switch to manual installation mode.\n\nClick No to continue with automatic installation."
    answer=$?
    trap 'error_exit "Unexpected error in script!" "trap"' ERR

    if [ "$answer" = "0" ]; then
        zenity --info --width=650 --text="To continue installation, close the terminal where the command had issues.\n\n<b>Then copy and run the following command in a terminal with administrator privileges:</b>\n\n<tt>$INSTALL ${MISSING[*]}</tt>\n\nAfter manual installation is complete, return here and click OK."
        [ $? -ne 0 ] && error_exit "User cancelled manual installation mode." "MANUAL INSTALL"
    elif [ "$answer" = "1" ]; then
        :
    else
        error_exit "User cancelled installation or closed the dialog." "QUESTION DIALOG"
    fi

    # Re-checking until successful (robust universal block!)
while :; do
    # Create a new list of missing packages
    MISSING_AGAIN=()
    for pkg in "${MISSING[@]}"; do
        if ! is_pkg_installed "$pkg"; then
            MISSING_AGAIN+=("$pkg")
        fi
    done
    if [ "${#MISSING_AGAIN[@]}" -eq 0 ]; then
        break  # All installed, exit the loop
    fi

    zenity --question --width=500 --text="The following packages <b>are still missing</b>:\n\n<tt>$(printf '%s ' "${MISSING_AGAIN[@]}")</tt>\n\nDo you want to try again?\n\nClick Yes to try again, No to abort."
    if [ $? -ne 0 ]; then
        zenity --info --width=520 --text="❗ <b>Package installation aborted.</b>\n\nThe following packages <b>are still missing</b>:\n\n<tt>$(printf '%s ' "${MISSING_AGAIN[@]}")</tt>\n\n<b>Remember: missing packages will prevent the widget from working.</b>\n\nThe script will now exit."
        exit 0
    fi
done
fi
    trap 'error_exit "Unexpected error in script!" "trap"' ERR

# --- CHECK CONKY/LUA AND DOWNLOAD dkjson.lua (remains unchanged) ---
CONKY_VER=$(conky -v 2>/dev/null)
if echo "$CONKY_VER" | grep -q "Lua bindings"; then
    # Check the Lua version supported by Conky
    if command -v lua5.4 &>/dev/null; then
        CONKY_LUA="5.4"
    elif command -v lua5.3 &>/dev/null; then
        CONKY_LUA="5.3"
    elif command -v lua &>/dev/null; then
        VER=$(lua -v 2>&1 | grep -oE '5\.[0-9]')
        if [ -n "$VER" ]; then
            CONKY_LUA="$VER"
        else
            CONKY_LUA="unknown"
        fi
    elif command -v luajit &>/dev/null; then
        CONKY_LUA="luajit (5.1)"
    else
        CONKY_LUA="none"
    fi
    HAS_LUA_IN_CONKY="yes"
else
    CONKY_LUA="none"
    HAS_LUA_IN_CONKY="no"
fi

# Check the version of Lua present in the system
if command -v lua5.4 &>/dev/null; then
    SYS_LUA="5.4"
elif command -v lua5.3 &>/dev/null; then
    SYS_LUA="5.3"
elif command -v lua &>/dev/null; then
    VER=$(lua -v 2>&1 | grep -oE '5\.[0-9]')
    if [ -n "$VER" ]; then
        SYS_LUA="$VER"
    else
        SYS_LUA="unknown"
    fi
elif command -v luajit &>/dev/null; then
    SYS_LUA="luajit (5.1)"
else
    SYS_LUA="none"
fi

# New intuitive message block
if [[ "$HAS_LUA_IN_CONKY" != "yes" ]]; then
    my_info "⚠️ Conky installed on your system does NOT support Lua. The mail widget will not work."
    [ $? -ne 0 ] && error_exit "User cancelled the Lua incompatibility message." "CHECK CONKY LUA"
elif [[ "$CONKY_LUA" == "none" ]]; then
    my_info "⚠️ <b>Conky -v</b> does not report Lua support. The mail widget will not work."
elif [[ "$CONKY_LUA" == "$SYS_LUA" ]]; then
    if [[ "$CONKY_LUA" == "unknown" ]]; then
        my_info "ℹ️ <b>Compatibility:</b> Lua was detected in the system, but its version could not be determined.\nThe mail widget will probably render correctly."
    else
        my_info "✅ <b>Compatibility:</b> Conky supports Lua - <b>$CONKY_LUA</b>.\nThe mail widget will render correctly."
    fi
elif [[ "$SYS_LUA" == luajit* ]]; then
    my_info "ℹ️ <b>Compatibility:</b> LuaJIT detected in system - <b>($SYS_LUA)</b>. The mail widget will probably render correctly."
elif [[ "$SYS_LUA" == "unknown" ]]; then
    my_info "ℹ️ <b>Note:</b> Lua detected in system, but could not determine its version.\nConky detects Lua: <b>$CONKY_LUA</b>. The mail widget will probably render correctly."
elif [[ "$SYS_LUA" == "none" ]]; then
    my_info "⚠️ <b>No Lua in system!</b> Conky expects Lua: <b>$CONKY_LUA</b>"
else
    my_info "⚠️ <b>Mismatch detected:</b>\n\n<b>Conky:</b> Lua <b>$CONKY_LUA</b>\n<b>System:</b> Lua <b>$SYS_LUA</b>"
fi


check_internet() {
    ping -c1 -W1 github.com &>/dev/null || error_exit "No internet connection." "check_internet"
}

if [ ! -f "$DKJSON_LOCAL" ]; then
    check_internet
    mkdir -p "$WIDGET_DIR"
    if ! wget -q "$DKJSON_URL" -O "$DKJSON_LOCAL"; then
        error_exit "Error while downloading dkjson.lua" "DKJSON.LUA (wget)"
    fi
    my_info "<big>✅ dkjson.lua file downloaded!</big>\n\n📂 Location:\n<tt>$DKJSON_LOCAL</tt>"
else
    my_info "<big>✅ dkjson.lua already exists.</big>\n\n📂 Location:\n<tt>$DKJSON_LOCAL</tt>"
fi

if zenity --question \
    --title="Installation Complete" \
    --width=520 \
    --text="<big>✅ <b>The script has completed successfully.</b></big>\n\nWould you like to run the variable configurator now (<tt>2.Replace_values_in_variables.sh</tt>)?" \
    --ok-label="Yes" --cancel-label="No"; then

    if [ -f "2.Replace_values_in_variables.sh" ]; then
        bash "2.Replace_values_in_variables.sh" &
        exit 0
    else
        zenity --error --width=440 --text="❌ <b>The required file <tt>2.Replace_values_in_variables.sh</tt> was not found.</b>\n\nPlease ensure that the file exists in the correct directory and try again."
        exit 1
    fi

else
    zenity --info --width=500 --text="✅ <b>The installation process has finished successfully.</b>\n\nIf you wish to configure variables later, you may run <tt>2.Replace_values_in_variables.sh</tt> manually at any time."
fi


exit 0

