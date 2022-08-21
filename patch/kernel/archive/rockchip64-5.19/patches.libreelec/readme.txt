The patches in this directory are imported from LibreELEC project - https://libreelec.tv

Patches are available as general patches for rockchip armhf/aarch64 targets.
They can be consulted on their github repository:

- https://github.com/LibreELEC/LibreELEC.tv/tree/master/projects/Rockchip/patches/linux/default

LibreELEC patches are provided in mailbox format, but here they are expanded
into single items to handle them better in case of clashing or mainlining.

In case there is the need to rebase the LibreELEC patches as a whole, a simple technique is used.

First, the patches are applied using git am command to the root of the linux kernel 
(~/libreelec-patches is the directory where patches are stored)

~/linux-5.19.y$ git am ~/libreelec-patches/*.patch

The git am step will create one commit per each patch in each mailbox file.
In case of unapplicable patches, git am will stop and allow the user to to proper changes
to accomodate the failing patch; use git am --continue is you fixed the patch, or git am --skip
if you want to skip the patch.

Once git am step is completed, you can use git format-patch to produce patch in proper
format complete with commit comments and ready-to-go naming. origin/linux-5.19.y is
the starting commit, of course change it appropriately.

~/linux-5.19.y$ git format-patch origin/linux-5.19.y

This will produce several patch files that can be then moved in this directory.

A last step is to update the series files. Place in the main armbian family patch directory 
and then issue

ls patches.libreelec/*.patch > libreelec.series
cat libreelec.series armbian.series > series.conf

Then you're done!

