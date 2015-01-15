#!/bin/bash

ncdir="$HOME/.juniper_networks/network_connect"
keyring_key="juniper.vpn"
keyring_host_attr="host"
keyring_username_attr="username"
keyring_password_attr="password"

function fail() {
	zenity --error --text="$1 failed. $2"
	exit 1
}

function testfor() {
	return `which "$1" &>/dev/null`
}

function require() {
	zenity --warning --text="$1 not found - please install package $2"
	exit 1
}

function credentials() {
	zdata=$(zenity \
		--forms \
		--text="Please enter your credentials" \
		--add-entry="VPN host (full URL, e.g., https://my.company/vpn)" \
		--add-entry="VPN host username" \
		--add-password="VPN host password" \
		--width=700 \
		--title="Juniper Login")
	hosturl=$(echo $zdata | cut -d'|' -f1)
	username=$(echo $zdata | cut -d'|' -f2)
	password=$(echo $zdata | cut -d'|' -f3-)
	echo -n $hosturl | secret-tool store --label="Juniper VPN Host" $keyring_key $keyring_host_attr
	echo -n $username | secret-tool store --label="Juniper VPN Username" $keyring_key $keyring_username_attr
	echo -n $password | secret-tool store --label="Juniper VPN Password" $keyring_key $keyring_password_attr
}

function create_loginjs() {
cat << EOF > "$1"
var page = new WebPage(),
	system = require('system'),
	testindex = 0,
	loadInProgress = false;

if (system.args.length !== 3) {
	console.log("Usage: phantomjs login.js username password");
	phantom.exit(1);
}

var username = system.args[1];
var password = system.args[2];

console.error = function() {
	system.stderr.write("[DEBUG] " + Array.prototype.join.call(arguments, ' ') + '\n');
}

page.onConsoleMessage = function(msg) {
	if (msg.indexOf("[DEBUG]") == 0) {
		system.stderr.write(msg + '\n');
	} else {
		console.log(msg);
	}
};

var steps = [
	function() {
		// Load Login Page
		page.open("$hosturl");
	},
	function() {
		// Enter Credentials
		page.evaluate(function(u, p) {
			console.log("[DEBUG] Enter credentials");
			var arr = document.getElementsByName("frmLogin");
			var i;

			for (i = 0; i < arr.length; i++) {
				if (arr[i].getAttribute('method') == "POST") {
					arr[i].elements["username"].value = u;
					arr[i].elements["password"].value = p;
					return 0;
				}
			}
		}, username, password);
	},
	function() {
		// Login
		page.evaluate(function() {
			console.log("[DEBUG] Login");
			var arr = document.getElementsByName("frmLogin");
			var i;

			for (i = 0; i < arr.length; i++) {
				if (arr[i].getAttribute('method') == "POST") {
					arr[i].submit();
					return 0;
				}
			}

		});
	},
	function() {
		// Take over session if necessary
		page.evaluate(function() {
			var form = document.getElementById("DSIDConfirmForm");
			if (form == null) {
				return 0;
			}

			console.log("[DEBUG] Taking over session");
			document.getElementsByName("btnContinue")[0].click();
			return 0;
		});
	},
	function() {
		// Output DSID Cookie
		page.evaluate(function() {
			console.log("[DEBUG] Output DSID");
			var value = "; " + document.cookie;
			var parts = value.split("; DSID=");
			if (parts.length == 2) {
				var dsid = parts.pop().split(";").shift();
				console.log("DSID=" + dsid);
				return 0;
			} else {
				console.log("[DEBUG] Could not determine DSID");
				return 1;
			}
		});
	}
];

interval = setInterval(function() {
	if (!loadInProgress && typeof steps[testindex] == "function") {
		//console.error("step " + (testindex + 1));
		var result = steps[testindex]();
		if (result > 0) {
			phantom.exit(result);
		}
		testindex++;
	}
	if (typeof steps[testindex] != "function") {
		// We've reached the end.
		// Put any code here that should be called once the page is loaded.
		// Don't call phantom.exit() to keep session open.
	}
}, 2000);

EOF
}

