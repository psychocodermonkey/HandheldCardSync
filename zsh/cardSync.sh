#!/usr/bin/env zsh

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
SYNC_STAGES=0
FOOTER_SIZE=2

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
if [ ! -f $CONFIG_FILE ]; then
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
typeset -a sections
typeset -A vars_by_section
current_section=""
while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace
    line="${${line##[[:space:]]}%%[[:space:]]}"

    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Section header [section]
    if [[ "$line" =~ '^\[(.*)\]$' ]]; then
        current_section="${match[1]}"
        # Only track non-consoles sections
        [[ "$current_section" != "consoles" ]] && ((SYNC_STAGES++))
        [[ "$current_section" != "consoles" ]] && sections+="$current_section"
        continue
    fi

    # Skip [consoles] section here
    [[ "$current_section" == "consoles" ]] && continue

    # Key=value pairs
    if [[ "$line" =~ '^([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$' ]]; then
        key="${match[1]}"
        value="${match[2]}"

        # If not syncing the section, remove it from counted stages.
        [[ "$key" == "sync" && "$value" == "false" ]] && ((SYNC_STAGES--))

        # Build variable name section_key
        varname="${current_section}_${key}"
        typeset -g "$varname=$value"

        # Track this variable under its section
        vars_by_section[$current_section]+=" $varname"
    fi
done < "$CONFIG_FILE"

# Parse [consoles] into an associative array
typeset -A consoles
while read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    consoles["$key"]="$value"
done < <(awk '/\[consoles\]/ {found=1; next} /^\[/ {found=0} found' "$CONFIG_FILE")

# ---------------------------------------------------------
# Update the window variables
# ---------------------------------------------------------
update_dimensions() {
  # Update lines and column variables.
  LINES=$(tput lines)
  COLUMNS=$(tput cols)
}

update_dimensions

# ---------------------------------------------------------
# Function to initilize terminal for display.
# ---------------------------------------------------------
init-term() {
  # Make room for footer no matter where we are at on the screen.
  local i
  for i in {1..$FOOTER_SIZE}; do
    printf "\n"
  done

  printf "\e7"                                         # Save curser location.
  printf "\e[%d;%dr" 0 "$((LINES - FOOTER_SIZE))"      # Set scrollable region.
  printf "\e8"                                         # Restore cursor location.
  printf "\e[%dA" "$((FOOTER_SIZE))"                   # Move cursor up the same number of new-lines we made room for.
  printf "\e[?25l"                                     # Hide the cursor
}

# ---------------------------------------------------------
# Put the terminal back the way we found it.
# ---------------------------------------------------------
deinit-term() {
  local i
  printf "\e7"                                        # Save cursor location.
  printf "\e[%d;%dr" 0 "$((LINES))"                   # Reset scrollable region to full screen.
  printf "\e[%d;%dH" "$((LINES - FOOTER_SIZE))" 0     # Move cursor to top of footer
  for i in {1..$FOOTER_SIZE}; do                      # Clear all lines in footer.
    printf "\e[0K"
  done
  printf "\e8"                                        # Put cursor back where we found it.
  printf "\e[?25h"                                    # Show cursor again.
}

