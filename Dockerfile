# ==============================================================================
# CustomC-OS: Operativsystem med MSB Bootloader & Terminal
# ==============================================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm-256color

# Installer QEMU, NASM og kjerne-verktoy
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    nasm \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /env

# Kopier kildekode og disk-image
COPY boot/ /env/boot/
COPY kernel/ /env/kernel/
COPY custom_c_os.img /env/custom_c_os.img

# Standard kommando: Start CustomC-OS direkte i terminalen via QEMU
CMD ["qemu-system-i386", "-fda", "/env/custom_c_os.img", "-boot", "a", "-nographic", "-monitor", "none"]
