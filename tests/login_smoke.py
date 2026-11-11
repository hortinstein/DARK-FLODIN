"""Exercise the first encrypted DCv2 login request over a real TCP socket."""
import argparse
import hashlib
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time


def wait_for_event(process, log, event, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if any(line.split(" ", 1)[0] == event for line in log.read_text().splitlines()):
            return
        if process.poll() is not None:
            raise RuntimeError(f"Server exited with status {process.returncode}")
        time.sleep(0.05)
    raise TimeoutError(f"Timed out waiting for {event}")


def scripted_client(endpoint):
    # Independently verified against the V2 first-word seed formula in newserv.
    with socket.create_connection(endpoint, timeout=3) as connection:
        with connection.makefile("rb") as stream:
            greeting = stream.read(0x4C)
        assert len(greeting) == 0x4C, greeting.hex()
        assert greeting[:4] == b"\x17\x00\x4c\x00", greeting[:4].hex()
        assert greeting[4:0x44].rstrip(b"\0") == (
            b"DreamCast Port Map. Copyright SEGA Enterprises. 1999"
        )
        (seed,) = struct.unpack_from("<I", greeting, 0x48)
        first_word = (0xC6DCAB76 * seed - 0x9E1977BA) & 0xFFFFFFFF
        encrypted_header = struct.pack("<I", 0x00E0009A ^ first_word)
        connection.sendall(encrypted_header[:1])
        time.sleep(0.05)
        # The probe checks payload framing only. Use opaque dummy bytes.
        connection.sendall(encrypted_header[1:] + bytes(0xDC))


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=12000)
    parser.add_argument("--disc", type=Path, help="Local PSO v2 disc image for Flycast")
    parser.add_argument("--disc-sha256", help="Expected checksum of the disc image")
    parser.add_argument("--flycast", default="flycast")
    parser.add_argument("--online-driver", type=Path,
                        help="Executable that drives the emulator menus")
    parser.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or args.timeout <= 0:
        parser.error("expected a valid TCP port and positive timeout")
    if args.disc:
        if not args.disc.is_file() or not args.disc_sha256:
            parser.error("Flycast mode requires an existing disc and --disc-sha256")
        with args.disc.open("rb") as disc:
            digest = hashlib.file_digest(disc, "sha256").hexdigest()
        if digest.lower() != args.disc_sha256.lower():
            parser.error("disc checksum mismatch")
    elif args.online_driver:
        parser.error("--online-driver requires --disc")

    with tempfile.TemporaryDirectory() as temporary:
        log = Path(temporary) / "server.log"
        with log.open("w") as output:
            server = subprocess.Popen(
                [str(args.server.resolve()), f"{args.host}:{args.port}"],
                stdout=output, stderr=subprocess.STDOUT,
            )
            emulator = driver = None
            try:
                wait_for_event(server, log, "event=login_listening", 5)
                if args.disc:
                    emulator = subprocess.Popen([args.flycast, str(args.disc.resolve())])
                    if args.online_driver:
                        driver = subprocess.Popen([str(args.online_driver.resolve())])
                    else:
                        print("Select Online in Flycast.", flush=True)
                else:
                    scripted_client((args.host, args.port))
                wait_for_event(server, log, "event=login_request", args.timeout)
                wait_for_event(server, log, "event=login_disconnected", 5)
            finally:
                stop(driver)
                stop(emulator)
                stop(server)
                print(log.read_text(), end="")


if __name__ == "__main__":
    main()
