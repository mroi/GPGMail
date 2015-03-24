GPGMail
=======

This is a modified version of the [GPGMail](https://github.com/GPGTools/GPGMail) plugin for 
Apple Mail. I found that the original comes with a number of components that I do not need 
and so cleaning up after each update became increasingly tiresome. Thus, I created my own, 
stripped down version, which just inludes
* the [GPGMail plugin](https://github.com/GPGTools/GPGMail) itself,
* the [Libmacgpg](https://github.com/GPGTools/Libmacgpg) library, and
* the [pinentry](https://github.com/GPGTools/pinentry-mac) tool.

I use the `gnupg` command from [Fink](http://finkproject.org), so I don’t need anything 
else. No auto-updating, no key managment UI. Just the things needed to get nice GPG 
integration in Apple Mail.

I modified the components to get a self-contained plugin that fits my setup. This may not be for 
you. I strongly urge you to consider using [the original GPGTools](https://gpgtools.org) instead 
of my custom version.

The original licenses of the above components apply.
