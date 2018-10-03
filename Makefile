GPGTOOLS_DIR = $(shell echo ~)/Library/Application Support/GPGTools
FRAMEWORK_DIR = $(GPGTOOLS_DIR)/GPGMail.mailbundle/Contents/Frameworks
XPC_DIR = $(FRAMEWORK_DIR)/Libmacgpg.framework/Versions/Current/XPCServices
LAUNCH_AGENT = $(shell echo ~)/Library/LaunchAgents/org.gpgtools.Libmacgpg.xpc.plist
PLUGIN_DIR = $(shell echo ~)/Library/Mail/Bundles

.PHONY: all install update clean

all:
	$(MAKE) -C libmacgpg -B
	$(MAKE) -C gpgmail -B

install: all
	-launchctl bootout gui/$$UID/org.gpgtools.Libmacgpg.xpc
	rsync -rlcv --delete --exclude=Contents/Frameworks/Libmacgpg.framework \
		gpgmail/build/Release/GPGMail.mailbundle "$(GPGTOOLS_DIR)/"
	rsync -rlcv --delete --exclude=Versions/B/XPCServices \
		libmacgpg/build/Release/Libmacgpg.framework "$(FRAMEWORK_DIR)/"
	mkdir -p "$(XPC_DIR)" ; ln -shf Versions/Current/XPCServices "$(FRAMEWORK_DIR)/Libmacgpg.framework/"
	rsync -rlcv --delete \
		libmacgpg/build/Release/org.gpgtools.Libmacgpg.xpc "$(XPC_DIR)/"
	uuid=`defaults read /Applications/Mail.app/Contents/Info PluginCompatibilityUUID` ; \
		fgrep -q $$uuid "$(GPGTOOLS_DIR)/GPGMail.mailbundle/Contents/Info.plist" || \
		defaults write "$(GPGTOOLS_DIR)/GPGMail.mailbundle/Contents/Info" Supported`sw_vers -productVersion | cut -d '.' -f 1,2`PluginCompatibilityUUIDs -array-add $$uuid
	codesign -s "`id -F`" --deep --force "$(GPGTOOLS_DIR)/GPGMail.mailbundle"
	sed 's|/Library/Application Support/GPGTools|$(XPC_DIR)|' < libmacgpg/build/org.gpgtools.Libmacgpg.xpc.plist > "$(LAUNCH_AGENT)"
	launchctl bootstrap gui/$$UID "$(LAUNCH_AGENT)"
	rsync -rlcv --delete \
		"$(GPGTOOLS_DIR)/GPGMail.mailbundle" "$(PLUGIN_DIR)/"

update:
	git subtree merge --prefix=libmacgpg --squash libmacgpg/dev
	git subtree merge --prefix=gpgmail --squash gpgmail/mojave

clean:
	$(MAKE) -C gpgmail $@
	$(MAKE) -C libmacgpg $@
