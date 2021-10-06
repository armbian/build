# Runners setup

Common tags: 

- self-hosted
- Linux
- X64
- ARM64
- public (isolated runners for merge reqeusts)
- local (local network)
- cache (mounted cache)
- images (present cache, good enough for making images)
- big (16-128 cores, 64Gb SSD, 20Gb+ memory)
- small (< 16 cores, 32Gb SSD, 4Gb memory)

# Preparing GPG

use gpg1 otherwise signing fails

# Preparing Runner

- make sure to choose proper architecture
- create startup

        sudo ./svc.sh install # install
        sudo ./svc.sh start   # start
        sudo ./svc.sh status  # check
