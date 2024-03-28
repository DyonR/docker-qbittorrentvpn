#!/bin/bash

port=$(natpmpc -a 1 0 udp 60 -g 10.2.0.1 | grep "public port" | awk '/Mapped public port/ {print $4}')

# find and replace "Session\Port=.*" in /config/qBittorrent/config/qBittorrent.conf with $port
sed -i -r "s/^(Session\\\Port=).*/\1$port/" /config/qBittorrent/config/qBittorrent.conf

# run the port forward loop.
while true ; do date ; natpmpc -a 1 0 udp 60 -g 10.2.0.1 && natpmpc -a 1 0 tcp 60 -g 10.2.0.1 || { echo -e "ERROR with natpmpc command \a" ; break ; } ; sleep 45 ; done