#!/bin/bash

# Returns 0 if game is installed
# Returns 1 if game is not installed
IsInstalled() {
  if  [ -e /palworld/PalServer.sh ] && [ -e /palworld/steamapps/appmanifest_2394010.acf ]; then
    return 0
  fi
  return 1
}

InstallServer() {

  if [ -z "${TARGET_MANIFEST_ID}" ]; then
    /home/steam/steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType linux +@sSteamCmdForcePlatformBitness 64 +force_install_dir "/palworld" +login anonymous +app_update 2394010 validate  +quit
    return
  fi

  local targetManifest
  targetManifest="${TARGET_MANIFEST_ID}"

  LogWarn "Installing Target Version: $targetManifest"
  /home/steam/steamcmd/steamcmd.sh +@sSteamCmdForcePlatformType linux +@sSteamCmdForcePlatformBitness 64 +force_install_dir "/palworld" +login anonymous +download_depot 2394010 2394012 "$targetManifest" +quit
  cp -vr "/home/steam/steamcmd/linux32/steamapps/content/app_2394010/depot_2394012/." "/palworld/"
}

# Returns 0 if Update Required
# Returns 1 if Update NOT Required
# Returns 2 if Check Failed
UpdateRequired() {
  LogAction "Checking for new update"

  #define local variables
  local CURRENT_MANIFEST LATEST_MANIFEST temp_file http_code updateAvailable

  #check steam for latest version
  temp_file=$(mktemp)
  http_code=$(curl https://api.steamcmd.net/v1/info/2394010 --output "$temp_file" --silent --location --write-out "%{http_code}")

  if [ "$http_code" -ne 200 ]; then
      LogError "There was a problem reaching the Steam api. Unable to check for updates!"
      rm "$temp_file"
      return 2
  fi

  # Parse temp file for manifest id
  LATEST_MANIFEST=$(grep -Po '"2394012".*"gid": "\d+"' <"$temp_file" | sed -r 's/.*("[0-9]+")$/\1/' | tr -d '"')
  rm "$temp_file"

  if [ -z "$LATEST_MANIFEST" ]; then
      LogError "The server response does not contain the expected BuildID. Unable to check for updates!"
      return 2
  fi

  # Parse current manifest from steam files
  CURRENT_MANIFEST=$(awk '/manifest/{count++} count==2 {print $2; exit}' /palworld/steamapps/appmanifest_2394010.acf | tr -d '"')
  LogInfo "Current Version: $CURRENT_MANIFEST"

  # Log any updates available
  local updateAvailable=false
  if [ "$CURRENT_MANIFEST" != "$LATEST_MANIFEST" ]; then
    LogInfo "An Update Is Available. Latest Version: $LATEST_MANIFEST."
    updateAvailable=true
  fi

  # No TARGET_MANIFEST_ID env set & update needed
  if [ "$updateAvailable" == true ] && [ -z "${TARGET_MANIFEST_ID}" ]; then
    return 0
  fi

  if [ -n "${TARGET_MANIFEST_ID}" ] && [ "$CURRENT_MANIFEST" != "${TARGET_MANIFEST_ID}" ]; then
    LogInfo "Game not at target version. Target Version: ${TARGET_MANIFEST_ID}"
    return 0
  fi

  # Warn if version is locked
  if [ "$updateAvailable" == false ]; then
    LogSuccess "The Server is up to date!"
    return 1
  fi

  if [ -n "${TARGET_MANIFEST_ID}" ]; then
    LogWarn "Unable to update. Locked by TARGET_MANIFEST_ID."
    return 1
  fi
}