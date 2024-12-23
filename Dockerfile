FROM ubuntu AS kernel

ARG kernel="linux-image-kvm"
WORKDIR /kernel
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "$kernel"
RUN basename -- /lib/modules/* > version \
  && cp -v "/boot/vmlinuz-$(cat version)" kernel \
  && cp -v "/boot/config-$(cat version)" config

# $modules are present and loaded on-demand by the kernel using modprobe,
# see <https://github.com/torvalds/linux/blob/5e321ded302da4d8c5d5dd953423d9b748ab3775/kernel/kmod.c#L61>.
ARG modules="iso9660 udf"
# $modules_load are loaded by init on start-up
ARG modules_load="loop fuse msdos vfat 9p 9p-virtio"
WORKDIR /modules
# See https://www.kernel.org/doc/Documentation/kbuild/kbuild.txt
RUN cp -v --parents "/lib/modules/$(cat /kernel/version)/modules.order" .
RUN cp -v --parents "/lib/modules/$(cat /kernel/version)/modules.builtin" .
RUN modprobe -aDS "$(cat /kernel/version)" $modules_load \
  | awk '!seen[$0]++' | sed "s/^builtin /# &/;s/^insmod //" >> /tmp/modules \
  && cp -v --parents $(sed "/^#/d" /tmp/modules) . \
  && mkdir -p etc \
  && sed -E 's/^[^#].+\///;s/\.ko(\.zst)?\s*$//' /tmp/modules > etc/modules
RUN modprobe -aDS "$(cat /kernel/version)" $modules \
  | awk '!seen[$0]++' | sed "s/^builtin /# &/" \
  | sed "/^#/d;s/^insmod //" \
  | xargs --no-run-if-empty cp -v --parents -t .
RUN cp -v --parents "/lib/modules/$(cat /kernel/version)/kernel/fs/nls/"*.ko* .
RUN find -type f -name '*.zst' | xargs --no-run-if-empty zstd -d --rm

###############################################################################

FROM busybox as initrd
# initrd needs /sbin/modprobe and depmod
RUN ln -s /bin /sbin
COPY --from=kernel /modules .
RUN depmod "$(basename -- /lib/modules/*/)"
COPY init /init

###############################################################################

FROM ubuntu as image
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cpio grub2 grub-efi-amd64-bin xorriso mtools

WORKDIR /output
COPY --from=kernel /kernel .
RUN rm version

WORKDIR /initrd
COPY --from=initrd / .
RUN find . | cpio -o -H newc | gzip -c > /output/initrd

WORKDIR /image
RUN ln /output/* .
RUN mkdir -p boot/grub && printf 'linux /kernel\ninitrd /initrd\nboot\n' > boot/grub/grub.cfg
RUN grub-mkrescue -o /output/image.iso .
RUN chmod -R +r /output

###############################################################################

FROM scratch
COPY --from=image /output /
