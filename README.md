OpenPGP for Apple Mail
======================

This is a modified version of the [GPG Suite](https://gpgtools.org) plugin for Apple Mail. I 
found that the original comes with a number of components I do not need. Thus, I created my 
own, stripped down version, which just inludes
* the OpenPGP plugin for Apple Mail (renamed to avoid confusion with 
  [the original](https://github.com/GPGTools/GPGMail)),
* the [Libmacgpg](https://github.com/GPGTools/Libmacgpg) library, and
* the [pinentry](https://github.com/matthewbauer/pinentry-mac.git) tool.

I use the `gnupg` command from [Nix](https://nixos.org), so I don’t need anything else. No 
auto-updating, no key managment UI. Just the things needed to get nice OpenPGP integration 
in Apple Mail.

I modified the components to get a Mail plugin and an accompanying framework, which install 
in user-writable folders within the home directory. No access to system-wide directories is 
required. The plugin must then be manually enabled in Apple Mail’s preferences.

If you don’t want the hassle of building the plugin yourself, then this project is not for 
you. I strongly urge you to consider using [the original GPG Suite](https://gpgtools.org) 
instead of my custom version. It comes with on option to [financially support the original 
developers](https://gpgtools.org/faq), which I highly recommend you do.

The original licenses of the above components apply.
