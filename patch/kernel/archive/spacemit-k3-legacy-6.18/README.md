Patches for the spacemit-k3 legacy kernel only.

Tree: spacemit-com/linux-6.18, branch k3-br-v1.0.y.

This tree declares the 3-argument xsk_tx_metadata_request() and its ethercat
driver already calls it correctly, so the 4-arg conversion in
spacemit-k3-current-6.18 must never reach it.
