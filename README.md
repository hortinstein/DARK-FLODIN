# Dark Flodin

An Odin server for Dreamcast Phantasy Star Online. The current DCv2
login probe sends the initial encryption greeting, decodes the first client
header, validates the request length, and records receipt of the complete
frame. It closes the connection after the probe. Account verification, ship
selection, and lobby entry are future milestones.

## Run the TCP smoke test

With Odin dev-2025-04, a C linker, and Python 3.11 or later:

```sh
odin test protocol
odin build server -out:dark-flodin
python3 tests/login_smoke.py --server ./dark-flodin --timeout 10
```

The same commands run on GitHub Actions. The client tests the greeting, sends a
fragmented encrypted header, and waits for receipt and disconnect events.

## Run the Flycast smoke test

On your test machine, configure Flycast with a PSO v2 test VMU and network
profile. Use test DNS to direct the game's login hostname to the machine
running the probe, and bind the probe to an IPv4 address reachable from the
emulator. PSO v2 EU is the initial target. Verify the hostname and login port
for your disc revision and use those in the test network configuration.

```sh
python3 tests/login_smoke.py --server ./dark-flodin \
  --host 192.168.56.10 --port 12000 \
  --disc /path/to/pso-v2.chd --disc-sha256 YOUR_SHA256
```

Replace the example IP and port with the values for your test network. Select
**Online** when Flycast opens. To run unattended, use the same command from a
graphical session or Xvfb and supply `--online-driver /path/to/driver`. The
driver is a local executable that waits for the emulator window and navigates
the configured menus. Keep the disc, VMU, and emulator profile on the test
machine. The harness prints server events on exit and terminates its child
processes. A pass requires the encrypted login request and a disconnect.

Wire-format references are newserv's
[command definitions](https://github.com/fuzziqersoftware/newserv/blob/master/src/CommandFormats.hh)
and [V2 encryption implementation](https://github.com/fuzziqersoftware/newserv/blob/master/src/PSOEncryption.cc).
