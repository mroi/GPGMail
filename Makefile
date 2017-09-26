PLUGIN_DIR = $(shell echo ~)/Library/Mail/Bundles
FRAMEWORK_DIR = $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Frameworks
RESOURCE_DIR = $(FRAMEWORK_DIR)/Libmacgpg.framework/Resources

.PHONY: all install update clean

all: pinentry/Makefile
	$(MAKE) -C pinentry SUBDIRS='secmem pinentry macosx'
	$(MAKE) -C libmacgpg -B XPC_INSTALLATION_DIR=$(RESOURCE_DIR)
	$(MAKE) -C gpgmail -B GPGMail.mailbundle

pinentry/Makefile: pinentry/configure
	cd $(<D) ; ./$(<F) --enable-fallback-curses

pinentry/configure: pinentry/autogen.sh
	cd $(<D) ; ./$(<F)

install: all
	rsync -rlcv --delete --exclude=GPGMail.mailbundle/Contents/Frameworks/Libmacgpg.framework \
		gpgmail/build/Release/GPGMail.mailbundle $(PLUGIN_DIR)/
	rsync -rlcv --delete --exclude=Resources/org.gpgtools.Libmacgpg.xpc --exclude=Resources/pinentry-mac.app \
		libmacgpg/build/Release/Libmacgpg.framework $(FRAMEWORK_DIR)/
	rsync -rlcv --delete \
		libmacgpg/build/Release/org.gpgtools.Libmacgpg.xpc $(RESOURCE_DIR)/
	rsync -rlcv --delete \
		pinentry/macosx/pinentry-mac.app $(RESOURCE_DIR)/
	uuid=`defaults read /Applications/Mail.app/Contents/Info PluginCompatibilityUUID` ; \
		fgrep -q $$uuid $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info.plist || \
		defaults write $(PLUGIN_DIR)/GPGMail.mailbundle/Contents/Info Supported`sw_vers -productVersion | cut -d '.' -f 1,2`PluginCompatibilityUUIDs -array-add $$uuid
	codesign -s "`id -F`" $(RESOURCE_DIR)/pinentry-mac.app
	codesign -s "`id -F`" $(RESOURCE_DIR)/org.gpgtools.Libmacgpg.xpc -i org.gpgtools.Libmacgpg.xpc
	codesign -s "`id -F`" $(FRAMEWORK_DIR)/Libmacgpg.framework
	codesign -s "`id -F`" $(PLUGIN_DIR)/GPGMail.mailbundle
	sed 's|/Library/Application Support/GPGTools|$(RESOURCE_DIR)|' < libmacgpg/build/org.gpgtools.Libmacgpg.xpc.plist > ~/Library/LaunchAgents/org.gpgtools.Libmacgpg.xpc.plist
	-launchctl uncache gui/$$UID/org.gpgtools.Libmacgpg.xpc

update:
	git subtree merge --prefix=pinentry --squash pinentry/master
	git subtree merge --prefix=libmacgpg --squash libmacgpg/dev
	git subtree merge --prefix=gpgmail --squash gpgmail/high-sierra

clean:
	$(MAKE) -C gpgmail $@
	$(MAKE) -C libmacgpg $@ XPC_INSTALLATION_DIR=$(RESOURCE_DIR)
	$(MAKE) -C pinentry $@
