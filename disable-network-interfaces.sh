#!/bin/bash

# Run as Root
if [ "$(whoami)" != "root" ]; then
	sudo "$0" "$@"
	exit 0
fi

#What to Disable
IFS=$'\n'
case $# in
	0)
		#Enable All Interfaces
		echo "No argument provided.  All interfaces will be enabled."
		for interface in $(networksetup -listnetworkserviceorder | awk '/^\([*]/{$1 ="";gsub("^ ",""); print $0}'); do
			echo "Turning on $interface"
			networksetup -setnetworkserviceenabled "$interface" on
		done
		exit 0
		;;
	1)
		#Disable Interfaces
		echo "All interfaces except those contining \"$1\" will be disabled."
		for interface in $(networksetup -listnetworkserviceorder | awk '/^\([0-9]/{$1 ="";gsub("^ ",""); print $0}'); do
			if [[ $interface != *"$1"* ]]; then
				echo "Turning off $interface"
				networksetup -setnetworkserviceenabled "$interface" off
			fi
		done
		exit 0
		;;
	*)
		echo "Error: Too many arguments."
		echo "Usage: $(basename "$0") [Interface Name]"
		exit 1
		;;
esac