for i in {9..50}; do if [ -e /dev/loop$i ]; then continue; fi; \
mknod /dev/loop$i b 7 $i; chown --reference=/dev/loop0 /dev/loop$i; \
chmod --reference=/dev/loop0 /dev/loop$i; done
