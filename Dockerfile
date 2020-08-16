FROM debian:10-slim

WORKDIR /opt

RUN usermod -u 99 nobody

# Make directories
RUN mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent

RUN apt update \
    && apt -y upgrade \
    && apt -y install --no-install-recommends \
    curl \
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
    && QBITTORRENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/qBittorrent/qBittorrent/tags" | awk '/name/{print $4;exit}' FS='[""]') \
    && LIBTORRENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/arvidn/libtorrent/releases" | awk '/tag_name/{print $4;exit}' FS='[""]') \
    && curl -o /opt/qBittorrent-${QBITTORRENT_RELEASE}.tar.gz -L https://api.github.com/repos/qbittorrent/qBittorrent/tarball/${QBITTORRENT_RELEASE} \
    && curl -o /opt/libtorrent-${LIBTORRENT_RELEASE}.tar.gz -L https://api.github.com/repos/arvidn/libtorrent/tarball/${LIBTORRENT_RELEASE} \
    && tar -xvzf /opt/qBittorrent-${QBITTORRENT_RELEASE}.tar.gz \
    && tar -xvzf /opt/libtorrent-${LIBTORRENT_RELEASE}.tar.gz \
    && rm /opt/*.tar.gz \
    && cd /opt/arvidn-libtorrent-* \
    && ./autotool.sh \
    && ./configure --disable-debug --enable-encryption && make clean && make -j$(nproc) && make install \
    && cd /opt/qbittorrent-* \
    && ./configure --disable-gui && make -j$(nproc) && make install \
    && cd /opt \
    && rm -rf /opt/* \
    && apt -y purge \
    curl \
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
