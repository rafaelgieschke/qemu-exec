FROM ubuntu AS kernel

ARG kernel="linux-image-kvm"
WORKDIR /kernel
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "$kernel"
RUN basename -- /lib/modules/* > version \
  && cp -v "/boot/vmlinuz-$(cat version)" kernel \
  && cp -v "/boot/config-$(cat version)" config

ARG modules="loop iso9660"
WORKDIR /modules
RUN for module in $modules; do modprobe -DS "$(cat /kernel/version)" "$module" \
  | sed "s/^builtin /# &/" >> init-insmod; done \
  && cp -v --parents $(sed "/^#/d;s/^insmod //" init-insmod) .


FROM busybox as initrd
COPY init /init


FROM ubuntu as image
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cpio grub2 xorriso

WORKDIR /output
COPY --from=kernel /kernel .

WORKDIR /initrd
COPY --from=initrd / .
COPY --from=kernel /modules .
RUN find . | cpio -o -H newc | gzip -c > /output/initrd

WORKDIR /image
RUN ln /output/* .
RUN mkdir -p boot/grub && printf 'linux /kernel\ninitrd /initrd\nboot\n' > boot/grub/grub.cfg
RUN grub-mkrescue -o /output/image.iso .

FROM scratch
COPY --from=image /output /
