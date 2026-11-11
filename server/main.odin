package main

import "core:crypto"
import "core:fmt"
import "core:net"
import "core:os"
import "core:time"
import "../protocol"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: dark-flodin <ip:port>")
		os.exit(2)
	}
	endpoint, valid := net.parse_endpoint(os.args[1])
	if !valid || endpoint.port == 0 {
		fmt.eprintln("expected an IP address and nonzero port")
		os.exit(2)
	}
	listener, listen_error := net.listen_tcp(endpoint)
	if listen_error != nil {
		fmt.eprintln("listen failed:", listen_error)
		os.exit(1)
	}
	defer net.close(listener)
	fmt.println("event=login_listening")
	for {
		client, _, accept_error := net.accept_tcp(listener)
		if accept_error != nil {
			fmt.eprintln("accept failed:", accept_error)
			os.exit(1)
		}
		probe_login(client)
	}
}

probe_login :: proc(client: net.TCP_Socket) {
	defer net.close(client)
	fmt.println("event=login_connected")
	defer fmt.println("event=login_disconnected")
	if net.set_option(client, .Receive_Timeout, 3 * time.Second) != nil ||
	   net.set_option(client, .Send_Timeout, 3 * time.Second) != nil {
		fmt.println("event=socket_setup_failed")
		return
	}
	keys: [2]u32
	crypto.rand_bytes((cast(^[8]byte)&keys)[:])
	greeting := protocol.login_greeting(keys[0], keys[1])
	for sent := 0; sent < len(greeting); {
		count, err := net.send_tcp(client, greeting[sent:])
		if err != nil || count == 0 {
			return
		}
		sent += count
	}
	header_bytes: [protocol.HEADER_SIZE]byte
	if !receive_exact(client, header_bytes[:]) {
		return
	}
	cipher := protocol.v2_cipher(keys[1])
	protocol.v2_transform(&cipher, header_bytes[:])
	header, result := protocol.decode_header(header_bytes[:])
	if result != .Ok {
		fmt.println("event=invalid_login_frame")
		return
	}
	if header.command != 0x9A && header.command != 0x9D {
		fmt.println("event=unexpected_login_command")
		return
	}
	if (header.command == 0x9A && header.size != 0xE0) ||
	   (header.command == 0x9D && header.size != 0xCC && header.size != 0x130) {
		fmt.println("event=invalid_login_frame")
		return
	}
	payload: [512]byte
	if receive_exact(client, payload[:int(header.size) - protocol.HEADER_SIZE]) {
		fmt.printf("event=login_request command=%02X size=%d\n", header.command, header.size)
	}
}

receive_exact :: proc(client: net.TCP_Socket, bytes: []byte) -> bool {
	started := time.tick_now()
	for received := 0; received < len(bytes); {
		remaining := 3 * time.Second - time.tick_diff(started, time.tick_now())
		if remaining <= 0 || net.set_option(client, .Receive_Timeout, remaining) != nil {
			return false
		}
		count, err := net.recv_tcp(client, bytes[received:])
		if err != nil || count == 0 {
			return false
		}
		received += count
	}
	return true
}
