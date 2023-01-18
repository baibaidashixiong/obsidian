FROM debian 
ARG user=zqz
LABEL maintainer="zqz" email="zqz.cn"
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list
RUN apt update && apt upgrade -y && \
        apt install -y vim tmux man && \
        apt install -y python3 python3-distutils python3-apt python3-gi && \
        apt install -y chrpath cpio cpp diffstat g++ gcc gawk git make patch wget lz4 libelf-dev libpulse-dev file zstd 
RUN  apt install -y libpulse-dev libncurses-dev libasound2-dev libattr1-dev libpcap-dev libcap-dev bison flex openssl iproute2 iptables iputils-ping procps sysstat 
RUN  apt install -y openjdk-11-jre v2ray && \
        # cd /bin && rm sh && ln -sf bash sh \
# 安装qemu依赖
        apt install -y locales && \
        apt install -y libvdeslirp-dev && \
        apt install -y sudo 
RUN ln -sf /etc/v2ray/geoip.dat /usr/bin/geoip.dat && ln -sf /etc/v2ray/geosite.dat /usr/bin/geosite.dat
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

RUN useradd --create-home --no-log-init --shell /bin/bash ${user} \
    && adduser ${user} sudo \
    && echo "${user}:zqz" | chpasswd \
    && usermod -a -G sudo ${user}
WORKDIR /home/${user}
RUN echo 'export ALL_PROXY=socks5://127.0.0.1:1080' >> /home/${user}/.bashrc
USER ${user}

