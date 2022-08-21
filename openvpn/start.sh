#!/bin/bash
# Forked from binhex's OpenVPN dockers
set -e

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[ERROR] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S'
	# Sleep so it wont 'spam restart'
	sleep 10
	exit 1
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED,,}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	echo "[INFO] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[WARNING] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

export LEGACY_IPTABLES=$(echo "${LEGACY_IPTABLES,,}")
echo "[INFO] LEGACY_IPTABLES is set to '${LEGACY_IPTABLES}'" | ts '%Y-%m-%d %H:%M:%.S'
if [[ $LEGACY_IPTABLES == "1" || $LEGACY_IPTABLES == "true" || $LEGACY_IPTABLES == "yes" ]]; then
	echo "[INFO] Setting iptables to iptables (legacy)" | ts '%Y-%m-%d %H:%M:%.S'
	update-alternatives --set iptables /usr/sbin/iptables-legacy
else
	echo "[INFO] Not making any changes to iptables version" | ts '%Y-%m-%d %H:%M:%.S'
fi
iptables_version=$(iptables -V)
echo "[INFO] The container is currently running ${iptables_version}."  | ts '%Y-%m-%d %H:%M:%.S'

if [[ $VPN_ENABLED == "1" || $VPN_ENABLED == "true" || $VPN_ENABLED == "yes" ]]; then
	# Check if VPN_TYPE is set.
	if [[ -z "${VPN_TYPE}" ]]; then
		echo "[WARNING] VPN_TYPE not set, defaulting to OpenVPN." | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_TYPE="openvpn"
	else
		echo "[INFO] VPN_TYPE defined as '${VPN_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	if [[ "${VPN_TYPE}" != "openvpn" && "${VPN_TYPE}" != "wireguard" ]]; then
		echo "[WARNING] VPN_TYPE not set, as 'wireguard' or 'openvpn', defaulting to OpenVPN." | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_TYPE="openvpn"
	fi
	# Create the directory to store OpenVPN or WireGuard config files
	mkdir -p /config/${VPN_TYPE}
	# Set permmissions and owner for files in /config/openvpn or /config/wireguard directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/${VPN_TYPE}" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/${VPN_TYPE}" &> /dev/null
	exit_code_chmod=$?
	set -e
	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[WARNING] Unable to chown/chmod /config/${VPN_TYPE}/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# Wildcard search for openvpn config files (match on first result)
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)
	else
		export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
	fi

	# If ovpn file not found in /config/openvpn or /config/wireguard then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		if [[ "${VPN_TYPE}" == "openvpn" ]]; then
			echo "[ERROR] No OpenVPN config file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.ovpn'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[ERROR] No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'" | ts '%Y-%m-%d %H:%M:%.S'
		fi
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		echo "[INFO] OpenVPN config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[INFO] WireGuard config file is found at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'
		if [[ "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
			echo "[ERROR] WireGuard config filename is not 'wg0.conf'" | ts '%Y-%m-%d %H:%M:%.S'
			echo "[ERROR] Rename ${VPN_CONFIG} to 'wg0.conf'" | ts '%Y-%m-%d %H:%M:%.S'
			sleep 10
			exit 1
		fi
	fi

	# Read username and password env vars and put them in credentials.conf, then add ovpn config for credentials file
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		if [[ ! -z "${VPN_USERNAME}" ]] && [[ ! -z "${VPN_PASSWORD}" ]]; then
			if [[ ! -e /config/openvpn/credentials.conf ]]; then
				touch /config/openvpn/credentials.conf
			fi

			echo "${VPN_USERNAME}" > /config/openvpn/credentials.conf
			echo "${VPN_PASSWORD}" >> /config/openvpn/credentials.conf

			# Replace line with one that points to credentials.conf
			auth_cred_exist=$(cat "${VPN_CONFIG}" | grep -m 1 'auth-user-pass')
			if [[ ! -z "${auth_cred_exist}" ]]; then
				# Get line number of auth-user-pass
				LINE_NUM=$(grep -Fn -m 1 'auth-user-pass' "${VPN_CONFIG}" | cut -d: -f 1)
				sed -i "${LINE_NUM}s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
			else
				sed -i "1s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
			fi
		fi
	fi
	
	# convert CRLF (windows) to LF (unix) for ovpn
	dos2unix "${VPN_CONFIG}" 1> /dev/null
	
	# parse values from the ovpn or conf file
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	else
		export vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^Endpoint)(\s{0,})[^\n\r]+' | sed -e 's~^[=\ ]*~~')
	fi

	if [[ ! -z "${vpn_remote_line}" ]]; then
		echo "[INFO] VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}"
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	else
		export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^:\r\n]+')
	fi

	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[INFO] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	else
		export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=:)\d{2,5}(?=:)?+')
	fi

	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[INFO] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PROTOCOL}" ]]; then
			echo "[INFO] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
			if [[ ! -z "${VPN_PROTOCOL}" ]]; then
				echo "[INFO] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
			else
				echo "[WARNING] VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp" | ts '%Y-%m-%d %H:%M:%.S'
				export VPN_PROTOCOL="udp"
			fi
		fi
		# required for use in iptables
		if [[ "${VPN_PROTOCOL}" == "tcp-client" ]]; then
			export VPN_PROTOCOL="tcp"
		fi
	else
		export VPN_PROTOCOL="udp"
		echo "[INFO] VPN_PROTOCOL set as '${VPN_PROTOCOL}', since WireGuard is always ${VPN_PROTOCOL}." | ts '%Y-%m-%d %H:%M:%.S'
	fi


	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
			export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
			echo "[INFO] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[ERROR] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S'
			# Sleep so it wont 'spam restart'
			sleep 10
			exit 1
		fi
	else
		export VPN_DEVICE_TYPE="wg0"
		echo "[INFO] VPN_DEVICE_TYPE set as '${VPN_DEVICE_TYPE}', since WireGuard will always be wg0." | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# get values from env vars as defined by user
	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[INFO] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[ERROR] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S'
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[INFO] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to CloudFlare and Google name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_OPTIONS}" ]]; then
			echo "[INFO] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[INFO] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
			export VPN_OPTIONS=""
		fi
	fi

