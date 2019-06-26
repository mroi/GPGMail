PLUGIN_DIR = $(shell echo ~)/Library/Mail/Bundles
FRAMEWORK_DIR = $(shell echo ~)/Library/Components
XPC_DIR = $(FRAMEWORK_DIR)/Libmacgpg.framework/Versions/Current/XPCServices
LAUNCH_AGENT = $(shell echo ~)/Library/LaunchAgents/org.gpgtools.Libmacgpg.xpc.plist

.PHONY: all install update clean

all:
	$(MAKE) -C libmacgpg -B
	$(MAKE) -C gpgmail -B

install: all
	-launchctl bootout gui/`id -u`/org.gpgtools.Libmacgpg.xpc
	rsync -rlcv --delete \
		gpgmail/build/Release/GPGMail.mailbundle "$(PLUGIN_DIR)/"
	rsync -rlcv --delete --exclude=Versions/B/XPCServices \
		libmacgpg/build/Release/Libmacgpg.framework "$(FRAMEWORK_DIR)/"
	mkdir -p "$(XPC_DIR)" ; ln -shf Versions/Current/XPCServices "$(FRAMEWORK_DIR)/Libmacgpg.framework/"
	rsync -rlcv --delete \
		libmacgpg/build/Release/org.gpgtools.Libmacgpg.xpc "$(XPC_DIR)/"
	uuid=`/usr/libexec/PlistBuddy -c 'Print PluginCompatibilityUUID' /Applications/Mail.app/Contents/Info.plist` ; \
		fgrep -q $$uuid "$(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist" || \
		/usr/libexec/PlistBuddy -c "Add :Supported`sw_vers -productVersion | cut -d '.' -f 1,2`PluginCompatibilityUUIDs: string $$uuid" \
		"$(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist"
	codesign -s "`id -F`" --deep --force "$(PLUGIN_DIR)/GPGMail.mailbundle"
	codesign -s "`id -F`" --deep --force "$(FRAMEWORK_DIR)/Libmacgpg.framework"
	sed 's|/Library/Application Support/GPGTools|$(XPC_DIR)|' < libmacgpg/build/org.gpgtools.Libmacgpg.xpc.plist > "$(LAUNCH_AGENT)"
	launchctl bootstrap gui/`id -u` "$(LAUNCH_AGENT)"

update:
	git subtree merge --prefix=libmacgpg --squash libmacgpg/dev
	git subtree merge --prefix=gpgmail --squash gpgmail/mojave

clean:
	$(MAKE) -C gpgmail $@
	$(MAKE) -C libmacgpg $@
