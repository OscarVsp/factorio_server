export FACTORIO_VERSION 		?= stable
export PACKAGE_PATH 			?= /tmp/factorio.tar.xz
export INSTALL_PATH				?= /opt
export SERVER_SETTINGS_PATH		?= config/server-settings.json
export SERVER_WHITELIST_PATH	?= config/server_whitelist.json
export MAP_GEN_SETTINGS_PATH	?= config/map-gen-settings.json
export MAP_SETTINGS_PATH		?= config/map-settings.json


setup:
	wget https://www.factorio.com/get-download/$(FACTORIO_VERSION)/headless/linux64 -nc -O $(PACKAGE_PATH)
	cd $(INSTALL_PATH)/
	sudo tar -xvf $(PACKAGE_PATH)

	sudo chown -R $(USER):$(USER) /opt/factorio

	cd factorio/
	mkdir config

	cp data/server-settings.example.json $(SERVER_SETTINGS_PATH)
	echo '[]' >$(SERVER_WHITELIST_PATH)
	cp data/map-settings.example.json $(MAP_SETTINGS_PATH)
	cp data/map-gen-settings.example.json $(MAP_GEN_SETTINGS_PATH)