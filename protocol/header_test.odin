package protocol

import "core:testing"

@(test)
reads_little_endian_size :: proc(t: ^testing.T) {
	bytes := [?]u8{0x17, 0x02, 0x04, 0x01}
	header, result := decode_header(bytes[:])
	testing.expect(t, result == .Ok)
	testing.expect(t, header.command == 0x17 && header.flags == 2 && header.size == 260)
}

@(test)
waits_for_complete_frame :: proc(t: ^testing.T) {
	bytes := [?]u8{0x17, 0, 6, 0, 1, 2, 0x18, 0, 4, 0}
	_, _, partial_header := read_frame(bytes[:3])
	_, _, partial_payload := read_frame(bytes[:5])
	header, frame, complete := read_frame(bytes[:])
	testing.expect(t, partial_header == .Incomplete && partial_payload == .Incomplete)
	testing.expect(t, complete == .Ok && len(frame) == 6 && header.size == 6)
}

@(test)
rejects_undersized_frame :: proc(t: ^testing.T) {
	bytes := [?]u8{0x17, 0, 3, 0}
	_, _, result := read_frame(bytes[:])
	testing.expect(t, result == .Invalid_Size)
}
