# Runners setup

Common tags: 

- self-hosted
- Linux
- X64
- ARM64
- local (local network)
- cache (mounted cache)
- big (16+ cores and 64Gb+ memory)
- small (< 16 cores and 64Gb+ memory)

# Preparing GPG

use gpg1 otherwise signing fails

# Preparing Runner

- make sure to choose proper architecture
- create startup

        sudo ./svc.sh install # install
        sudo ./svc.sh start   # start
        sudo ./svc.sh status  # check
