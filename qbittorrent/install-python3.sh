#!/bin/bash
if [ ! -e /usr/bin/python3 ]; then
	echo "[INFO] Python3 not yet installed, installing..." | ts '%Y-%m-%d %H:%M:%.S'
	apt -qq update \
	&& apt -y install python3 \
	&& apt-get clean \
	&& apt -y autoremove \
	&& rm -rf \
	/var/lib/apt/lists/* \
	/tmp/* \
	/var/tmp/*
else
	echo "[INFO] Python3 is already installed, nothing to do." | ts '%Y-%m-%d %H:%M:%.S'
fi