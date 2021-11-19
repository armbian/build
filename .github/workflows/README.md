# Runners setup

Common tags: 

- self-hosted
- Linux
- X64
- ARM64 (4Gb memory with ZRAM_PERCENTAGE=50)
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

# Use workflows in forked repositories

`forked-helper.yml` workflow helper can help to run custom workflows on the forked repositories.

1. Set `ARMBIAN_SELF_DISPATCH_TOKEN` secret on your repository with `security_events` permissions.
2. Helper will dispatch `repository_dispatch` event `armbian` on `push`, `release`, `deployment`, 
   `pull_request` and `workflow_dispatch` events. All needed event details you can find in `client_payload` 
   property of the event.
4. Create empty default branch in forked repository
5. Create workflow with `repository_dispatch` in default branch.
6. Run any need actions in this workflow.

Workflow example:
```yaml
name: Test Armbian dispatch

on:
  repository_dispatch:
    types: ["armbian"]

jobs:
  show-dispatch:
    name: Show dispatch event details
    runs-on: ubuntu-latest
    steps:
      - uses: hmarr/debug-action@v2
```
