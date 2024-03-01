FROM golang:1.22.0-alpine as rcon-cli_builder

ARG RCON_VERSION="0.10.3"
ARG RCON_TGZ_SHA1SUM=33ee8077e66bea6ee097db4d9c923b5ed390d583

WORKDIR /build

# install rcon
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ENV CGO_ENABLED=0
RUN wget -q https://github.com/gorcon/rcon-cli/archive/refs/tags/v${RCON_VERSION}.tar.gz -O rcon.tar.gz \
    && echo "${RCON_TGZ_SHA1SUM}" rcon.tar.gz | sha1sum -c - \
    && tar -xzvf rcon.tar.gz \
    && rm rcon.tar.gz \
    && mv rcon-cli-${RCON_VERSION}/* ./ \
    && rm -rf rcon-cli-${RCON_VERSION} \
    && go build -v ./cmd/gorcon

FROM busybox:latest as bash-linux

ARG UE4SS_VERSION="3.0.1"
WORKDIR /File
# RUN wget -q https://github.com/UE4SS-RE/RE-UE4SS/releases/download/v${UE4SS_VERSION}/zDEV-UE4SS_v${UE4SS_VERSION}.zip -O UE4SS.zip \
#     && unzip UE4SS.zip libUE4SS.so UE4SS-settings.ini
COPY ./zDEV-UE4SS.zip /File/UE4SS.zip

RUN unzip UE4SS.zip libUE4SS.so UE4SS-settings.ini \
    && rm -rf UE4SS.zip \
    && chown -R 1000:1000 /File/*
    # && mv /File/UE4SS-settings.ini /File/default-settings.ini

FROM reodwind/steamcmd:ubuntu-root as base-amd64

ARG TARGETARCH

FROM base-${TARGETARCH}

ENV USER steam
ENV UE4SSDIR=/home/steam/UE4SS
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=rcon-cli_builder /build/gorcon /usr/bin/rcon-cli

# copy ue4ss linux
RUN set -x \
        && su "${USER}" -c \
        "mkdir -p \"${UE4SSDIR}\" "

COPY --from=bash-linux /File/* /${UE4SSDIR}/

#copy scripts
COPY ./scripts /home/steam/server
RUN chmod +x /home/steam/server/*.sh \
    && mv /home/steam/server/restore.sh /usr/local/bin/restore \
    && apt-get update \
    && apt-get install -y gettext-base \
    && apt-get -y autoremove \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/* \
    && rm -rf /var/tmp/*

WORKDIR /home/steam/server

ENV HOME=/home/steam \
    PORT=8211\
    PUID=1000 \
    PGID=1000 \
    PLAYERS= \
    MULTITHREADING=true \
    COMMUNITY=true \
    PUBLIC_IP= \
    PUBLIC_PORT= \
    SERVER_PASSWORD= \
    SERVER_NAME= \
    ADMIN_PASSWORD= \
    UPDATE_ON_BOOT=true \
    RCON_ENABLED=true \
    RCON_PORT=25575 \
    QUERY_PORT=27015 \
    TZ=UTC \
    SERVER_DESCRIPTION= \
    BACKUP_ENABLED=true \
    UE4SS_ENABLED=true \
    UE4SS_MODSDIR=/palworld/Mods

HEALTHCHECK --start-period=5m \
    CMD pgrep "PalServer-Linux" > /dev/null || exit 1

EXPOSE ${PORT} ${RCON_PORT}
ENTRYPOINT ["/home/steam/server/init.sh"]

FROM base-${TARGETARCH} as palworld
WORKDIR /palworld