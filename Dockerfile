# Adapted from SignalWire's FreeSWITCH Dockerfile.
#
# Three stages:
#   builder - compiles FreeSWITCH and its libraries, then
#             stages the installed files (stripped of debug symbols, no
#             headers, static libraries or sources) under /stage.
#   awscli  - installs AWS CLI v2 and drops what `aws s3 mv` never touches.
#   runtime - debian:bookworm-slim with only the shared libraries and tools
#             FreeSWITCH, the Lua hooks and /scripts actually use.
# The compiler, -dev packages, git and the source trees stay in the builder
# stage, which is what took the image from ~3.7 GB to ~380 MB.

FROM debian:bookworm AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install git

RUN DEBIAN_FRONTEND=noninteractive apt-get -yq install \
# build
    build-essential cmake automake autoconf 'libtool-bin|libtool' pkg-config \
# general
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev uuid-dev \
# core
    libpcre2-dev libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
# core codecs
    libogg-dev libspeex-dev libspeexdsp-dev \
# mod_enum
    libldns-dev \
# mod_python3
    python3-dev \
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
# music-on-hold download
    curl

RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/freeswitch_v1.11.3.tar.gz -O /usr/src/freeswitch_v1.11.3.tar.gz \
    && mkdir -p /usr/src/freeswitch \
    && tar -xzf /usr/src/freeswitch_v1.11.3.tar.gz -C /usr/src/freeswitch --strip-components=1 \
    && rm -rf /usr/src/freeswitch_v1.11.3.tar.gz
RUN mkdir -p /usr/src/libs
# This tarball keeps its .git directory, and is extracted with --no-same-owner
# so the tree is root-owned: libks's CMakeLists generates a Debian changelog via
# `git log` and needs the previous tag reachable, and git refuses to run in a
# repo owned by another uid.
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/libks_v2.0.11.tar.gz -O /usr/src/libs/libks_v2.0.11.tar.gz \
    && mkdir -p /usr/src/libs/libks \
    && tar --no-same-owner -xzf /usr/src/libs/libks_v2.0.11.tar.gz -C /usr/src/libs/libks --strip-components=1 \
    && rm -rf /usr/src/libs/libks_v2.0.11.tar.gz
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/sofia-sip_v1.13.18.tar.gz -O /usr/src/libs/sofia-sip_v1.13.18.tar.gz \
    && mkdir -p /usr/src/libs/sofia-sip \
    && tar -xzf /usr/src/libs/sofia-sip_v1.13.18.tar.gz -C /usr/src/libs/sofia-sip --strip-components=1 \
    && rm -rf /usr/src/libs/sofia-sip_v1.13.18.tar.gz
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/spandsp_v3.1.1.tar.gz -O /usr/src/libs/spandsp_v3.1.1.tar.gz \
    && mkdir -p /usr/src/libs/spandsp \
    && tar -xzf /usr/src/libs/spandsp_v3.1.1.tar.gz -C /usr/src/libs/spandsp --strip-components=1 \
    && rm -rf /usr/src/libs/spandsp_v3.1.1.tar.gz
RUN wget -nv https://comcent-oss-artifacts.s3.amazonaws.com/downloads/signalwire-c_v2.0.0.tar.gz -O /usr/src/libs/signalwire-c_v2.0.0.tar.gz \
    && mkdir -p /usr/src/libs/signalwire-c \
    && tar -xzf /usr/src/libs/signalwire-c_v2.0.0.tar.gz -C /usr/src/libs/signalwire-c --strip-components=1 \
    && rm -rf /usr/src/libs/signalwire-c_v2.0.0.tar.gz

RUN cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/spandsp && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/signalwire-c && PKG_CONFIG_PATH=/usr/lib/pkgconfig cmake . -DCMAKE_INSTALL_PREFIX=/usr && make install

# Enable modules
# FreeSWITCH v1.10.10
RUN cd /usr/src/freeswitch \
    && sed -i 's|#formats/mod_shout|formats/mod_shout|' /usr/src/freeswitch/build/modules.conf.in \
    && sed -i 's|#xml_int/mod_xml_curl|xml_int/mod_xml_curl|' /usr/src/freeswitch/build/modules.conf.in \
    && sed -i 's|#event_handlers/mod_amqp|event_handlers/mod_amqp|' /usr/src/freeswitch/build/modules.conf.in \
    && sed -i -E 's|^([a-z_]+/mod_av)$|#\1|' /usr/src/freeswitch/build/modules.conf.in \
    && ./bootstrap.sh -j \
    && ./configure \
    && make -j`nproc` && make install

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

