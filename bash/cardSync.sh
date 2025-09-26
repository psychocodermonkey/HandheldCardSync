#!/usr/bin/env bash

usage() {
    echo " "
    echo " Handheld Card Sync Tool "
    echo " [+] Sync directoreis between a rom collection drive and a handheld SD card."
    echo " "
    echo " Copyright (C) 2025  Andrew Dixon "
    echo " This program comes with ABSOLUTELY NO WARRANTY; "
    echo " See LICENSE file for details. "
    echo " "
    echo " This script uses cardSync.conf to set the directories to use for syncing between the two locations."
    echo " "
    echo "Usage: $0 [-tld]"
    echo "  Options:"
    echo "    -t      Run in test (dry run) mode: no changes are made (overrides live mode)."
    echo "    -l      Run in live mode: changes are applied to the destination."
    echo "    -d      Debug mode, dumps the config file to the screen. Can be used in conjunction with -t (test) or -l (live)."
    echo " "
    echo " See notes in the cardSync.conf for the instructions on how to set up the configuraotn file."
    echo " "
    exit 1
}

DRY_RUN=false
LIVE_RUN=false
DUMP_CONFIG=false
CONFIG_FILE="cardSync.conf"

# Verify that rsync is installed before doing anything.
command -v rsync > /dev/null 2>&1 || {
    echo -e "\n [+] !! ERROR :: 'rsync' is required but not installed. Please install it and try again."
    exit 1
}

# Parse command line arguments
while getopts ":tld?" opt; do
    # echo "Processing option: $opt with argument: $OPTARG"  # Debug
    case ${opt} in
        t ) DRY_RUN=true ;;
        l ) LIVE_RUN=true ;;
        d ) DUMP_CONFIG=true ;;
        \? ) usage ;;
        * ) usage ;; # Catch all.
    esac
done
shift $((OPTIND -1))

# Check if the mapping file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo " [+] Error: The mapping file '$CONFIG_FILE' does not exist."
  exit 1
fi

# Define rsync command prefix based on dry run or live mode
if [ "$DRY_RUN" = true ]; then
    echo "----------------------------------------------------------------------------------------------------"
    echo "| [+] Running in TEST mode!"
    echo "----------------------------------------------------------------------------------------------------"
    RSYNC_PREFIX="rsync -auvn"

elif [ "$LIVE_RUN" = true ]; then
    echo "----------------------------------------------------------------------------------------------------"
    echo "| [+] *** ATTENTION *** :: Running in LIVE mode!"
    echo "----------------------------------------------------------------------------------------------------"
    RSYNC_PREFIX="rsync -auv"

elif [ "$DUMP_CONFIG" = true ]; then
    echo "----------------------------------------------------------------------------------------------------"
    echo "| [+] *** DEBUG ONLY *** :: Dumping config file."
    echo "----------------------------------------------------------------------------------------------------"

else
    echo " [+] !! ERROR :: No mode specified. Use -t for test (dry run) -l for live, or -d to dump current config."
    usage
fi

# ---------------------------------------------------------
# Parse config file
# ---------------------------------------------------------
echo " [+] Fetching parameters..."
# Track sections and their variables
sections=()
declare -A vars_by_section
current_section=""