else
	echo "[WARNING] !!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi


# split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# process name servers in the list
for name_server_item in "${name_server_list[@]}"; do
	# strip whitespace from start and end of lan_network_item
	name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "[INFO] Adding ${name_server_item} to resolv.conf" | ts '%Y-%m-%d %H:%M:%.S'
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf
done

if [[ -z "${PUID}" ]]; then
	echo "[INFO] PUID not defined. Defaulting to root user" | ts '%Y-%m-%d %H:%M:%.S'
	export PUID="root"
fi

if [[ -z "${PGID}" ]]; then
	echo "[INFO] PGID not defined. Defaulting to root group" | ts '%Y-%m-%d %H:%M:%.S'
	export PGID="root"
fi

if [[ $VPN_ENABLED == "1" || $VPN_ENABLED == "true" || $VPN_ENABLED == "yes" ]]; then
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		echo "[INFO] Starting OpenVPN..." | ts '%Y-%m-%d %H:%M:%.S'
		cd /config/openvpn
		exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "${VPN_CONFIG}" &
		#exec /bin/bash /etc/openvpn/openvpn.init start &
	else
		echo "[INFO] Starting WireGuard..." | ts '%Y-%m-%d %H:%M:%.S'
		cd /config/wireguard
		if ip link | grep -q `basename -s .conf $VPN_CONFIG`; then
			wg-quick down $VPN_CONFIG || echo "WireGuard is down already" | ts '%Y-%m-%d %H:%M:%.S' # Run wg-quick down as an extra safeguard in case WireGuard is still up for some reason
			sleep 0.5 # Just to give WireGuard a bit to go down
		fi
		wg-quick up $VPN_CONFIG
		#exec /bin/bash /etc/openvpn/openvpn.init start &
	fi
	exec /bin/bash /etc/qbittorrent/iptables.sh
else
	echo "[WARNIG] @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] THE CONTAINER IS RUNNING WITH VPN DISABLED" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] PLEASE MAKE SURE VPN_ENABLED IS SET TO 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] IF THIS IS INTENTIONAL, YOU CAN IGNORE THIS" | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNIG] @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@" | ts '%Y-%m-%d %H:%M:%.S'
	exec /bin/bash /etc/qbittorrent/start.sh
fi
