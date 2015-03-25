PLUGIN_DIR = $(shell echo ~)/Library/Mail/Bundles
FRAMEWORK_DIR = $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Frameworks
RESOURCE_DIR = $(FRAMEWORK_DIR)/Libmacgpg.framework/Resources

.PHONY: all install update clean

all:
	$(MAKE) -C pinentry -B all
	$(MAKE) -C libmacgpg -B all XPC_INSTALLATION_DIR=$(RESOURCE_DIR)
	$(MAKE) -C gpgmail -B GPGMail.mailbundle

install: all
	rsync -rlcv --delete --exclude=GPGMail.mailbundle/Contents/Frameworks/Libmacgpg.framework \
		gpgmail/build/Release/GPGMail.mailbundle $(PLUGIN_DIR)/
	rsync -rlcv --delete --exclude=Resources/org.gpgtools.Libmacgpg.xpc --exclude=Resources/pinentry-mac.app \
		libmacgpg/build/Release/Libmacgpg.framework $(FRAMEWORK_DIR)/
	rsync -rlcv --delete \
		libmacgpg/build/Release/org.gpgtools.Libmacgpg.xpc $(RESOURCE_DIR)/
	rsync -rlcv --delete \
		pinentry/build/Release/pinentry-mac.app $(RESOURCE_DIR)/
	uuid=`defaults read /Applications/Mail.app/Contents/Info PluginCompatibilityUUID` ; \
		fgrep -q $$uuid $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist || \
		defaults write $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info SupportedPluginCompatibilityUUIDs -array-add $$uuid
	sed 's|/Library/Application Support/GPGTools|$(RESOURCE_DIR)|' < libmacgpg/build/org.gpgtools.Libmacgpg.xpc.plist > ~/Library/LaunchAgents/org.gpgtools.Libmacgpg.xpc.plist
	launchctl uncache gui/$$UID/org.gpgtools.Libmacgpg.xpc

update:
	git subtree merge --prefix=gpgmail --squash gpgmail/dev
	git subtree merge --prefix=libmacgpg --squash libmacgpg/dev
	git subtree merge --prefix=pinentry --squash pinentry/master

clean:
	$(MAKE) -C gpgmail $@
	$(MAKE) -C libmacgpg $@ XPC_INSTALLATION_DIR=$(RESOURCE_DIR)
	$(MAKE) -C pinentry $@
