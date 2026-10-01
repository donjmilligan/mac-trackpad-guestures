APP := build/GestureKeys.app
INSTALL_DIR := /Applications

.PHONY: app run install test debug-touches clean

app:
	scripts/build-app.sh

run: app
	-pkill -x GestureKeys
	open $(APP)

install: app
	-pkill -x GestureKeys
	rm -rf $(INSTALL_DIR)/GestureKeys.app
	cp -R $(APP) $(INSTALL_DIR)/
	open $(INSTALL_DIR)/GestureKeys.app

test:
	swift run SelfTest

debug-touches: app
	$(APP)/Contents/MacOS/GestureKeys --debug-touches

clean:
	rm -rf .build build
