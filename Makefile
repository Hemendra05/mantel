NAV     ?= Pulse
CONFIG  ?= release
SIGN_ID ?= MyNavbarsLocalDev
DEST    ?= $(HOME)/Applications

SRC  := navbars/$(NAV)
APP  := $(SRC)/.build/$(NAV).app
BIN  := $(SRC)/.build/$(CONFIG)/$(NAV)

.PHONY: all build bundle run stop install uninstall clean list dr glyph dump \
        login-on login-off login-status panel

all: bundle

build:
	@cd $(SRC) && swift build -c $(CONFIG)

bundle: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/$(NAV)
	@cp $(SRC)/Info.plist $(APP)/Contents/Info.plist
	@codesign --force -s $(SIGN_ID) $(APP) 2>/dev/null \
	  || { echo "signing failed; run tools/make-signing-cert.sh"; exit 1; }
	@echo "built $(APP)"

run: stop bundle
	@open $(APP)
	@echo "running $(NAV) (make stop to quit)"

stop:
	@pkill -x $(NAV) 2>/dev/null || true

install: bundle
	@mkdir -p $(DEST)
	@rm -rf $(DEST)/$(NAV).app
	@cp -R $(APP) $(DEST)/$(NAV).app
	@echo "installed $(DEST)/$(NAV).app"

# Sequenced in the body: login-off execs the binary that stop/rm then remove,
# so these must not run concurrently under -j.
uninstall:
	@$(MAKE) login-off
	@$(MAKE) stop
	@rm -rf $(DEST)/$(NAV).app

# Login items must point at the installed copy, never .build.
login-on: install
	@$(DEST)/$(NAV).app/Contents/MacOS/$(NAV) --login on

login-off:
	@test -x $(DEST)/$(NAV).app/Contents/MacOS/$(NAV) \
	  && $(DEST)/$(NAV).app/Contents/MacOS/$(NAV) --login off || true

login-status:
	@test -x $(DEST)/$(NAV).app/Contents/MacOS/$(NAV) \
	  && $(DEST)/$(NAV).app/Contents/MacOS/$(NAV) --login status \
	  || echo "$(NAV) not installed in $(DEST)"

# TCC grants survive rebuilds only while this stays identical between builds.
# Reads the existing bundle; run `make bundle` first if it is stale.
dr:
	@codesign -d -r- $(APP) 2>/dev/null | grep "designated =>"

glyph: build
	@$(BIN) --glyph /tmp/$(NAV)-glyph.png

dump: build
	@$(BIN) --dump

clean:
	@rm -rf $(SRC)/.build

list:
	@ls -1 navbars

panel: build
	@$(BIN) --panel /tmp/$(NAV)-panel.png
