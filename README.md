GPGMail
=======

This is a modified version of the [GPGMail](https://github.com/GPGTools/GPGMail) plugin for 
Apple Mail. I found that the original comes with a number of components that I do not need 
and so cleaning up after each update became increasingly tiresome. Thus, I created my own, 
stripped down version, which just inludes
* the [GPGMail plugin](https://github.com/GPGTools/GPGMail) itself,
* the [Libmacgpg](https://github.com/GPGTools/Libmacgpg) library, and
* the [pinentry](https://github.com/matthewbauer/pinentry-mac.git) tool.

I use the `gnupg` command from [Nix](https://nixos.org), so I don’t need anything else. No 
auto-updating, no key managment UI. Just the things needed to get nice GPG integration in 
Apple Mail.

I modified the components to get a Mail plugin and an accompanying framework, which install 
in user-writable folders within the home directory. No access to system-wide directories is 
required. The plugin must then be manually enabled in Apple Mail’s preferences.

If you don’t want the hassle of building GPGMail yourself, then this project is not for you. 
I strongly urge you to consider using [the original GPGTools](https://gpgtools.org) instead 
of my custom version. It comes with on option to [financially support the original 
developers](https://gpgtools.org/faq), which I highly recommend you do.

The original licenses of the above components apply.
