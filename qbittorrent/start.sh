#!/bin/bash
# Check if /config/qBittorrent exists, if not make the directory
if [[ ! -e /config/qBittorrent/config ]]; then
	mkdir -p /config/qBittorrent/config
fi
# Set the correct rights accordingly to the PUID and PGID on /config/qBittorrent
chown -R ${PUID}:${PGID} /config/qBittorrent

# Set the rights on the /downloads folder
chown -R ${PUID}:${PGID} /downloads

# Check if qBittorrent.conf exists, if not, copy the template over
if [ ! -e /config/qBittorrent/config/qBittorrent.conf ]; then
	echo "[WARNING] qBittorrent.conf is missing, this is normal for the first launch! Copying template." | ts '%Y-%m-%d %H:%M:%.S'
	cp /etc/qbittorrent/qBittorrent.conf /config/qBittorrent/config/qBittorrent.conf
	chmod 755 /config/qBittorrent/config/qBittorrent.conf
	chown ${PUID}:${PGID} /config/qBittorrent/config/qBittorrent.conf
fi

export INSTALL_PYTHON3=$(echo "${INSTALL_PYTHON3,,}")
if [[ $INSTALL_PYTHON3 == "yes" ]]; then
	/bin/bash /etc/qbittorrent/install-python3.sh
fi

# The mess down here checks if SSL is enabled.
export ENABLE_SSL=$(echo "${ENABLE_SSL,,}")
if [[ ${ENABLE_SSL} == 'yes' ]]; then
	echo "[INFO] ENABLE_SSL is set to ${ENABLE_SSL}" | ts '%Y-%m-%d %H:%M:%.S'
	if [[ ${HOST_OS,,} == 'unraid' ]]; then
		echo "[SYSTEM] If you use Unraid, and get something like a 'ERR_EMPTY_RESPONSE' in your browser, add https:// to the front of the IP, and/or do this:" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[SYSTEM] Edit this Docker, change the slider in the top right to 'advanced view' and change http to https at the WebUI setting." | ts '%Y-%m-%d %H:%M:%.S'
	fi
	if [ ! -e /config/qBittorrent/config/WebUICertificate.crt ]; then
		echo "[WARNING] WebUI Certificate is missing, generating a new Certificate and Key" | ts '%Y-%m-%d %H:%M:%.S'
		openssl req -new -x509 -nodes -out /config/qBittorrent/config/WebUICertificate.crt -keyout /config/qBittorrent/config/WebUIKey.key -subj "/C=NL/ST=localhost/L=localhost/O=/OU=/CN="
		chown -R ${PUID}:${PGID} /config/qBittorrent/config
	elif [ ! -e /config/qBittorrent/config/WebUIKey.key ]; then
		echo "[WARNING] WebUI Key is missing, generating a new Certificate and Key" | ts '%Y-%m-%d %H:%M:%.S'
		openssl req -new -x509 -nodes -out /config/qBittorrent/config/WebUICertificate.crt -keyout /config/qBittorrent/config/WebUIKey.key -subj "/C=NL/ST=localhost/L=localhost/O=/OU=/CN="
		chown -R ${PUID}:${PGID} /config/qBittorrent/config
	fi
	if grep -Fxq 'WebUI\HTTPS\CertificatePath=/config/qBittorrent/config/WebUICertificate.crt' "/config/qBittorrent/config/qBittorrent.conf"; then
		echo "[INFO] /config/qBittorrent/config/qBittorrent.conf already has the line WebUICertificate.crt loaded, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf doesn't have the WebUICertificate.crt loaded. Added it to the config." | ts '%Y-%m-%d %H:%M:%.S'
		echo 'WebUI\HTTPS\CertificatePath=/config/qBittorrent/config/WebUICertificate.crt' >> "/config/qBittorrent/config/qBittorrent.conf"
	fi
	if grep -Fxq 'WebUI\HTTPS\KeyPath=/config/qBittorrent/config/WebUIKey.key' "/config/qBittorrent/config/qBittorrent.conf"; then
		echo "[INFO] /config/qBittorrent/config/qBittorrent.conf already has the line WebUIKey.key loaded, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf doesn't have the WebUIKey.key loaded. Added it to the config." | ts '%Y-%m-%d %H:%M:%.S'
		echo 'WebUI\HTTPS\KeyPath=/config/qBittorrent/config/WebUIKey.key' >> "/config/qBittorrent/config/qBittorrent.conf"
	fi
	if grep -xq 'WebUI\\HTTPS\\Enabled=true\|WebUI\\HTTPS\\Enabled=false' "/config/qBittorrent/config/qBittorrent.conf"; then
		if grep -xq 'WebUI\\HTTPS\\Enabled=false' "/config/qBittorrent/config/qBittorrent.conf"; then
			echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf does have the WebUI\HTTPS\Enabled set to false, changing it to true." | ts '%Y-%m-%d %H:%M:%.S'
			sed -i 's/WebUI\\HTTPS\\Enabled=false/WebUI\\HTTPS\\Enabled=true/g' "/config/qBittorrent/config/qBittorrent.conf"
		else
			echo "[INFO] /config/qBittorrent/config/qBittorrent.conf does have the WebUI\HTTPS\Enabled already set to true." | ts '%Y-%m-%d %H:%M:%.S'
		fi
	else
		echo "[WARNING] /config/qBittorrent/config/qBittorrent.conf doesn't have the WebUI\HTTPS\Enabled loaded. Added it to the config." | ts '%Y-%m-%d %H:%M:%.S'
		echo 'WebUI\HTTPS\Enabled=true' >> "/config/qBittorrent/config/qBittorrent.conf"
	fi
