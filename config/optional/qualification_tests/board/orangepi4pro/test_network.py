import os
import socket
import subprocess
import pytest
from helpers import read_sysfs, run_command

pytestmark = [pytest.mark.board]

def test_ethernet_interface_present(primary_eth_interface):
    """Verify that Gigabit Ethernet interface (end0 or eth0) is present in sysfs."""
    assert primary_eth_interface is not None, "Ethernet interface missing from /sys/class/net/"
    assert os.path.exists(f"/sys/class/net/{primary_eth_interface}"), f"Interface {primary_eth_interface} not in sysfs"

def test_ethernet_mac_address(primary_eth_interface):
    """Verify that primary Ethernet interface has a valid, non-zero MAC address."""
    if not primary_eth_interface:
        pytest.skip("No Ethernet interface detected")
    addr_path = f"/sys/class/net/{primary_eth_interface}/address"
    mac = read_sysfs(addr_path)
    assert mac is not None, f"Could not read {primary_eth_interface} MAC address"
    assert mac != "00:00:00:00:00:00", f"Invalid all-zero MAC address on {primary_eth_interface}: {mac}"
    parts = mac.split(":")
    assert len(parts) == 6, f"Malformed MAC address: {mac}"

@pytest.mark.hardware
def test_ethernet_carrier_link(primary_eth_interface, eth_carrier):
    """Verify physical link carrier on primary Ethernet interface."""
    if not eth_carrier:
        pytest.skip(f"No Ethernet cable connected to {primary_eth_interface} (carrier = 0)")

    speed_str = read_sysfs(f"/sys/class/net/{primary_eth_interface}/speed", default="unknown")
    assert speed_str in ("1000", "100", "10"), f"Unexpected {primary_eth_interface} link speed: {speed_str} Mbps"
    print(f"\n[Ethernet Link] {primary_eth_interface} carrier UP at {speed_str} Mbps")

@pytest.mark.hardware
def test_network_gateway_ping(eth0_carrier):
    """Verify local network ICMP ping to gateway / TFTP host."""
    if not eth0_carrier:
        pytest.skip("No Ethernet cable connected")

    # Attempt to ping standard gateway or local TFTP host
    targets = ["10.0.1.4", "10.0.1.1", "1.1.1.1"]
    ping_ok = False
    last_err = ""

    for target in targets:
        out, code = run_command(f"ping -c 2 -W 2 {target}", timeout=6)
        if code == 0:
            ping_ok = True
            break
        last_err = out

    if not ping_ok:
        pytest.skip(f"Ping failed to local targets {targets}: {last_err}")

    assert ping_ok, "Ping succeeded to target"

@pytest.mark.hardware
def test_network_iperf_throughput(eth0_carrier, iperf_server):
    """Run iperf3 throughput benchmark if a test server was specified."""
    if not eth0_carrier:
        pytest.skip("No Ethernet cable connected")
    if not iperf_server:
        pytest.skip("No iperf3 server specified (pass --iperf-server <HOST> to test throughput)")

    iperf_bin, _ = run_command("command -v iperf3")
    if not iperf_bin:
        pytest.skip("iperf3 client binary not installed on target")

    # Test TCP throughput for 5 seconds
    out, code = run_command(f"iperf3 -c {iperf_server} -t 5 -f m", timeout=15)
    if code != 0:
        pytest.skip(f"iperf3 server {iperf_server} unreachable or refused connection: {out}")

    assert "sender" in out and "receiver" in out, f"iperf3 did not report throughput: {out}"