if [ $# -ne 0 ]; then
	cat <<- EOF
	Juniper VPN Login

	Usage: $0

	See https://github.com/atextor/juniper-vpn for more information.
	EOF
	exit 0
fi

testfor zenity || { echo "zenity not found - please install package zenity"; exit 1; }
testfor phantomjs || require phantomjs phantomjs
testfor xterm || require xterm xterm
testfor secret-tool || require secret-tool libsecret-tools
testfor sudo || require sudo sudo
testfor gksudo || require gksudo gksu
testfor alien || require alien alien
testfor openssl || require openssl openssl
testfor tar || require tar tar
testfor gcc || require gcc gcc-multilib

mkdir -p "$ncdir"

if [ ! -x "$ncdir/ncui" ]; then
	# First run
	zenity --info --text="You are running VPN login for the first time. This will setup the tool. In the following dialog, please select the Juniper Network Connect Client RPM file (ncui-6.5R9.i386.rpm)."
	rpmfile=$(readlink -f "$(zenity --file-selection --file-filter='ncui-6.5R9.i386.rpm')")
	credentials
	host=$(echo $hosturl | awk -F/ '{print $3}')
	dir=$(mktemp -d)

	(
		echo "10"
		echo "# Copying file to temp dir $dir"
		cp "$rpmfile" "$dir"
		cd "$dir"

		echo "20"
		echo "# Converting package"
		if ! alien -t "ncui-6.5R9.i386.rpm"; then
			fail "Converting package"
		fi

		echo "30"
		echo "# Extracting client"
		if ! tar -xzvf ncui-6.5.tgz --strip-components 3; then
			fail "Extracting client"
		fi

		echo "40"
		echo "# Installing client"
		if ! mv nc/* "$ncdir"; then
			fail "Installing client"
		fi

		cd "$ncdir"
		echo "50"
		echo "# Building client library"
		if ! gcc -m32 -Wl,-rpath,`pwd` -o ncui libncui.so; then
			fail "Building client binary" "Maybe you're missing package gcc-multilib."
		fi

		echo "60"
		echo "# Getting certificate for $host"
		echo | openssl s_client -connect $host:443 2>&1 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' | openssl x509 -outform der > ${host}.crt
		if [ $? -ne 0 ]; then
			fail "Getting certificate for $host"
		fi

		echo "70"
		echo "# Creating login.js"
		create_loginjs "$ncdir/login.js"

		echo "80"
		echo "# Cleaning up"
		rm -rf "$dir"
	) |
	zenity --progress \
		--title="Installing Juniper VPN" \
		--text="Installing Juniper VPN" \
		--percentage=0 \
		--auto-close

	zenity --info --text="Installation complete. Run the script again to connect to the VPN."
	exit 0
fi

username=$(secret-tool lookup $keyring_key $keyring_username_attr)
if [ -z $username ]; then
	# no credentials in keyring
	# display dialog to enter credentials
	credentials
else
	hosturl=$(secret-tool lookup $keyring_key $keyring_host_attr)
	password=$(secret-tool lookup $keyring_key $keyring_password_attr)
fi

host=$(echo $hosturl | awk -F/ '{print $3}')
cd "$ncdir"

scriptpid=$$
exec 3> >(zenity --progress --pulsate --title="Connecting to Juniper VPN" --auto-close --width=500 --auto-kill)
zenpid=$!
echo "# Connecting" >&3

# simulate login using phantomjs
phantomjs login.js "$username" "$password" 2>&1 | {
	while read dsid; do
		echo "# ${dsid}" | sed -e 's/\[DEBUG\] //g' >&3
		echo $dsid | grep "^DSID=" &>/dev/null || continue
		exec 3>&-
		pkill -P $zenpid
		wait $zenpid 2>/dev/null

		echo Using DSID: $dsid
		if [ -z "$dsid" ]; then
			zenity --error --text="Could not determine DSID - Aborting."
			kill $scriptpid
			exit 1
		fi

		cd "$ncdir"
		sudo -k
		gksudo --message "System administrator privileges are required to run Juniper VPN. Please enter your password." -p | \
			2>&1 &>/dev/null sudo -p "" -S xterm -title "Juniper VPN - Close this window to terminate VPN connection" -e "/bin/bash -c echo | ./ncui -h ${host} -c $dsid -f "$ncdir"/${host}.crt"
		kill $scriptpid
		exit 0
	done
}

