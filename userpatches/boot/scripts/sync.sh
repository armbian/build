#!/bin/bash

# regular sync to prevent data loss when direct power outage
while [ 1 ]; do
    sync
    sleep 5
done
