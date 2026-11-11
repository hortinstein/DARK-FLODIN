package protocol

LOGIN_GREETING_SIZE :: HEADER_SIZE + 0x48
LOGIN_BANNER :: "DreamCast Port Map. Copyright SEGA Enterprises. 1999"

login_greeting :: proc(server_key, client_key: u32) -> [LOGIN_GREETING_SIZE]byte {
	packet: [LOGIN_GREETING_SIZE]byte
	packet[0] = 0x17
	packet[2] = LOGIN_GREETING_SIZE
	copy(packet[HEADER_SIZE:HEADER_SIZE + 0x40], LOGIN_BANNER)
	for index in 0..<4 {
		packet[0x44 + index] = byte(server_key >> uint(8 * index))
		packet[0x48 + index] = byte(client_key >> uint(8 * index))
	}
	return packet
}

V2_Cipher :: struct {
	words: [56]u32,
	offset: int,
}

v2_cipher :: proc(seed: u32) -> V2_Cipher {
	cipher: V2_Cipher
	previous, current := seed, u32(1)
	cipher.words[55] = seed
	for index in 1..=54 {
		cipher.words[(21 * index) % 55] = current
		previous, current = current, previous - current
	}
	for _ in 0..<5 {
		refresh_v2(&cipher)
	}
	return cipher
}

@(private)
refresh_v2 :: proc(cipher: ^V2_Cipher) {
	for index in 1..<25 {
		cipher.words[index] -= cipher.words[index + 31]
	}
	for index in 25..<56 {
		cipher.words[index] -= cipher.words[index - 24]
	}
	cipher.offset = 1
}

// Transform one complete protocol segment. A partial final word consumes
// the full keystream word, as on Dreamcast.
v2_transform :: proc(cipher: ^V2_Cipher, bytes: []byte) {
	for start := 0; start < len(bytes); start += 4 {
		if cipher.offset == len(cipher.words) {
			refresh_v2(cipher)
		}
		key := cipher.words[cipher.offset]
		cipher.offset += 1
		for index in 0..<min(4, len(bytes) - start) {
			bytes[start + index] ~= byte(key >> uint(8 * index))
		}
	}
}