while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim whitespace
    line="$(echo "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Section header [section]
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        current_section="${BASH_REMATCH[1]}"
        [[ "$current_section" != "consoles" ]] && sections+=("$current_section")
        continue
    fi

    # Skip [consoles] section here
    [[ "$current_section" == "consoles" ]] && continue

    # Key=value pairs
    if [[ "$line" =~ ^([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        varname="${current_section}_${key}"
        eval "$varname=\"$value\""
        vars_by_section[$current_section]="${vars_by_section[$current_section]} $varname"
    fi
done < "$CONFIG_FILE"

# Parse [consoles] into an associative array
declare -A consoles
while read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    consoles["$key"]="$value"
done < <(awk '/\[consoles\]/ {found=1; next} /^\[/ {found=0} found' "$CONFIG_FILE")

# ---------------------------------------------------------
# Function to center text within a dashed line
# ---------------------------------------------------------
center_text() {
    local text="$1"
    local total_length=100  # Total length of the output string
    local text_length=${#text}
    local remaining=$((total_length - text_length))
    local left_padding=$((remaining / 2))
    local right_padding=$((remaining - left_padding))
    # Build padding strings of dashes
    printf '%*s' "$left_padding" '' | tr ' ' '-'
    printf "%s" "$text"
    printf '%*s\n' "$right_padding" '' | tr ' ' '-'
}

# ---------------------------------------------------------
# Debug function to dump parsed config dynamically
# ---------------------------------------------------------
dump_config() {
  center_text " Parsed Config "
  echo ""

  for section in "${sections[@]}"; do
    echo "[$section]"
    for v in ${vars_by_section[$section]}; do
      val="$(eval echo "\$$v")"
      printf "  %-10s : %s\n" "${v#${section}_}" "$val"
    done
    echo ""
  done

  # Special case: consoles array
  echo "[consoles]"
  for key in "${!consoles[@]}"; do
    echo "  $key -> ${consoles[$key]}"
  done
  center_text ""

  if [[ $DRY_RUN = false && $LIVE_RUN = false ]]; then
    exit 1
  fi
}

# ---------------------------------------------------------
# Function to build and execute rsync commands
# ---------------------------------------------------------
rsync_command() {
    local section="$1"
    local src="$2"
    local dest="$3"
    local exlist="$4"

        # Check if source and destination paths are provided
    if [[ -z "$section" || -z "$src" || -z "$dest" ]]; then
        echo "Usage: rsync_command <section> <source> <destination>"
        return 1
    fi

    # Normalize paths
    src="$(echo "$src" | sed -E 's:/+:/:g; s:(^//):/:')"
    dest="$(echo "$dest" | sed -E 's:/+:/:g; s:(^//):/:')"

    # Ensure trailing slash if it's a directory path
    [[ "$src"  != */ ]] && src="$src/"
    [[ "$dest" != */ ]] && dest="$dest/"

    # Build the rsync command based on the mode
    # local cmd="$RSYNC_PREFIX --exclude='._*' --exclude='.DS_Store'"
    local cmd="$RSYNC_PREFIX"
    if [[ -n "$exlist" ]]; then
      if [[ -f "$exlist" ]]; then
        cmd+=" --exclude-from='$exlist'"
      fi
    fi
    cmd+=" $src $dest"

    echo ""
    center_text "$section"
    echo "| [+] Syncing: $src -> $dest"
    echo "| [+] $cmd"
    echo "----------------------------------------------------------------------------------------------------"

    eval $cmd  # Execute the constructed rsync command
}

[[ "$DUMP_CONFIG" = true ]] && dump_config

# Read each line in the mapping file
for src_system in "${!consoles[@]}"; do

  # Extract source and destination from the line
  dest_system="${consoles[$src_system]}"

  echo ""
  echo ""
  center_text " Starting new system "
  echo "| [+] Source.......: $src_system"
  echo "|           -- to --"
  echo "| [+] Destination..: $dest_system"
  echo "----------------------------------------------------------------------------------------------------"

  # -- Section: ROMS
  section_description=" Syncing Roms "
  src_path="$(echo "$roms_source" | sed "s/?/$src_system/g")"
  dest_path="$(echo "$roms_dest" | sed "s/?/$dest_system/g")"
  if [[ -n $roms_exlist ]]; then
    exclude="${roms_exlist//\?/${consoles[$src_system]}}"
    rsync_command "$section_description" "$src_path" "$dest_path" "$exclude"
  else
    rsync_command "$section_description" "$src_path" "$dest_path"
  fi

  # -- Section: MEDIA
  if [[ $media_sync == "true" ]]; then
    section_description=" Syncing Media "
    src_path="$(echo "$media_source" | sed "s/?/$src_system/g")"
    dest_path="$(echo "$media_dest" | sed "s/?/$dest_system/g")"
    rsync_command "$section_description" "$src_path" "$dest_path"
  fi

  # -- Section: SAVES
  if [[ $saves_sync == "true" ]]; then
    section_description=" Syncing Saves "
    src_path="$(echo "$saves_source" | sed "s/?/$src_system/g")"
    dest_path="$(echo "$saves_dest" | sed "s/?/$dest_system/g")"
    rsync_command "$section_description" "$src_path" "$dest_path"
  fi

  # -- Section: SAVE STATES
  if [[ $states_sync == "true" ]]; then
    section_description=" Syncing Save States "
    src_path="$(echo "$states_source" | sed "s/?/$src_system/g")"
    dest_path="$(echo "$states_dest" | sed "s/?/$dest_system/g")"
    rsync_command "$section_description" "$src_path" "$dest_path"
  fi

  # -- Section: GAMELISTS
  if [[ $gamelists_sync == "true" ]]; then
    section_description=" Syncing Gamelists "
    src_path="$(echo "$gamelists_source" | sed "s/?/$src_system/g")"
    dest_path="$(echo "$roms_dest" | sed "s/?/$dest_system/g")"
    rsync_command "$section_description" "$src_path" "$dest_path"
  fi
done