# Stage what the runtime image needs: the FreeSWITCH install tree and the four
# libraries built above. Those land in /usr/lib, except spandsp, whose
# configure picks /usr/lib/x86_64-linux-gnu on amd64, so each is copied from
# wherever it was installed, keeping its directory. Headers, pkgconfig, static
# libraries and libtool archives are only for building, and the stock conf is
# replaced by etc/ in the runtime stage. Everything was compiled with -g, so
# stripping is most of the saving on what remains.
RUN set -eux; \
    mkdir -p /stage/usr/local; \
    cp -a /usr/local/freeswitch /stage/usr/local/; \
    for lib in libks2 libsignalwire_client2 libsofia-sip-ua libspandsp; do \
        found=$(find /usr/lib -maxdepth 2 -name "$lib.so*"); \
        test -n "$found"; \
        cp -a --parents $found /stage/; \
    done; \
    cd /stage/usr/local/freeswitch; \
    rm -rf include lib/pkgconfig conf/*; \
    find . \( -name '*.a' -o -name '*.la' \) -delete; \
    find /stage -type f | while read -r f; do \
        if [ "$(head -c4 "$f" | tail -c3)" = "ELF" ]; then strip --strip-unneeded "$f"; fi; \
    done

# Add awscli — match the image architecture. A hardcoded aarch64 binary on the
# amd64 image made `aws s3 mv` fail silently in s3_upload_bg.sh, so recording
# uploads never completed and call stories were never persisted.
#
# s3_upload_bg.sh only runs `aws s3 mv`, so the install is cut down to that:
# the service models other than S3 and the ones credential providers call
# (STS for assume-role/web identity, SSO, SSO-OIDC, sign-in), the command
# examples and the tab-completion index and binary all go, and the bundled
# shared libraries are stripped. That takes it from ~270 MB to ~45 MB while
# keeping the real CLI, so endpoint, credential and error handling are
# unchanged.
FROM debian:bookworm-slim AS awscli

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -yq install --no-install-recommends \
        ca-certificates curl unzip binutils \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip; \
    cd /tmp && unzip -q awscliv2.zip && ./aws/install && rm -rf /tmp/awscliv2.zip /tmp/aws; \
    dist=/usr/local/aws-cli/v2/current/dist; \
    rm -rf "$dist/awscli/examples" "$dist/awscli/data/ac.index" \
        "$dist/aws_completer" /usr/local/aws-cli/v2/current/bin/aws_completer \
        /usr/local/bin/aws_completer; \
    test -d "$dist/awscli/botocore/data/s3"; \
    find "$dist/awscli/botocore/data" -mindepth 1 -maxdepth 1 -type d \
        ! -name s3 ! -name sts ! -name sso ! -name sso-oidc ! -name signin \
        -exec rm -rf {} +; \
    find "$dist" -type f -name '*.so*' -exec strip --strip-unneeded {} +; \
    aws --version; \
    aws s3 mv --dryrun /etc/hostname s3://bucket/key

FROM debian:bookworm-slim

# Runtime shared libraries, found by running ldd over every binary and module
# under /usr/local/freeswitch and the four libraries built in the builder
# stage, then mapping each to its Debian package. The check at the end of the
# next RUN fails the build if any of them is missing one.
# Then the tools the image runs outside FreeSWITCH:
#   sox, libsox-fmt-base  s3_upload_bg.sh splices silence in at hold positions
#   python3-minimal       s3_upload_bg.sh fires the upload-completed event over ESL
#   ca-certificates       HTTPS from mod_xml_curl/mod_signalwire and the AWS CLI
#   media-types           /etc/mime.types, which the AWS CLI reads to set the
#                         uploaded recording's Content-Type (audio/x-wav)
#   wget                  docker-entrypoint.sh's optional sound download
#   curl                  kept for ad-hoc debugging, as before
#   tcpdump               SIP/RTP debugging on the host, as before
#   openssl               bin/gentls_cert
#   tzdata, netbase, procps  timezones, /etc/services, ps/top
# dnsutils (dig) is left out: nothing here calls it, and it brings ~45 MB of
# libicu/bind9 libraries. `getent hosts <name>` still resolves names.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get -yq install --no-install-recommends \
        libbsd0 libcairo2 libcurl4 libedit2 libexpat1 libflac12 libfreetype6 \
        libjpeg62-turbo libldns3 libltdl7 liblua5.2-0 libmp3lame0 libmpg123-0 \
        libodbc2 libogg0 libopus0 libpcre2-8-0 libpng16-16 libpq5 librabbitmq4 \
        libshout3 libsndfile1 libspeex1 libspeexdsp1 libsqlite3-0 libssl3 \
        libstdc++6 libtiff6 libtpl0 libuuid1 libvorbis0a libvorbisenc2 zlib1g \
        sox libsox-fmt-base python3-minimal ca-certificates media-types \
        wget curl tcpdump openssl tzdata netbase procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /stage/ /
COPY --from=awscli /usr/local/aws-cli /usr/local/aws-cli

# The entrypoint used to start FreeSWITCH from its build tree
# (/usr/src/freeswitch), which is not in this image. Keep those paths working
# for anything outside the image that still calls them.
RUN set -eux; \
    ldconfig; \
    ln -s /usr/local/aws-cli/v2/current/bin/aws /usr/local/bin/aws; \
    mkdir -p /usr/src/freeswitch; \
    ln -s /usr/local/freeswitch/bin/freeswitch /usr/src/freeswitch/freeswitch; \
    ln -s /usr/local/freeswitch/bin/fs_cli /usr/src/freeswitch/fs_cli; \
    missing=$(find /usr/local/freeswitch /usr/lib -type f \( -path '/usr/local/*' \
        -o -name 'libks2.so*' -o -name 'libsignalwire_client2.so*' \
        -o -name 'libsofia-sip-ua.so*' -o -name 'libspandsp.so*' \) \
        -exec sh -c 'head -c4 "$1" | tail -c3 | grep -q ELF && ldd "$1" | grep "not found" | sed "s|^|$1: |"' _ {} \; ); \
    if [ -n "$missing" ]; then echo "$missing"; exit 1; fi; \
    aws --version; sox --version; python3 -c 'import socket'

COPY ./scripts /scripts/
RUN chmod +x /scripts/*

COPY etc /usr/local/freeswitch/conf/

# HEALTHCHECK --interval=15s --timeout=5s \
#     CMD  /scripts/healthcheck.sh

ENV PATH="/usr/local/freeswitch/bin:${PATH}"

ENTRYPOINT ["/scripts/docker-entrypoint.sh"]
