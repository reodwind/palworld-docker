#!/bin/bash
# shellcheck source=scripts/helper.sh
source "/home/steam/server/helper.sh"

# Helper Functions for installation & updates
# shellcheck source=scripts/install.sh"
source "/home/steam/server/install.sh"

dirExists "/palworld" || exit
isWritable "/palworld" || exit
isExecutable "/palworld" || exit

cd /palworld || exit

# Get the architecture using dpkg
architecture=$(dpkg --print-architecture)

# Get host kernel page size
kernel_page_size=$(getconf PAGESIZE)

# Check kernel page size for arm64 hosts before running steamcmdac
if [ "$architecture" == "arm64" ] && [ "$kernel_page_size" != "4096" ]; then
    LogError "Only ARM64 hosts with 4k page size is supported."
    exit 1
fi

IsInstalled
ServerInstalled=$?
if [ "$ServerInstalled" == 1 ]; then
    LogInfo "Server installation not detected."
    LogAction "Starting Installation"
    InstallServer
fi

# Update Only If Already Installed
if [ "$ServerInstalled" == 0 ] && [ "${UPDATE_ON_BOOT,,}" == true ]; then
    UpdateRequired
    IsUpdateRequired=$?
    if [ "$IsUpdateRequired" == 0 ]; then
        LogAction "Starting Update"
        InstallServer
    fi
fi

# Check if the architecture is arm64
if [ "$architecture" == "arm64" ]; then
    # create an arm64 version of ./PalServer.sh
    cp ./PalServer.sh ./PalServer-arm64.sh
    # shellcheck disable=SC2016
    sed -i 's|\("$UE_PROJECT_ROOT\/Pal\/Binaries\/Linux\/PalServer-Linux-Test" Pal "$@"\)|LD_LIBRARY_PATH=/home/steam/steamcmd/linux64:$LD_LIBRARY_PATH box64 \1|' ./PalServer-arm64.sh
    chmod +x ./PalServer-arm64.sh
    STARTCOMMAND=("./PalServer-arm64.sh")
else
    if [ "$UE4SS_ENABLED" == true ]; then
        cp ./PalServer.sh ./PalServer-UE4SS.sh
        sed -e 's|\("$UE_PROJECT_ROOT\/Pal\/Binaries\/Linux\/PalServer-Linux-Test" Pal "$@"\)|LD_PRELOAD='$UE4SSDIR'\/libUE4SS.so \1|' ./PalServer.sh > ./PalServer-UE4SS.sh
        chmod +x ./PalServer-UE4SS.sh
        STARTCOMMAND=("./PalServer-UE4SS.sh")
    else
        STARTCOMMAND=("./PalServer.sh")
    fi    
fi


#Validate Installation
if ! fileExists "${STARTCOMMAND[0]}"; then
    LogError "Server Not Installed Properly"
    exit 1
fi

isReadable "${STARTCOMMAND[0]}" || exit
isExecutable "${STARTCOMMAND[0]}" || exit

# Prepare Arguments
if [ -n "${PORT}" ]; then
    STARTCOMMAND+=("-port=${PORT}")
fi

if [ -n "${QUERY_PORT}" ]; then
    STARTCOMMAND+=("-queryport=${QUERY_PORT}")
fi

if [ "${COMMUNITY,,}" = true ]; then
    STARTCOMMAND+=("-publiclobby")
fi

if [ "${MULTITHREADING,,}" = true ]; then
    STARTCOMMAND+=("-useperfthreads" "-NoAsyncLoadingThread" "-UseMultithreadForDS")
fi

if [ "${RCON_ENABLED,,}" = true ]; then
    STARTCOMMAND+=("-rcon")
fi

if [ "${DISABLE_GENERATE_SETTINGS,,}" = true ]; then
  LogAction "GENERATING CONFIG"
  LogWarn "Env vars will not be applied due to DISABLE_GENERATE_SETTINGS being set to TRUE!"

  # shellcheck disable=SC2143
  if [ ! "$(grep -s '[^[:space:]]' /palworld/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini)" ]; then
      LogAction "GENERATING CONFIG"
      # Server will generate all ini files after first run.
      if [ "$architecture" == "arm64" ]; then
          timeout --preserve-status 15s ./PalServer-arm64.sh 1> /dev/null
      else
          timeout --preserve-status 15s ./PalServer.sh 1> /dev/null
      fi

      # Wait for shutdown
      sleep 5
      cp /palworld/DefaultPalWorldSettings.ini /palworld/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
  fi
else
  LogAction "GENERATING CONFIG"
  LogInfo "Using Env vars to create PalWorldSettings.ini"
  /home/steam/server/settings.sh || exit
fi

# Configure RCON settings
cat >/home/steam/server/rcon.yaml  <<EOL
default:
  address: "127.0.0.1:${RCON_PORT}"
  password: "${ADMIN_PASSWORD}"
EOL

LogAction "Starting Server"

echo "${STARTCOMMAND[*]}"
"${STARTCOMMAND[@]}"

exit 0
