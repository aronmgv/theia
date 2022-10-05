FROM ubuntu:22.04 as common

ENV DEBIAN_FRONTEND noninteractive

ARG NODE_VERSION=18.10.0
ENV NODE_VERSION $NODE_VERSION
ENV YARN_VERSION 1.22.19

# Common deps
RUN apt-get update && \
    apt-get -y install build-essential \
                       curl \
                       git \
                       gpg \
                       python3 \
                       wget \
                       xz-utils \
                       sudo \
                       libsecret-1-dev \
    && \
    apt-get clean && \
    apt-get autoremove -y && \
    rm -rf /var/cache/apt/* && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

## User account
RUN adduser --disabled-password --gecos '' theia && \
    adduser theia sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# gpg keys listed at https://github.com/nodejs/node#release-keys
RUN set -ex \
    && for key in \	
	4ED778F539E3634C779C87C6D7062848A1AB005C \
	141F07595B7B3FFE74309A937405533BE57C7D57 \
	94AE36675C464D64BAFA68DD7434390BDBE9B9C5 \
	74F12602B6F1C4E913FAA37AD3A89613643B6201 \
	71DCFD284A79C3B38668286BC97EC7A07EDE3FC1 \
	61FC681DFB92A079F1685E77973F295594EC4689 \
	8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
	C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
	890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
	C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
	DD8F2338BAE7501E3DD5AC78C273792F7D83545D \
	A48C2BEE680E841632CD4E44F07496B3EB3C1762 \
	108F52B48DB57BB0CC439B2997B01419BD92F80A \
	B9E2F5981AA6E0CD28160D9FF13993A75599653C \
    ; do \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-key "$key" || \
    gpg --batch --keyserver keys.openpgp.org --recv-key "$key" || \
    gpg --batch --keyserver pgp.mit.edu --recv-keys "$key" || \
    gpg --batch --keyserver keyserver.pgp.com --recv-keys "$key" ; \
    done

RUN ARCH= && dpkgArch="$(dpkg --print-architecture)" \
    && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
    esac \
    && curl -SLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
    && curl -SLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
    && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
    && grep " node-v$NODE_VERSION-linux-$ARCH.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs

RUN set -ex \
    && for key in \
    6A010C5166006599AA17F08146C2130DFD2497F5 \
    ; do \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-key "$key" || \
    gpg --batch --keyserver keys.openpgp.org --recv-key "$key" || \
    gpg --batch --keyserver pgp.mit.edu --recv-key "$key" || \
    gpg --batch --keyserver keyserver.pgp.com --recv-keys "$key" ; \
    done \
    && curl -fSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
    && curl -fSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
    && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
    && mkdir -p /opt/yarn \
    && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/yarn --strip-components=1 \
    && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarn \
    && ln -s /opt/yarn/bin/yarn /usr/local/bin/yarnpkg \
    && rm yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz

FROM common as theia

ARG GITHUB_TOKEN

# Use "latest" or "next" version for Theia packages
ARG version=latest

# Optionally build a striped Theia application with no map file or .ts sources.
# Makes image ~150MB smaller when enabled
ARG strip=false
ENV strip=$strip

USER theia
WORKDIR /home/theia
ADD $version.package.json ./package.json

RUN if [ "$strip" = "true" ]; then \
yarn --pure-lockfile && \
    NODE_OPTIONS="--max_old_space_size=4096" yarn theia build && \
    yarn theia download:plugins --ignore-errors && \
    yarn --production && \
    yarn autoclean --init && \
    echo *.ts >> .yarnclean && \
    echo *.ts.map >> .yarnclean && \
    echo *.spec.* >> .yarnclean && \
    yarn autoclean --force && \
    yarn cache clean \
;else \
yarn --cache-folder ./ycache && rm -rf ./ycache && \
     NODE_OPTIONS="--max_old_space_size=4096" yarn theia build && yarn theia download:plugins --ignore-errors \
;fi

FROM common

# Developer tools

# LSPs

## Go
ENV GO_VERSION=1.19.2 \
    GOOS=linux \
    GOARCH=amd64 \
    GOROOT=/usr/local/go \
    GOPATH=/usr/local/go-packages
ENV PATH=$GOROOT/bin:$GOPATH/bin:$PATH

# Install Go
# https://go.dev/doc/install
RUN curl -fsSL https://storage.googleapis.com/golang/go$GO_VERSION.$GOOS-$GOARCH.tar.gz | tar -C /usr/local -xzv

# VS Code Go Tools https://github.com/golang/vscode-go/blob/master/docs/tools.md
RUN go install github.com/uudashr/gopkgs/cmd/gopkgs@v2 && \
    go install github.com/ramya-rao-a/go-outline@latest && \
    go install github.com/cweill/gotests/gotests@latest && \
    go install github.com/fatih/gomodifytags@latest && \
    go install github.com/josharian/impl@latest && \
    go install github.com/haya14busa/goplay/cmd/goplay@latest && \
    go install github.com/go-delve/delve/cmd/dlv@latest && \
    GO111MODULE=on go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest && \
                   go install golang.org/x/tools/gopls@latest

ENV PATH=$PATH:$GOPATH/bin

# Java
RUN apt-get update && apt-get -y install openjdk-18-jdk maven gradle

# C/C++
# public LLVM PPA, development version of LLVM
ARG LLVM=14

RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:ubuntu-toolchain-r/test && \
    apt-get remove -y software-properties-common

RUN wget -O - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - && \
    echo "deb http://apt.llvm.org/bionic/ llvm-toolchain-bionic main" > /etc/apt/sources.list.d/llvm.list && \
    apt-get update && \
    apt-get install -y \
                       clang-tools-$LLVM \
                       clangd-$LLVM \
                       clang-tidy-$LLVM \
                       gcc-multilib \
                       g++-multilib \
                       gdb && \
    ln -s /usr/bin/clang-$LLVM /usr/bin/clang && \
    ln -s /usr/bin/clang++-$LLVM /usr/bin/clang++ && \
    ln -s /usr/bin/clang-cl-$LLVM /usr/bin/clang-cl && \
    ln -s /usr/bin/clang-cpp-$LLVM /usr/bin/clang-cpp && \
    ln -s /usr/bin/clang-tidy-$LLVM /usr/bin/clang-tidy && \
    ln -s /usr/bin/clangd-$LLVM /usr/bin/clangd

# Install latest stable CMake
ARG CMAKE_VERSION=3.18.1

RUN wget "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-x86_64.sh" && \
    chmod a+x cmake-$CMAKE_VERSION-Linux-x86_64.sh && \
    ./cmake-$CMAKE_VERSION-Linux-x86_64.sh --prefix=/usr/ --skip-license && \
    rm cmake-$CMAKE_VERSION-Linux-x86_64.sh

# Python 2-3
RUN apt-get update \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get install -y python2 python2-dev python-pip \
    && apt-get install -y python3 python3-dev python3-pip \
    && apt-get remove -y software-properties-common \
	&& apt-get autoremove -y \
    && pip install --upgrade pip --user \
    && pip3 install --upgrade pip --user \
    && pip3 install python-language-server flake8 autopep8

# .NET Core SDK
ARG DOTNET_VERSION=6.0
# Disables .NET telemetry
ENV DOTNET_CLI_TELEMETRY_OPTOUT 1
# Suppresses .NET welcome message
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE 1

RUN curl -SLO "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-$DOTNET_VERSION

# PHP
ARG PHP_VERSION=8.1

RUN apt-get update \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:ondrej/php \
    && apt-get install -y curl php-yaml php-xdebug php$PHP_VERSION php$PHP_VERSION-cli php$PHP_VERSION-mbstring unzip php$PHP_VERSION-common \
    && apt-get remove -y software-properties-common
RUN echo '[XDebug]\n\
xdebug.remote_enable = 1\n\
xdebug.remote_autostart = 1' >> /etc/php/$PHP_VERSION/mods-available/xdebug.ini
RUN curl -s -o composer-setup.php https://getcomposer.org/installer \
    && php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
    && rm composer-setup.php

# Ruby
RUN apt-get update && apt-get -y install ruby ruby-dev zlib1g-dev && \
    gem install solargraph

# Dart
ENV DART_VERSION 2.18.2

RUN \
  apt-get update && apt-get install --no-install-recommends -y -q gnupg2 curl git ca-certificates apt-transport-https openssh-client && \
  curl https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - && \
  curl https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_stable.list > /etc/apt/sources.list.d/dart_stable.list && \
  curl https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_testing.list > /etc/apt/sources.list.d/dart_testing.list && \
  curl https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_unstable.list > /etc/apt/sources.list.d/dart_unstable.list && \
  apt-get update && \
  apt-get install dart=$DART_VERSION-1

ENV DART_SDK /usr/lib/dart
ENV PATH $DART_SDK/bin:/theia/.pub-cache/bin:$PATH

WORKDIR /home/theia

COPY --from=theia --chown=theia:theia /home/theia /home/theia

RUN apt-get update && apt-get -y install libsecret-1-0

RUN chmod g+rw /home && \
    mkdir -p /home/project && \
    mkdir -p /home/theia/.pub-cache/bin && \
    mkdir -p /usr/local/cargo && \
    mkdir -p /usr/local/go && \
    mkdir -p /usr/local/go-packages && \
    chown -R theia:theia /home/project && \
    chown -R theia:theia /home/theia/.pub-cache/bin && \
    chown -R theia:theia /usr/local/cargo && \
    chown -R theia:theia /usr/local/go && \
    chown -R theia:theia /usr/local/go-packages

# Theia application
RUN apt-get clean && \
  apt-get autoremove -y && \
  rm -rf /var/cache/apt/* && \
  rm -rf /var/lib/apt/lists/* && \
  rm -rf /tmp/*

# Change permissions to make the `yang-language-server` executable.
RUN chmod +x ./plugins/yangster/extension/server/bin/yang-language-server

USER theia
EXPOSE 3000
# Configure Theia
ENV SHELL=/bin/bash \
    THEIA_DEFAULT_PLUGINS=local-dir:/home/theia/plugins  \
    # Configure user Go path
    GOPATH=/home/project

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

ENTRYPOINT [ "node", "/home/theia/src-gen/backend/main.js", "/home/project", "--hostname=0.0.0.0" ]