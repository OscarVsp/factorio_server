#!/usr/bin/bash

FACTORIO_VERSION=${FACTORIO_VERSION - 'stable'}
PACKAGE_PATH=${PACKAGE_PATH-'/tmp/factorio.tar.xz'}
INSTALL_PATH=${INSTALL_PATH-'/opt'}
SERVER_SETTINGS_PATH='config/server-settings.json'
SERVER_WHITELIST_PATH='config/server_whitelist.json'
MAP_GEN_SETTINGS_PATH='config/map-gen-settings.json'
MAP_SETTINGS_PATH='config/map-settings.json'

wget https://www.factorio.com/get-download/$FACTORIO_VERSION/headless/linux64 -nc -O $PACKAGE_PATH

cd $INSTALL_PATH/
sudo tar -xvf $PACKAGE_PATH

sudo chown -R $USER:$USER /opt/factorio

cd factorio/

wget -o

cp data/server-settings.example.json $SERVER_SETTINGS_PATH
echo '[]' >$SERVER_WHITELIST_PATH
cp data/map-settings.example.json $MAP_SETTINGS_PATH
cp data/map-gen-settings.example.json $MAP_GEN_SETTINGS_PATH
