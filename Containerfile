FROM docker.io/library/debian:unstable

ARG DEBIAN_FRONTEND=noninteractive
# Antipattern but we are doing this since `apt`/`debootstrap` does not allow chroot installation on unprivileged podman builds
ENV DEV_DEPS="libzstd-dev libssl-dev pkg-config libostree-dev curl git build-essential meson libfuse3-dev go-md2man dracut whois"

RUN rm /etc/apt/apt.conf.d/docker-gzip-indexes /etc/apt/apt.conf.d/docker-no-languages && \
    apt update -y && \
    apt install -y $DEV_DEPS ostree

RUN --mount=type=tmpfs,dst=/tmp --mount=type=tmpfs,dst=/root \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal -y && \
    git clone https://github.com/bootc-dev/bootc.git /tmp/bootc && \
    cd /tmp/bootc && \
    CARGO_FEATURES="composefs-backend" PATH="/root/.cargo/bin:$PATH" make bin && \
    make install-all && \
    make install-initramfs-dracut && \
    git clone https://github.com/p5/coreos-bootupd.git -b sdboot-support /tmp/bootupd && \
    cd /tmp/bootupd && \
    /root/.cargo/bin/cargo build --release --bins --features systemd-boot && \
    make install


# Install required packages for bootc images
ENV DRACUT_NO_XATTR=1
RUN apt install -y \
  btrfs-progs \
  dosfstools \
  e2fsprogs \
  fdisk \
  firmware-linux-free \
  linux-image-generic \
  skopeo \
  systemd \
  systemd-boot* \
  xfsprogs

RUN sh -c 'export KERNEL_VERSION="$(basename "$(find /usr/lib/modules -maxdepth 1 -type d | grep -v -E "*.img" | tail -n 1)")" && \
    dracut --force --no-hostonly --reproducible --zstd --verbose --kver "$KERNEL_VERSION"  "/usr/lib/modules/$KERNEL_VERSION/initramfs.img" && \
    cp /boot/vmlinuz-$KERNEL_VERSION "/usr/lib/modules/$KERNEL_VERSION/vmlinuz"'



RUN apt remove -y $DEV_DEPS && \
    apt autoremove -y
ENV DEV_DEPS=

# Update useradd default to /var/home instead of /home for User Creation
RUN sed -i 's|^HOME=.*|HOME=/var/home|' "/etc/default/useradd"


COPY files/ /

RUN apt install -y --no-install-recommends \
  gnome-core \
  task-desktop \
  tasksel \
  network-manager-gnome \
  gnome-initial-setup

### Prepare final image
RUN rm -rf /var /boot && \
    ln -s /var/home /home && \
    ln -s /var/roothome /root && \
    ln -s /var/srv /srv && \
    ln -s sysroot/ostree ostree && \
    ln -s /var/usrlocal /usr/local && \
    mkdir -p /sysroot /var/home /boot && \
    rm -rf /var/log /home /root /usr/local /srv

RUN systemd-tmpfiles --create /usr/lib/tmpfiles.d/bootc.conf


# Necessary for `bootc install`
RUN mkdir -p /usr/lib/ostree && \
    printf  "[composefs]\nenabled = yes\n[sysroot]\nreadonly = true\n" | \
    tee "/usr/lib/ostree/prepare-root.conf"
# delete the root account from /etc/passwd and /etc/shadow
RUN passwd --delete root && \
    passwd --lock root


RUN bootc container lint