else
	echo "[WARNING] ENABLE_SSL is set to ${ENABLE_SSL}, SSL is not enabled. This could cause issues with logging if other apps use the same Cookie name (SID)." | ts '%Y-%m-%d %H:%M:%.S'
	echo "[WARNING] If you manage the SSL config yourself, you can ignore this." | ts '%Y-%m-%d %H:%M:%.S'
fi

# Check if the PGID exists, if not create the group with the name 'qbittorrent'
grep $"${PGID}:" /etc/group > /dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "[INFO] A group with PGID $PGID already exists in /etc/group, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[INFO] A group with PGID $PGID does not exist, adding a group called 'qbittorrent' with PGID $PGID" | ts '%Y-%m-%d %H:%M:%.S'
	groupadd -g $PGID qbittorrent
fi

# Check if the PUID exists, if not create the user with the name 'qbittorrent', with the correct group
id ${PUID} > /dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "[INFO] An user with PUID $PUID already exists in /etc/passwd, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[INFO] An user with PUID $PUID does not exist, adding an user called 'qbittorrent user' with PUID $PUID" | ts '%Y-%m-%d %H:%M:%.S'
	useradd -c "qbittorrent user" -g $PGID -u $PUID qbittorrent
fi

# Set the umask
if [[ ! -z "${UMASK}" ]]; then
	echo "[INFO] UMASK defined as '${UMASK}'" | ts '%Y-%m-%d %H:%M:%.S'
	export UMASK=$(echo "${UMASK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
	echo "[WARNING] UMASK not defined (via -e UMASK), defaulting to '002'" | ts '%Y-%m-%d %H:%M:%.S'
	export UMASK="002"
fi

# Start qBittorrent
echo "[INFO] Starting qBittorrent daemon..." | ts '%Y-%m-%d %H:%M:%.S'
/bin/bash /etc/qbittorrent/qbittorrent.init start &
chmod -R 755 /config/qBittorrent

# Wait a second for it to start up and get the process id
sleep 1
qbittorrentpid=$(pgrep -o -x qbittorrent-nox) 
echo "[INFO] qBittorrent PID: $qbittorrentpid" | ts '%Y-%m-%d %H:%M:%.S'

# If the process exists, make sure that the log file has the proper rights and start the health check
if [ -e /proc/$qbittorrentpid ]; then
	if [[ -e /config/qBittorrent/data/logs/qbittorrent.log ]]; then
		chmod 775 /config/qBittorrent/data/logs/qbittorrent.log
	fi
	
	# Set some variables that are used
	HOST=${HEALTH_CHECK_HOST}
	DEFAULT_HOST="one.one.one.one"
	INTERVAL=${HEALTH_CHECK_INTERVAL}
	DEFAULT_INTERVAL=300
	
	# If host is zero (not set) default it to the DEFAULT_HOST variable
	if [[ -z "${HOST}" ]]; then
		echo "[INFO] HEALTH_CHECK_HOST is not set. For now using default host ${DEFAULT_HOST}" | ts '%Y-%m-%d %H:%M:%.S'
		HOST=${DEFAULT_HOST}
	fi

	# If HEALTH_CHECK_INTERVAL is zero (not set) default it to DEFAULT_INTERVAL
	if [[ -z "${HEALTH_CHECK_INTERVAL}" ]]; then
		echo "[INFO] HEALTH_CHECK_INTERVAL is not set. For now using default interval of ${DEFAULT_INTERVAL}" | ts '%Y-%m-%d %H:%M:%.S'
		INTERVAL=${DEFAULT_INTERVAL}
	fi
	
	# If HEALTH_CHECK_SILENT is zero (not set) default it to supression
	if [[ -z "${HEALTH_CHECK_SILENT}" ]]; then
		echo "[INFO] HEALTH_CHECK_SILENT is not set. Because this variable is not set, it will be supressed by default" | ts '%Y-%m-%d %H:%M:%.S'
		HEALTH_CHECK_SILENT=1
	fi

	while true; do
		# Ping uses both exit codes 1 and 2. Exit code 2 cannot be used for docker health checks, therefore we use this script to catch error code 2
		ping -c 1 $HOST > /dev/null 2>&1
		STATUS=$?
		if [[ "${STATUS}" -ne 0 ]]; then
			echo "[ERROR] Network is down, exiting this Docker" | ts '%Y-%m-%d %H:%M:%.S'
			exit 1
		fi
		if [ ! "${HEALTH_CHECK_SILENT}" -eq 1 ]; then
			echo "[INFO] Network is up" | ts '%Y-%m-%d %H:%M:%.S'
		fi
		sleep ${INTERVAL}
	done
else
	echo "[ERROR] qBittorrent failed to start!" | ts '%Y-%m-%d %H:%M:%.S'
fi
