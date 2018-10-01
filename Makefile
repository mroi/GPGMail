PLUGIN_DIR = $(shell echo ~)/Library/Mail/Bundles
FRAMEWORK_DIR = $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Frameworks
XPC_DIR = $(FRAMEWORK_DIR)/Libmacgpg.framework/Resources
LAUNCH_AGENT = $(shell echo ~)/Library/LaunchAgents/org.gpgtools.Libmacgpg.xpc.plist

.PHONY: all install update clean

all:
	$(MAKE) -C libmacgpg -B
	$(MAKE) -C gpgmail -B

install: all
	-launchctl bootout gui/$$UID/org.gpgtools.Libmacgpg.xpc
	rsync -rlcv --delete --exclude=Contents/Frameworks/Libmacgpg.framework \
		gpgmail/build/Release/GPGMail.mailbundle "$(PLUGIN_DIR)/"
	rsync -rlcv --delete --exclude=Resources/org.gpgtools.Libmacgpg.xpc \
		libmacgpg/build/Release/Libmacgpg.framework "$(FRAMEWORK_DIR)/"
	rsync -rlcv --delete \
		libmacgpg/build/Release/org.gpgtools.Libmacgpg.xpc "$(XPC_DIR)/"
	uuid=`defaults read /Applications/Mail.app/Contents/Info PluginCompatibilityUUID` ; \
		fgrep -q $$uuid "$(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist" || { \
			cp "$(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist" . ; \
			defaults write $(PWD)/Info Supported`sw_vers -productVersion | cut -d '.' -f 1,2`PluginCompatibilityUUIDs -array-add $$uuid ; \
			plutil -convert xml1 -o "$(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist" Info.plist ; \
			rm Info.plist ; \
		}
	codesign -s "`id -F`" --deep --force "$(XPC_DIR)/org.gpgtools.Libmacgpg.xpc" -i org.gpgtools.Libmacgpg.xpc
	codesign -s "`id -F`" --deep --force "$(PLUGIN_DIR)/GPGMail.mailbundle"
	sed 's|/Library/Application Support/GPGTools|$(XPC_DIR)|' < libmacgpg/build/org.gpgtools.Libmacgpg.xpc.plist > "$(LAUNCH_AGENT)"
	launchctl bootstrap gui/$$UID "$(LAUNCH_AGENT)"

update:
	git subtree merge --prefix=libmacgpg --squash libmacgpg/dev
	git subtree merge --prefix=gpgmail --squash gpgmail/mojave

clean:
	$(MAKE) -C gpgmail $@
	$(MAKE) -C libmacgpg $@
