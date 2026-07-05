FROM debian:bullseye
MAINTAINER Andrey Volk <andrey@signalwire.com>

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install git

RUN DEBIAN_FRONTEND=noninteractive apt-get -yq install \
# network tools
    tcpdump dnsutils \
# audio post-processing (used by on_record_stop.lua to splice silence into
# recordings at WebRTC hold positions)
    sox \
# build
    build-essential cmake automake autoconf 'libtool-bin|libtool' pkg-config \
# general
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev uuid-dev \
# core
    libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
# core codecs
    libogg-dev libspeex-dev libspeexdsp-dev \
# mod_enum
    libldns-dev \
# mod_python3
    python3-dev \
# mod_av
    libavformat-dev libswscale-dev libavresample-dev \
# mod_lua
    liblua5.2-dev \
# mod_opus
    libopus-dev \
# mod_pgsql
    libpq-dev \
# mod_sndfile
    libsndfile1-dev libflac-dev libogg-dev libvorbis-dev \
# mod_shout
    libshout3-dev libmpg123-dev libmp3lame-dev \
# wget
    wget \
# mod_amqp
    librabbitmq4 librabbitmq-dev \
# s3 cli
    curl unzip

RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/freeswitch_v1.10.10.tar.gz -O /usr/src/freeswitch_v1.10.10.tar.gz \
    && mkdir -p /usr/src/freeswitch \
    && tar -xzf /usr/src/freeswitch_v1.10.10.tar.gz -C /usr/src/freeswitch --strip-components=1 \
    && rm -rf /usr/src/freeswitch_v1.10.10.tar.gz
RUN mkdir -p /usr/src/libs
RUN git clone https://github.com/signalwire/libks /usr/src/libs/libks
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/sofia-sip_v1.13.17.tar.gz -O /usr/src/libs/sofia-sip_v1.13.17.tar.gz \
    && mkdir -p /usr/src/libs/sofia-sip \
    && tar -xzf /usr/src/libs/sofia-sip_v1.13.17.tar.gz -C /usr/src/libs/sofia-sip --strip-components=1 \
    && rm -rf /usr/src/libs/sofia-sip_v1.13.17.tar.gz
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/spandsp_67d2455.tar.gz -O /usr/src/libs/spandsp_67d2455.tar.gz \
    && mkdir -p /usr/src/libs/spandsp \
    && tar -xzf /usr/src/libs/spandsp_67d2455.tar.gz -C /usr/src/libs/spandsp --strip-components=1 \
    && rm -rf /usr/src/libs/spandsp_67d2455.tar.gz
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/signalwire-c_v2.0.0.tar.gz -O /usr/src/libs/signalwire-c_v2.0.0.tar.gz \
    && mkdir -p /usr/src/libs/signalwire-c \
    && tar -xzf /usr/src/libs/signalwire-c_v2.0.0.tar.gz -C /usr/src/libs/signalwire-c --strip-components=1 \
    && rm -rf /usr/src/libs/signalwire-c_v2.0.0.tar.gz

RUN cd /usr/src/libs/libks && git fetch --tags && git checkout v2.0.3 && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/signalwire-c && PKG_CONFIG_PATH=/usr/lib/pkgconfig cmake . -DCMAKE_INSTALL_PREFIX=/usr && make install

# Enable modules
# FreeSWITCH v1.10.10
RUN cd /usr/src/freeswitch \
    && sed -i 's|#formats/mod_shout|formats/mod_shout|' /usr/src/freeswitch/build/modules.conf.in \
    && sed -i 's|#xml_int/mod_xml_curl|xml_int/mod_xml_curl|' /usr/src/freeswitch/build/modules.conf.in \
    && sed -i 's|#event_handlers/mod_amqp|event_handlers/mod_amqp|' /usr/src/freeswitch/build/modules.conf.in \
    && ./bootstrap.sh -j \
    && ./configure \
    && make -j`nproc` && make install

# Cleanup the image
RUN apt-get clean && \
    apt-get autoclean && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Uncomment to cleanup even more
#RUN rm -rf /usr/src/*

# Add awscli — match the image architecture. A hardcoded aarch64 binary on the
# amd64 image made `aws s3 mv` fail silently in s3_upload_bg.sh, so recording
# uploads never completed and call stories were never persisted.
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  ./aws/install && \
  rm -rf awscliv2.zip aws


COPY ./scripts /scripts/
RUN chmod +x /scripts/*

RUN rm -rf /usr/local/freeswitch/conf/*
COPY etc /usr/local/freeswitch/conf/

# Install the official FreeSWITCH 8 kHz music-on-hold pack so
# local_stream://moh resolves to real audio instead of falling back to the
# missing "default" source.
RUN mkdir -p /usr/local/freeswitch/sounds/music/8000 \
    && curl -fsSL \
        https://files.freeswitch.org/releases/sounds/freeswitch-sounds-music-8000-1.0.52.tar.gz \
        -o /tmp/moh.tar.gz \
    && tar -xzf /tmp/moh.tar.gz -C /tmp \
    && mv /tmp/music/8000/*.wav /usr/local/freeswitch/sounds/music/8000/ \
    && rm -rf /tmp/music /tmp/moh.tar.gz
# HEALTHCHECK --interval=15s --timeout=5s \
#     CMD  /scripts/healthcheck.sh

ENV PATH="/usr/src/freeswitch:${PATH}"

ENTRYPOINT ["/scripts/docker-entrypoint.sh"]
