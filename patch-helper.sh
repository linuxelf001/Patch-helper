#!/bin/bash
#
# Check whether upstream CIFS patches have been backported to a distro's
# Azure-tuned kernel. By default, print a list of all missing patches. 
#
#If given an upstream commit id, print the status of that specific patch.
#
# Usage:
#   ./patch-helper.sh [-b|-d|-e] -c codename -k kernel -u upstream [commit]
# where
#   o "-b" means that we are checking Ubuntu (this is the default)
#   o "-d" means that we are checking Debian
#   o "-e" means that we are checking Centos
#   o "codename" is the codeword for the distro release
#   o "kernel" is the version of the Azure-tuned kernel
#   o "upstream" is the path to store the upstream git tree
#   o "commit" is the id of the upstream commit to check
#
# Examples:
#   ./patch-helper.sh -b -c xenial -k 4.15.0-1060-azure -u ~/linux
#   ./patch-helper.sh -b -c disco -k 5.0.0-1010-azure -u ~/linux 7c00c3a625f8
#   ./patch-helper.sh -d -c buster -k 4.19.0-8-cloud-amd64 -u ~/linux
#   ./patch-helper.sh -e -c 7 -k 3.10.0-862.14.4.el7.azure.x86_64 -u ~/linux

# Delete temporary files on exit
cleanup()
{
	rm -f $PACKAGE_INFO
	rm -f $CHANGELOG
	rm -f $UPS_LOG
}
trap cleanup EXIT

# Print a message to stderr and exit with an error code
fail()
{
	echo "$*" 1>&2
	exit 1
}

# Find changelog and full kernel version ($FULL_KVER) for an Ubuntu kernel
ubuntu_get_package_info()
{
	# Download the webpage for the package
	local PKGURL="https://packages.ubuntu.com/$CODENAME/linux-modules-$KVER"
	PACKAGE_INFO=$(mktemp)
	echo "Fetching info for the Azure kernel package..." 1>&2
	wget "$PKGURL" -O $PACKAGE_INFO >& /dev/null ||
		fail "Failed to download info on the Azure kernel package"

	# Parse the webpage for info
	local CHANGELOG_URL=$(grep "Ubuntu Changelog" $PACKAGE_INFO |
			      grep -o '".*"')
	CHANGELOG_URL=${CHANGELOG_URL//\"}
	CHANGELOG_URL=${CHANGELOG_URL/http/https}
	FULL_KVER=$(grep 'Package: linux-modules-' $PACKAGE_INFO |
		    grep -o '(.*)')
	FULL_KVER=${FULL_KVER//\(}
	FULL_KVER=${FULL_KVER//\)}

	CHANGELOG=$(mktemp)
	echo "Fetching the changelog for the Azure kernel..." 1>&2
	wget "$CHANGELOG_URL" -O $CHANGELOG >& /dev/null ||
		fail "Failed to download the changelog for the Azure kernel"

	PREFIX_ON_CHANGELOG='linux-azure ('
}

# Find changelog and full kernel version ($FULL_KVER) for a Debian kernel
debian_get_package_info()
{
	# Download the webpage for the package
	local PKGURL="https://packages.debian.org/$CODENAME/linux-image-$KVER-unsigned"
	PACKAGE_INFO=$(mktemp)
	echo "Fetching info for the Azure kernel package..." 1>&2
	wget "$PKGURL" -O $PACKAGE_INFO >& /dev/null ||
		fail "Failed to download info on the Azure kernel package"

	# Parse the webpage for info
	local CHANGELOG_URL=$(grep "Debian Changelog" $PACKAGE_INFO |
			      grep -o '".*"')
	CHANGELOG_URL=${CHANGELOG_URL//\"}
	FULL_KVER=$(grep 'Package: linux-image-' $PACKAGE_INFO |
		    grep -o '(.*)')
	FULL_KVER=${FULL_KVER//\(}
	FULL_KVER=${FULL_KVER//\)}

	CHANGELOG=$(mktemp)
	echo "Fetching the changelog for the Azure kernel..." 1>&2
	wget "$CHANGELOG_URL" -O $CHANGELOG >& /dev/null ||
		fail "Failed to download the changelog for the Azure kernel"

	PREFIX_ON_CHANGELOG='linux ('
}

# Find changelog and full kernel version ($FULL_KVER) for a Centos kernel
centos_get_package_info()
{
	command -v rpm >& /dev/null ||
		fail "You need to install the rpm package manager"

	# Download the whole rpm package
	local PKGURL="http://mirror.centos.org/centos/$CODENAME/virt/x86_64/azure/kernel-azure-$KVER.rpm"
	PACKAGE_INFO=$(mktemp)
	echo "Fetching the Azure kernel package..." 1>&2
	wget "$PKGURL" -O $PACKAGE_INFO >& /dev/null ||
		fail "Failed to download the Azure kernel package"

	# Read the changelog from the package metadata
	CHANGELOG=$(mktemp)
	rpm -qp --changelog $PACKAGE_INFO > $CHANGELOG 2>/dev/null

	# Parse the changelog for the full kernel version
	FULL_KVER=$(grep -m 1 -o '[^[:space:]]*$' $CHANGELOG)

	PREFIX_ON_CHANGELOG=' \['
}

# Parse the command options
TEMP=$(getopt -o 'bdec:k:u:' -n 'ups-cifs' -- "$@")
[ $? -ne 0 ] && fail
eval set -- "$TEMP"
unset TEMP
while true; do
	case "$1" in
	'-b')
		[ -n "$DISTRO" ] && fail "More than one distro specified"
		DISTRO="ubuntu"
		shift
		continue
		;;
	'-d')
		[ -n "$CHANGELOG" ] && fail "More than one distro specified"
		DISTRO="debian"
		shift
		continue
		;;
	'-e')
		[ -n "$CHANGELOG" ] && fail "More than one distro specified"
		DISTRO="centos"
		shift
		continue
		;;
	'-c')
		CODENAME="$2"
		shift 2
		continue
		;;
	'-k')
		KVER="$2"
		MAJOR=$(echo "$KVER" | grep -o '^[[:digit:]]*')
		MINOR=$(echo "$KVER" | grep -o '^[[:digit:]]*\.[[:digit:]]*' |
			grep -o '[[:digit:]]*$')
		shift 2
		continue
		;;
	'-u')
		UPS_DIR="$2"
		shift 2
		continue
		;;
	'--')
		COMMIT="$2"
		break
	esac
