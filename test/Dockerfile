FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    curl git bash ca-certificates sudo shellcheck \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash titan && echo 'titan ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
USER titan
WORKDIR /home/titan
