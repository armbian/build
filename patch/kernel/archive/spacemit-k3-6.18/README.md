Patches that apply to BOTH spacemit-k3 kernel branches.

legacy  = spacemit-com/linux-6.18, branch k3-br-v1.0.y (vendor tree)
current = gitlab.com/jmontleon/kernel-ark, branch fedora-6.18.y-riscv-k3.0

The two trees are only nominally the same version and their APIs differ.
A patch that touches an API one of them carries belongs in the per-branch
dir (spacemit-k3-legacy-6.18 / spacemit-k3-current-6.18), not here.
