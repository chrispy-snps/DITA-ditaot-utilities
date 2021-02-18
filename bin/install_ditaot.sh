#!/bin/bash

# find latest DITA-OT version
LATEST_DITAOT_URL=`curl -s https://www.dita-ot.org/download | egrep -o "https://github.com/.*?zip"`
if [[ ! $LATEST_DITAOT_URL =~ ^https.*zip$ ]]
then
  echo "Could not find latest .zip archive at 'https://www.dita-ot.org/download'."
  exit
fi

LATEST_DITAOT_VER=`echo $LATEST_DITAOT_URL | grep -oP 'dita-ot-[^/]+(?=\.zip)'`
if [[ ! $LATEST_DITAOT_VER =~ ^dita-ot-[0-9\.]+$ ]]
then
  echo "Could not extract version from '$LATEST_DITAOT_URL'."
  exit
fi

# check if it's already installed
cd ~
if [ -d "$LATEST_DITAOT_VER" ] 
then
  while true; do
    read -p "'$LATEST_DITAOT_VER' is already installed. Reinstall? " yn
    case $yn in
      [Yy]* ) break;;
      [Nn]* ) exit;;
      * ) echo "Please answer yes or no.";;
    esac
  done
fi

# grab latest DITA-OT archive
echo -e "Downloading '$LATEST_DITAOT_URL'...\n"
rm -f "${LATEST_DITAOT_VER}.zip"
rm -f "${LATEST_DITAOT_VER}.zip.*"
wget "$LATEST_DITAOT_URL" -q --show-progress

# uncompress and create filesystem link
echo "Extracting..."
rm -rf "${LATEST_DITAOT_VER}"
unzip -q "${LATEST_DITAOT_VER}.zip"
rm -f ./dita-ot
ln -s "$LATEST_DITAOT_VER" ./dita-ot
rm "${LATEST_DITAOT_VER}.zip"

echo -e "Done.\n"
./dita-ot/bin/dita --version

