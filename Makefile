PLUGIN_DIR = $(shell echo ~)/Library/Mail/Bundles
COMPONENT_DIR = $(shell echo ~)/Library/Components
XPC_DIR = $(COMPONENT_DIR)/Libmacgpg.framework/Versions/Current/XPCServices
LAUNCH_AGENT = $(shell echo ~)/Library/LaunchAgents/org.gpgtools.Libmacgpg.xpc.plist
INSTALL_DIR = $(shell echo ~)/Library/Application Support/Mail/Plug-ins/Bundles$(PLUGIN_DIR)
INSTALL_SCRIPT = $(shell echo ~)/Desktop/install-openpgp.sh

.PHONY: all install update clean

all:
	$(MAKE) -C pinentry -B
	$(MAKE) -C libmacgpg -B
	$(MAKE) -C gpgmail -B

install: all
	-launchctl bootout gui/$$(id -u)/org.gpgtools.Libmacgpg.xpc
	# copy built components to their target locations
	rsync -rlcv --delete \
		gpgmail/build/Release/OpenPGP.mailbundle "$(PLUGIN_DIR)/"
	rsync -rlcv --delete --exclude=Versions/B/XPCServices \
		libmacgpg/build/Release/Libmacgpg.framework "$(COMPONENT_DIR)/"
	mkdir -p "$(XPC_DIR)" ; ln -shf Versions/Current/XPCServices "$(COMPONENT_DIR)/Libmacgpg.framework/"
	rsync -rlcv --delete \
		libmacgpg/build/Release/org.gpgtools.Libmacgpg.xpc "$(XPC_DIR)/"
	rsync -rlcv --delete \
		pinentry/build/Release/pinentry-mac.app "$(COMPONENT_DIR)/"
	# add compatibility UUIDs to OpenPGP plugin
	uuid=$$(/usr/libexec/PlistBuddy -c 'Print PluginCompatibilityUUID' /System/Applications/Mail.app/Contents/Info.plist) ; \
	if ! fgrep -q $$uuid "$(PLUGIN_DIR)/OpenPGP.mailbundle/Contents/Info.plist" ; then \
		major=$$(sw_vers -productVersion | cut -d '.' -f 1) ; \
		for minor in 0 1 2 3 4 5 6 7 8 9 ; do \
			/usr/libexec/PlistBuddy -c "Add :Supported$${major}.$${minor}PluginCompatibilityUUIDs array" "$(PLUGIN_DIR)/OpenPGP.mailbundle/Contents/Info.plist" ; \
			/usr/libexec/PlistBuddy -c "Add :Supported$${major}.$${minor}PluginCompatibilityUUIDs: string $$uuid" "$(PLUGIN_DIR)/OpenPGP.mailbundle/Contents/Info.plist" ; \
		done ; \
	fi
	# codesign with custom user cert
	codesign -s "$$(id -F)" --deep --force "$(PLUGIN_DIR)/OpenPGP.mailbundle"
	codesign -s "$$(id -F)" --deep --force "$(COMPONENT_DIR)/Libmacgpg.framework"
	codesign -s "$$(id -F)" --deep --force "$(COMPONENT_DIR)/pinentry-mac.app"
	# setup launch agent and pinentry
	sed 's|/Library/Application Support/GPGTools|$(XPC_DIR)|' < libmacgpg/build/org.gpgtools.Libmacgpg.xpc.plist > "$(LAUNCH_AGENT)"
	launchctl bootstrap gui/$$(id -u) "$(LAUNCH_AGENT)"
	echo 'pinentry-program $(COMPONENT_DIR)/pinentry-mac.app/Contents/MacOS/pinentry-mac' > ~/.gnupg/gpg-agent.conf
	# write script to circumvent missing notarization
	cdhash=$$(codesign -dvvv $(PLUGIN_DIR)/OpenPGP.mailbundle 2>&1 | sed -n '/^CDHash=/{s/^CDHash=//;p;}') ; \
	sysvol=/Volumes/$$(diskutil info / | sed -n '/Volume Name/{s/[^:]*: *//;p;}') ; \
	datavol=/Volumes/$$(diskutil info /System/Volumes/Data | sed -n '/Volume Name/{s/[^:]*: *//;p;}') ; \
	printf "#!/bin/sh\nset -x\n\"$${sysvol}/usr/bin/sqlite3\" \"$${datavol}/private/var/db/SystemPolicyConfiguration/ExecPolicy\" \"INSERT INTO old_platform_cache VALUES ('7667712-$${cdhash}', $$(date +%s));\"\nrm -rf \"$${datavol}$(INSTALL_DIR)/OpenPGP.mailbundle\"\ncp -Rp \"$${datavol}$(PLUGIN_DIR)/OpenPGP.mailbundle\" \"$${datavol}$(INSTALL_DIR)/\"\nrm \"$${datavol}$(INSTALL_SCRIPT)\"\nset +x\n" > $(INSTALL_SCRIPT)
	@echo '** run $(INSTALL_SCRIPT) from recovery mode to install un-notarized plugin **'

update:
	git subtree merge --prefix=pinentry --squash pinentry/master
	git subtree merge --prefix=libmacgpg --squash libmacgpg/dev
	git subtree merge --prefix=gpgmail gpgmail

clean:
	$(MAKE) -C gpgmail $@
	$(MAKE) -C libmacgpg $@
	$(MAKE) -C pinentry $@