# ---------------------------------------------------------
# Build and print a simple text progress bar at the bottom.
# ---------------------------------------------------------
progress_bar() {
  local source_sys=$1
  local dest_sys=$2
  local current=$3

  # Calculate progress
  local len=$((SYNC_STAGES * ${#consoles[@]}))
  local perc_done=$((current * 100 / len))
  local bar_len=$((COLUMNS - 7))                          # Use terminal columns to set the length of the progress bar less room for [] ###%.
  local num_bars=$((perc_done * bar_len / 100))           # Determine how long the bar needs to be.

  printf "\e7"                                            # Move cursor to home position.
  printf "\e[%d;%dH" "$((LINES - FOOTER_SIZE + 1))" 0         # Move cursor to the correct position for the "Syncing:" line
  printf "\e[0K"                                          # Clear the line from the current position to the end of the line.
  printf "[+] Syncing: %s --> %s" "$source_sys" "$dest_sys"
  printf "\e[%d;%dH" "$((LINES - FOOTER_SIZE + 2))" 0     # Move cursor to the correct position for the progress bar
  local bar="["
  for ((i = 0; i < num_bars; i++)); do
    bar+="█"
  done
  for ((i = num_bars; i < bar_len; i++)); do
    bar+="."
  done
  bar+="] $perc_done%"

  printf "%s" "$bar"                                   # Print the progress section.
  printf "\e8"                                         # Put cursor back where we found it.
}

# Start messing with terminal
trap deinit-term EXIT
trap "update_dimensions; init-term" WINCH
init-term

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
    local left_pad=$(printf '%*s' $left_padding '' | tr ' ' '-')
    local right_pad=$(printf '%*s' $right_padding '' | tr ' ' '-')

    echo "${left_pad}${text}${right_pad}"
}

# ---------------------------------------------------------
# Debug function to dump parsed config dynamically
# ---------------------------------------------------------
dump_config() {
  center_text " Parsed Config "
  echo ""

  for section in $sections; do
    echo "[$section]"
    for v in ${(z)vars_by_section[$section]}; do
      val="${(P)v}"
      printf "  %-10s : %s\n" "${v#${section}_}" "$val"
    done
    echo ""
  done

  # Special case: consoles array
  echo "[consoles]"
  for key in ${(k)consoles}; do
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
    [[ "$src" != */ ]] && src="$src/"
    [[ "$dest" != */ ]] && dest="$dest/"

    # Build the rsync command based on the mode
    # local cmd="$RSYNC_PREFIX --exclude='._*' --exclude='.DS_Store'"
    local cmd="$RSYNC_PREFIX"
    # Check if a exclusion list pattern was passed and make sure it exists.
    if [[ -n $exlist ]]; then
      if [[ -f $exlist ]]; then
        cmd+=" --exclude-from='$exlist'"
      fi
    fi
    cmd+=" $src $dest"

    eval $cmd  # Execute the constructed rsync command
}

main() {
  [[ "$DUMP_CONFIG" = true ]] && dump_config

  local current=0

  # Read each line in the mapping file
  for src_system in ${(k)consoles}; do

    # Extract source and destination from the line
    dest_system=${consoles[$src_system]}

    # -- Section: ROMS
    section_description=" Syncing Roms "
    ((current++))
    src_path="${roms_source//\?/${(Q)src_system}}"
    dest_path="${roms_dest//\?/${consoles[$src_system]}}"
    progress_bar "$src_system" "$dest_system" "$current"
    if [[ -n $roms_exlist ]]; then
      exclude="${roms_exlist//\?/${consoles[$src_system]}}"
      rsync_command "$section_description" "$src_path" "$dest_path" "$exclude"
    else
      rsync_command "$section_description" "$src_path" "$dest_path"
    fi

    # -- Section: MEDIA
    if [[ $media_sync == "true" ]]; then
      section_description=" Syncing Media "
      ((current++))
      src_path="${media_source//\?/${(Q)src_system}}"
      dest_path="${media_dest//\?/${consoles[$src_system]}}"
      progress_bar "$src_system" "$dest_system" "$current"
      rsync_command "$section_description" "$src_path" "$dest_path"
    fi

    # -- Section: SAVES
    if [[ $saves_sync == "true" ]]; then
      section_description=" Syncing Saves "
      ((current++))
      src_path="${saves_source//\?/${(Q)src_system}}"
      dest_path="${saves_dest//\?/${consoles[$src_system]}}"
      progress_bar "$src_system" "$dest_system" "$current"
      rsync_command "$section_description" "$src_path" "$dest_path"
    fi

    # -- Section: SAVE STATES
    if [[ $states_sync == "true" ]]; then
      section_description=" Syncing Save States "
      ((current++))
      src_path="${states_source//\?/${(Q)src_system}}"
      dest_path="${states_dest//\?/${consoles[$src_system]}}"
      progress_bar "$src_system" "$dest_system" "$current"
      rsync_command "$section_description" "$src_path" "$dest_path"
    fi

    # -- Section: GAMELISTS
    if [[ $gamelists_sync == "true" ]]; then
      section_description=" Syncing Gamelists "
      ((current++))
      src_path="${gamelists_source//\?/${(Q)src_system}}"
      dest_path="${roms_dest//\?/${consoles[$src_system]}}"
      progress_bar "$src_system" "$dest_system" "$current"
      rsync_command "$section_description" "$src_path" "$dest_path"
    fi
  done
}

main
