FROM debian:10-slim

WORKDIR /opt

RUN usermod -u 99 nobody

# Make directories
RUN mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent

RUN apt update \
    && apt -y upgrade \
    && apt -y install --no-install-recommends \
    curl \
    jq \
    build-essential \
    ca-certificates \
    pkg-config \
    automake \
    libtool \
    git \
    zlib1g-dev \
    libssl-dev \
    libgeoip-dev \
    libboost-dev \
    libboost-system-dev \
    libboost-chrono-dev \
    libboost-random-dev \
    python3 \
    qtbase5-dev \
    qttools5-dev \
    libqt5svg5-dev \
    && LIBTORRENT_ASSETS=$(curl -sX GET "https://api.github.com/repos/arvidn/libtorrent/releases" | jq '.[] | select(.prerelease==false) | select(.target_commitish=="RC_1_2") | .assets_url' | head -n 1 | tr -d '"') \
    && LIBTORRENT_DOWNLOAD_URL=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .browser_download_url' | tr -d '"') \
    && LIBTORRENT_NAME=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .name' | tr -d '"') \
    && curl -o /opt/${LIBTORRENT_NAME} -L ${LIBTORRENT_DOWNLOAD_URL} \
    && tar -xvzf /opt/${LIBTORRENT_NAME} \
    && rm /opt/*.tar.gz \
    && cd /opt/libtorrent-rasterbar* \
    && ./configure --disable-debug --enable-encryption && make clean && make -j$(nproc) && make install \
    && git clone https://github.com/qbittorrent/qBittorrent.git /opt/qBittorrent \
    && cd /opt/qBittorrent \
    && ./configure --disable-gui && make -j$(nproc) && make install \
    && cd /opt \
    && rm -rf /opt/* \
    && apt -y purge \
    curl \
    jq \
    build-essential \
    ca-certificates \
    pkg-config \
    automake \
    libtool \
    git \
    zlib1g-dev \
    libssl-dev \
    libgeoip-dev \
    libboost-dev \
    libboost-system-dev \
    libboost-chrono-dev \
    libboost-random-dev \
    python3 \
    qtbase5-dev \
    qttools5-dev \
    libqt5svg5-dev \
    && apt-get clean \
    && apt -y autoremove \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

RUN echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable-wireguard.list \ 
    && printf 'Package: *\nPin: release a=unstable\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-unstable \
    && apt update \
    && apt -y install --no-install-recommends \
    libboost-system1.67.0 \
    libqt5xml5 \
    libqt5network5 \
    libssl1.1 \
    kmod \
    iptables \
    inetutils-ping \
    procps \
    moreutils \
    net-tools \
    dos2unix \
    openvpn \
    openresolv \
    wireguard-tools \
    ipcalc \
    ca-certificates \
    && apt-get clean \
    && apt -y autoremove \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

VOLUME /config /downloads

ADD openvpn/ /etc/openvpn/
ADD qbittorrent/ /etc/qbittorrent/

RUN chmod +x /etc/qbittorrent/*.sh /etc/qbittorrent/*.init /etc/openvpn/*.sh

EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp
CMD ["/bin/bash", "/etc/openvpn/start.sh"]
