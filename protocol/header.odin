package protocol

HEADER_SIZE :: 4

Header :: struct {
	command: u8,
	flags: u8,
	size: u16,
}

Decode_Result :: enum {
	Ok,
	Incomplete,
	Invalid_Size,
}

decode_header :: proc(bytes: []u8) -> (Header, Decode_Result) {
	if len(bytes) < HEADER_SIZE {
		return {}, .Incomplete
	}
	size := u16(bytes[2]) | (u16(bytes[3]) << 8)
	if size < HEADER_SIZE {
		return {}, .Invalid_Size
	}
	return {command = bytes[0], flags = bytes[1], size = size}, .Ok
}

// read_frame accepts decrypted bytes and returns the first complete frame.
read_frame :: proc(bytes: []u8) -> (Header, []u8, Decode_Result) {
	header, result := decode_header(bytes)
	if result != .Ok {
		return {}, nil, result
	}
	if len(bytes) < int(header.size) {
		return {}, nil, .Incomplete
	}
	return header, bytes[:int(header.size)], .Ok
}
