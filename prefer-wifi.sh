#!/bin/bash

# Moves WiFi interface to top of service order

if networksetup -listnetworkserviceorder | grep -q "Wi-Fi"; then
	services=("Wi-Fi")
	while read -r service; do
		if [[ "$service" != "Wi-Fi" ]]; then
			services+=("$service")
		fi
	done < <(networksetup -listnetworkserviceorder | grep "^(.*)." | sed 's/(.*) //')

	networksetup -ordernetworkservices "${services[@]}"
fi
