# Handheld Card Sync

This repository contains scripts designed to facilitate syncing directories between an emulator collection drive and a handheld SD card, specifically tailored for retro handheld devices. The primary focus is on syncing game ROMs but also includes options for media and gamelists where applicable.

## Table of Contents

- [Features](#features)
- [Usage](#usage)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [License](#license)

## Features

- Syncs game ROM directories from a mounted emulator drive to the SD card's root or specified system directory.
- Optionally syncs media files like screenshots and titles to designated image folders within the synced game directories.
- Supports syncing gamelists into directories named after the respective systems, preserving the structure of the source gamelists.

## Usage

To use the scripts provided in this repository, follow these steps:

1. Ensure that the source paths are configured properly in cardSync.conf in the same location as the cardSync script.
2. Run the script from the root of the SD card or specify system directories manually if configured.
3. Choose between running in test mode (`-t`) to preview changes without making any alterations, or live mode (`-l`) to execute the sync operations.

### Options

- `-t`: Runs the script in test (dry run) mode, showing what would happen without actually modifying files on the SD card.
- `-l`: Executes the sync operation as planned, making changes to the destination files and directories.

## Configuration

Configuration settings are managed through a file named `cardSync.conf`. Ensure this file is correctly formatted according to the documentation provided in the script or within the `cardSYnc.conf` file itself. Refer to the comments within the configuration for more detailed information.

### Example Configuration File (`cardSync.conf`)

```configurations/cardSync.conf
# =================================================================================================
# cardSync.conf
# Configuration file for cardSync.sh
#
# Each section defines sync rules for different data types (roms, saves, media, etc).
# Use '?' as a placeholder which will be replaced by each system name from [consoles].
# Set sync=true/false to enable or disable syncing for that section.
#
# Relatitve pathing can be used if the script resies on drive. For example, if the script and
# this configuration file reside on the card for the device in the root directory, you may
# forego absolute pathing. EX: /Volumes/sdcard/
#
# Exclusion list paths should be a path to the file ot be used. Can be global or system specific
# if the exclusion list file exists within specific directories. Exclusion lists are assumed to
# be at the destination location if a placeholder (?) is provided.
# =================================================================================================


# Roms -
## If exclusion lists are dropped into the root of the roms folder named [destination]-exlist
## The name replacement will build the filename with destination dir name in front. They can
## also be placed within the individual rom directory and the path updated to /roms/?/exlist.
[roms]
source=/path/to/source/?
dest=/path/to/destinaiton/?
exlist=/path/to/roms/?-exlist

# Save Games -
## Assumes that saves for retroarch (or other emulator) are formatted to save consistently,
## and that saves are stored by content directory. If not, you may need to adjust the paths.
[saves]
sync=true
source=/path/to/source/saves/?
dest=/path/to/saves/destinaiton/?

# Save States -
## Assumes that save states for retroarch (or other emulator) are formatted to save consistently,
## and that saves are stored by content directory. If not, you may need to adjust the paths.
[states]
sync=false
source=/path/to/source/states/?
dest=/path/to/states/destinaiton/?

# Gamelists -
## If you need to copy in gamelists from another location.
## EX: ES-DE gamelists into other EmulationStation installs.
[gamelists]
sync=true
source=/path/to/gamelists/source/?
dest=/path/to/destination/gamelists/?

# Scraped Game Media -
## Copy media from another scraped environment. If gamelist.xml files are populated with relatitive
## paths, you can copy directly from the ES-DE folder structure, or just an individual folder for
## systems that link by name matching.
[media]
sync=true
source=/path/to/source/media/?
dest=/where/to/write/?/media

# List of Systems to sync.
## List is named as [source] [destination].
## This list is what gets repalced in the paths listed above for [source] and [destination]
[consoles]
arcade arcade
mame mame
# End of file
```

## Contributing

Contributions are welcome! Feel free to reach out!

## License

This project is licensed under the GPLv3 License - see the [LICENSE](LICENSE) file for details.
