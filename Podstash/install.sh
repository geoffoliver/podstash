#!/bin/bash

# Install Airfoil Integration Scripts for Podstash
# This script compiles and installs the AppleScript files needed for Airfoil integration

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Installing Airfoil Integration Scripts for Podstash${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Your bundle identifier
BUNDLE_ID="me.geoffoliver.Podstash"

echo -e "${BLUE}Using bundle identifier: ${NC}${BUNDLE_ID}"
echo ""

# Create directories
echo -e "${BLUE}Creating Airfoil support directories...${NC}"
mkdir -p ~/Library/Application\ Support/Airfoil/TrackTitles
mkdir -p ~/Library/Application\ Support/Airfoil/RemoteControl

# Check if the AppleScript source files exist
if [ ! -f "$SCRIPT_DIR/TrackMetadata.applescript" ]; then
    echo -e "${RED}Error: TrackMetadata.applescript not found in $SCRIPT_DIR${NC}"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/RemoteControl.applescript" ]; then
    echo -e "${RED}Error: RemoteControl.applescript not found in $SCRIPT_DIR${NC}"
    exit 1
fi

# Compile and install track metadata script
echo -e "${BLUE}Compiling and installing track metadata script...${NC}"
osacompile -o ~/Library/Application\ Support/Airfoil/TrackTitles/${BUNDLE_ID}.scpt \
    "$SCRIPT_DIR/TrackMetadata.applescript"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Track metadata script installed${NC}"
else
    echo -e "${RED}✗ Failed to compile track metadata script${NC}"
    exit 1
fi

# Compile and install remote control script
echo -e "${BLUE}Compiling and installing remote control script...${NC}"
osacompile -o ~/Library/Application\ Support/Airfoil/RemoteControl/dacp.${BUNDLE_ID}.scpt \
    "$SCRIPT_DIR/RemoteControl.applescript"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Remote control script installed${NC}"
else
    echo -e "${RED}✗ Failed to compile remote control script${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo -e "${BLUE}Scripts installed to:${NC}"
echo "  ~/Library/Application Support/Airfoil/TrackTitles/${BUNDLE_ID}.scpt"
echo "  ~/Library/Application Support/Airfoil/RemoteControl/dacp.${BUNDLE_ID}.scpt"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Make sure Podstash is built and running"
echo "  2. Play an episode in Podstash"
echo "  3. Open Airfoil and select Podstash as the source"
echo "  4. The episode metadata and artwork should appear in Airfoil Speakers"
echo "  5. Test the playback controls!"
echo ""
