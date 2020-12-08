FROM debian:10-slim

WORKDIR /opt

RUN usermod -u 99 nobody

# Make directories
RUN mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent

# Compile libtorrent-rasterbar
RUN apt update \
    && apt -y upgrade \
    && apt -y install --no-install-recommends \
    ca-certificates \
    curl \
    g++ \
    jq \
    libboost-system-dev \
    libssl-dev \
    make \
    && LIBTORRENT_ASSETS=$(curl -sX GET "https://api.github.com/repos/arvidn/libtorrent/releases" | jq '.[] | select(.prerelease==false) | select(.target_commitish=="RC_1_2") | .assets_url' | head -n 1 | tr -d '"') \
    && LIBTORRENT_DOWNLOAD_URL=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .browser_download_url' | tr -d '"') \
    && LIBTORRENT_NAME=$(curl -sX GET ${LIBTORRENT_ASSETS} | jq '.[0] .name' | tr -d '"') \
    && curl -o /opt/${LIBTORRENT_NAME} -L ${LIBTORRENT_DOWNLOAD_URL} \
    && tar -xzf /opt/${LIBTORRENT_NAME} \
    && rm /opt/${LIBTORRENT_NAME} \
    && cd /opt/libtorrent-rasterbar* \
    && ./configure CXXFLAGS="-std=c++14" --disable-debug --enable-encryption && make clean && make -j$(nproc) && make install \
    && cd /opt \
    && rm -rf /opt/* \
    && apt -y purge \
    ca-certificates \
    curl \
    g++ \
    jq \
    libboost-system-dev \
    libssl-dev \
    make \
    && apt-get clean \
    && apt -y autoremove \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

# Compile qBittorrent
RUN apt update \
    && apt -y upgrade \
    && apt -y install --no-install-recommends \
    ca-certificates \
    curl \
    g++ \
    jq \
    libboost-system-dev \
    libssl-dev \
    make \
    pkg-config \
    qtbase5-dev \
    qttools5-dev \
    zlib1g-dev \
    && QBITTORRENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/qBittorrent/qBittorrent/tags" | jq '.[0] .name' | tr -d '"') \
    && curl -o /opt/qBittorrent-${QBITTORRENT_RELEASE}.tar.gz -L "https://github.com/qbittorrent/qBittorrent/archive/${QBITTORRENT_RELEASE}.tar.gz" \
    && tar -xzf /opt/qBittorrent-${QBITTORRENT_RELEASE}.tar.gz \
    && rm /opt/qBittorrent-${QBITTORRENT_RELEASE}.tar.gz \
    && cd /opt/qBittorrent-${QBITTORRENT_RELEASE} \
    && ./configure CXXFLAGS="-std=c++14" --disable-gui && make -j$(nproc) && make install \
    && cd /opt \
    && rm -rf /opt/* \
    && apt -y purge \
    ca-certificates \
    curl \
    g++ \
    jq \
    libboost-system-dev \
    libssl-dev \
    make \
    pkg-config \
    qtbase5-dev \
    qttools5-dev \
    zlib1g-dev \
    && apt-get clean \
    && apt -y autoremove \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

# Install WireGuard, OpenVPN and other dependencies for running qbittorrent-nox and the container scripts
RUN echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable-wireguard.list \ 
    && printf 'Package: *\nPin: release a=unstable\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-unstable \
    && apt update \
    && apt -y install --no-install-recommends \
    ca-certificates \
    curl \
    dos2unix \
    inetutils-ping \
    ipcalc \
    iptables \
    kmod \
    libboost-system1.67.0 \
    libqt5network5 \
    libqt5xml5 \
    libssl1.1 \
    moreutils \
    net-tools \
    openresolv \
    openvpn \
    procps \
    wireguard-tools \
    && apt-get clean \
    && apt -y autoremove \
    && rm -rf \
    /var/lib/apt/lists/* \
    /tmp/* \
    /var/tmp/*

RUN echo "deb http://deb.debian.org/debian/ buster non-free" > /etc/apt/sources.list.d/non-free-unrar.list \
    && printf 'Package: *\nPin: release a=non-free\nPin-Priority: 150\n' > /etc/apt/preferences.d/limit-non-free \
    && apt update \
    && apt -y upgrade \
    && apt -y install --no-install-recommends \
    unrar \
    p7zip-full \
    unzip \
    zip \
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