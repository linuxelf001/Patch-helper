# patch-helper

Patch-helper script can check whether upstream CIFS patches have been backported to a distro's Azure-tuned kernel. By default, print a list of all missing patches. 

If given an upstream commit id, print the status of that specific patch.

Usage:
  ./patch-helper.sh [-b|-d|-e] -c codename -k kernel -u upstream [commit]
  
where

    "-b" means that we are checking Ubuntu (this is the default)

    "-d" means that we are checking Debian

    "-e" means that we are checking Centos

    "codename" is the codeword for the distro release

    "kernel" is the version of the Azure-tuned kernel

    "upstream" is the path to store the upstream git tree

    "commit" is the id of the upstream commit to check

Examples:

    ./patch-helper.sh -b -c xenial -k 4.15.0-1060-azure -u ~/linux

    ./patch-helper.sh -b -c disco -k 5.0.0-1010-azure -u ~/linux 7c00c3a625f8

    ./patch-helper.sh -d -c buster -k 4.19.0-8-cloud-amd64 -u ~/linux

    ./patch-helper.sh -e -c 7 -k 3.10.0-862.14.4.el7.azure.x86_64 -u ~/linux

