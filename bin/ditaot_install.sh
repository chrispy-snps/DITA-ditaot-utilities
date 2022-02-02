#!/bin/bash

# find latest DITA-OT version
LATEST_DITAOT_URL=$(curl -s https://www.dita-ot.org/download | egrep -o "https://github.com/.*?zip")
if [[ ! $LATEST_DITAOT_URL =~ ^https.*zip$ ]]
then
  echo "Could not find latest .zip archive at 'https://www.dita-ot.org/download'."
  exit
fi

LATEST_DITAOT_VER=$(echo $LATEST_DITAOT_URL | grep -oP 'dita-ot-[^/]+(?=\.zip)')
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
echo -e "\nExtracting..."
rm -rf "${LATEST_DITAOT_VER}"
unzip -q "${LATEST_DITAOT_VER}.zip"
rm -f ./dita-ot
ln -s "$LATEST_DITAOT_VER" ./dita-ot
rm "${LATEST_DITAOT_VER}.zip"

# install plugins, if any
IFS=$'\n'; PLUGIN_ARRAY=($DITAOT_PLUGINS_TO_INSTALL); unset IFS;
if [ ${#PLUGIN_ARRAY[@]} -gt 0 ]
then
  echo "Installing plugins..."
  for P in "${PLUGIN_ARRAY[@]}"
  do
    if [ ! -d "$P" ]
    then
      echo "Plugin '$P' not found, skipping..."
      continue
    fi
    BASENAME=$(basename -- "$P")
    FULLPATH=$(realpath -- "$P")
    rm -rf "./dita-ot/plugins/$BASENAME"
    ln -s "$FULLPATH" "dita-ot/plugins/$BASENAME"
  done
  ./dita-ot/bin/dita install
fi

echo -e "Done.\n"
./dita-ot/bin/dita --version