done
[ -z "$CODENAME" -o -z "$KVER" -o -z "$UPS_DIR" ] && fail "Missing option"
[ -z "$DISTRO" ] && DISTRO="ubuntu"

# Perform all distro-specific information retrieval
[ "$DISTRO" == "ubuntu" ] && ubuntu_get_package_info
[ "$DISTRO" == "debian" ] && debian_get_package_info
[ "$DISTRO" == "centos" ] && centos_get_package_info

# Find the first line that refers to this kernel version
CHANGELOG_START=$(grep -nm 1 "$FULL_KVER" $CHANGELOG | grep -o '^[[:digit:]]*')

# Clone or update the upstream kernel
UPS_KVER=$(echo "$FULL_KVER" | grep -o '^[[:digit:]]*\.[[:digit:]]*')
UPS_URL='git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git'
echo "Fetching the latest upstream kernel..." 1>&2
[ -a "$UPS_DIR" ] || { git clone "$UPS_URL" "$UPS_DIR" >& /dev/null ||
		 fail "Failed to clone the upstream kernel"; }
cd "$UPS_DIR" || fail
git pull >& /dev/null || fail "Failed to update the upstream kernel"

# If a commit id was specified, check the status of that one only
if [ -n "$COMMIT" ]; then
	# Check if it was part of an old upstream release
	COMMIT_KVER=$(git name-rev --tags --name-only "$COMMIT" |&
					grep -o '^v[[:digit:]]*\.[[:digit:]]*')
	COMMIT_KVER=${COMMIT_KVER//v}
	[ -z "$COMMIT_KVER" ] && fail "Failed to find commit $COMMIT"
	COMMIT_MAJOR=$(echo "$COMMIT_KVER" | grep -o '^[[:digit:]]*')
	COMMIT_MINOR=$(echo "$COMMIT_KVER" | grep -o '[[:digit:]]*$')
	if [ $COMMIT_MAJOR -lt $MAJOR ] ||
	   [ $COMMIT_MAJOR -eq $MAJOR -a $COMMIT_MINOR -le $MINOR ]; then
		echo "$COMMIT was picked up as part of Linux $COMMIT_KVER"
		exit 0
	fi

# Check it it's in the changelogs, and under which release
# Debian splits long commit titles in the changelogs, so just check the first 72 characters
	COMMIT_SUBJECT=$(git show -s --format='%s' "$COMMIT" 2>&1)
	COMMIT_SUBJECT=${COMMIT_SUBJECT::72}
	CHANGELOG_END=$(grep -nF "$COMMIT_SUBJECT" $CHANGELOG |
			grep -o '^[[:digit:]]*')
	[ -z "$CHANGELOG_END" ] && CHANGELOG_END=0
	COMMIT_KVER=$(head -n $CHANGELOG_END $CHANGELOG |
		      tail -n +$CHANGELOG_START |
		      grep "$PREFIX_ON_CHANGELOG"'[[:digit:]]*\.' |
		      tail -n 1 | grep -o '[[(].*[])]')
	COMMIT_KVER=${COMMIT_KVER//\(}
	COMMIT_KVER=${COMMIT_KVER//\[}
	COMMIT_KVER=${COMMIT_KVER//\)}
	COMMIT_KVER=${COMMIT_KVER//\]}
	if [ -n "$COMMIT_KVER" ]; then
		echo "$COMMIT was picked up for the $COMMIT_KVER release"
		exit 0
	fi

	echo "$COMMIT hasn't been picked up for $KVER"
	exit 0
fi

# Print each upstream commit, as long as it isn't listed in the changelog
UPS_LOG=$(mktemp)
git log --oneline v"$UPS_KVER"..HEAD fs/cifs > $UPS_LOG || fail
while read -r CTID CTNAME; do
	tail -n +$CHANGELOG_START $CHANGELOG | grep -qF "$CTNAME" ||
							echo $CTID $CTNAME
done < $UPS_LOG || fail

exit 0
