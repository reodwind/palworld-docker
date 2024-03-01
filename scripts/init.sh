#!/bin/bash
# shellcheck source=scripts/helper.sh
source "/home/steam/server/helper.sh"

if [[ "$(id -u)" -eq 0 ]] && [[ "$(id -g)" -eq 0 ]]; then
    if [[ "${PUID}" -ne 0 ]] && [[ "${PGID}" -ne 0 ]]; then
        LogAction "EXECUTING USERMOD"
        usermod -o -u "${PUID}" steam
        groupmod -o -g "${PGID}" steam
        chown -R steam:steam /palworld /home/steam/
    else
        LogError "Running as root is not supported, please fix your PUID and PGID!"
        exit 1
    fi
elif [[ "$(id -u)" -eq 0 ]] || [[ "$(id -g)" -eq 0 ]]; then
   LogError "Running as root is not supported, please fix your user!"
   exit 1
fi

if ! [ -w "/palworld" ]; then
    LogError "/palworld is not writable."
    exit 1
fi

mkdir -p /palworld/backups

# ue4ss enabled
if [ "$UE4SS_ENABLED" == true ]; then
    if [[ "$(id -u)" -eq 0 ]]; then
        su steam -c mkdir -p $UE4SS_MODSDIR &
    else
        mkdir -p $UE4SS_MODSDIR
    fi
    if [ ! -d "$UE4SSDIR/Mods" ]; then
        ln -s $UE4SS_MODSDIR $UE4SSDIR
    fi
    sed -E -i 's/^ConsoleEnabled = 1/ConsoleEnabled  = 0/g' $UE4SSDIR/UE4SS-settings.ini
    sed -E -i 's/^GuiConsoleEnabled = 1/GuiConsoleEnabled = 0/g' $UE4SSDIR/UE4SS-settings.ini
    sed -E -i 's/^GuiConsoleVisible = 1/GuiConsoleVisible = 0/g' $UE4SSDIR/UE4SS-settings.ini
    # sed -e 's/^ModsFolderPath[ ]*=[ ]*/ModsFolderPath ="\/palworld\/Mods"/g' $UE4SSDIR/default-settings.ini >$UE4SSDIR/UE4SS-settings.ini
fi

# shellcheck disable=SC2317
term_handler() {
  DiscordMessage "Shutdown" "${DISCORD_PRE_SHUTDOWN_MESSAGE}" "in-progress"

    if ! shutdown_server; then
        # Does not save
        kill -SIGTERM "$(pidof PalServer-Linux-Test)"
    fi

    tail --pid="$killpid" -f 2>/dev/null
}

trap 'term_handler' SIGTERM

if [[ "$(id -u)" -eq 0 ]]; then
    su steam -c ./start.sh &
else
    ./start.sh &
fi
# Process ID of su
killpid="$!"
wait "$killpid"

mapfile -t backup_pids < <(pgrep backup)
if [ "${#backup_pids[@]}" -ne 0 ]; then
    LogInfo "Waiting for backup to finish"
    for pid in "${backup_pids[@]}"; do
        tail --pid="$pid" -f 2>/dev/null
    done
fi

mapfile -t restore_pids < <(pgrep restore)
if [ "${#restore_pids[@]}" -ne 0 ]; then
    LogInfo "Waiting for restore to finish"
    for pid in "${restore_pids[@]}"; do
        tail --pid="$pid" -f 2>/dev/null
    done
fi
