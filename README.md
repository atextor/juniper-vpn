Juniper VPN - Juniper Network Connection Client Connection Script
=================================================================

Sets up and connects to Juniper VPNs with Two-Phase-Authentication on 64 Bit Linux systems.

Juniper provides a Linux client for their VPN, which works out of the box on 32 bit systems, and as long as the VPN server is set up to use One-Phase-Auth only.
Workarounds and custom solutions can be found online, many of which require fiddling. This script should make the VPN work with as little tinkering required as possible.

Other solutions:
 * [Official Juniper Tutorial](http://kb.juniper.net/InfoCenter/index?page=content&id=KB25230)
 * [MadScientist JNC Session Manager](http://mad-scientist.us/juniper.html)
 * [jnc](http://www.scc.kit.edu/scc/net/juniper-vpn/linux/)
 * [Arch Wiki with various other workarounds](https://wiki.archlinux.org/index.php/Juniper_VPN)
 * [Ubuntu Forum Thread](http://ubuntuforums.org/showthread.php?t=232607)

Features
--------

* Works on 64 Bit Linux Systems
* No manual installation of 32 Bit Firefox and/or JRE/JDK required
* No manual downloading/installing of host certificates required
* Works with Two-Phase-Authentication setups (where not only username/password are required, but the Session ID from the login page as well)
* No need to visit the VPN login page at all
* Stores credentials in keyring, not plain text files
* Uses sudo/gksu to run the connection client, not a root password or setuid
* Integrated setup wizard

Installation and Usage
----------------------

Install the required dependencies. For Ubuntu, run the following:

	sudo apt-get install zenity phantomjs xterm libsecret-tools sudo gksu alien openssl tar gcc-multilib

Then, run the script `login.sh`.

On first run, the tool will ask for the location of the Juniper Network
Connect Client RPM file (ncui-6.5R9.i386.rpm). Ask the administrators of
the VPN for this file. You will also be asked for your credentials, these
will be stored in the keyring, i.e., you won’t have to enter them again.

On all subsequent runs, the tool will connect to the VPN. After the login,
an xterm window will appear that hosts the VPN process. Close the xterm
to close the VPN.

How does it work
----------------

In short: The RPM is extracted using `alien` and the client library is installed
in the correct location. The client binary contained in the package provided by
Juniper has no option for the user to provide the session ID (DSID), which is
required for VPNs with Two-Phase-Authentication. Therefore, the client library
is linked into a new client binary. Openssl is used to fetch the host
certificate. When connecting, a session is acquired by logging in to the VPN
website in a virtual, script-controlled browser via
[phantomjs](http://phantomjs.org). This also recognizes if a session already
exists and in this case, takes over the session. The virtual browser retrieves
the DSID from the page cookies and the script retrieves the credentials from
the keyring. Sudo/gksu is used to launch the previously linked connect client
using the credentials, the host certificate and the DSID and voilà - you’re
connected to the VPN.

FAQ
---

* Q: How can I reset my credentials? A: If you wish to reset or change
	them, use a keyring management tool such as `seahorse` and delete the keys
	"Juniper VPN Host", "Juniper VPN Password" and "Juniper VPN Username".
	On the next start, the script will ask for new credentials.

Author
------
login.sh was written by Andreas Textor <textor.andreas@googlemail.com>.

