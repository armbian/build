#!/bin/bash

# this is required for NFS boot to prevent deconfiguring the network on shutdown
[[ $RELEASE == xenial || $RELEASE == stretch || $RELEASE == bionic ]] && [[ -f $upperdir/etc/network/interfaces.default ]] && \
sed -i 's/#no-auto-down/no-auto-down/g' $upperdir/etc/network/interfaces.default

# fixing permissions (basic), reference: dh_fixperms
find $upperdir -print0 2>/dev/null | xargs -0r chown --no-dereference 0:0
find $upperdir ! -type l -print0 2>/dev/null | xargs -0r chmod 'go=rX,u+rw,a-s'
