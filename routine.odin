package odinz

import "core:fmt"

Frame :: struct {
    pc: u32 `fmt:"04x"`,
    variables: []u16 `fmt:"04x"`,
    stack: [dynamic]u16 `fmt:"04x"`,
    has_store: bool,
    store: u8,
}

delete_frame :: proc(frame: ^Frame) {
    delete(frame.variables)
    delete(frame.stack)
}

@(private="file")
frame_next_byte :: proc(machine: ^Machine, frame: ^Frame) -> u8 {
    b := machine_read_byte(machine, frame.pc)
    frame.pc += 1
    return b
}

@(private="file")
frame_next_word :: proc(machine: ^Machine, frame: ^Frame) -> u16 {
    high := machine_read_byte(machine, frame.pc)
    low := machine_read_byte(machine, frame.pc)
    frame.pc += 2
    return u16(high) << 16 + u16(low)
}

routine_read :: proc(machine: ^Machine, address: u32) -> (frame: Frame) {
    frame.pc = address
    variables := frame_next_byte(machine, &frame)
    frame.variables = make([]u16, variables)
    header := machine_header(machine)
    if header.version <= 4 {
        for i: u8 = 0; i < variables; i += 1 {
            frame.variables[i] = frame_next_word(machine, &frame)
        }
    }
    return frame
}

packed_addr :: proc(machine: ^Machine, address: u16) -> u32 {
    header := machine_header(machine)
    switch header.version {
    case 1, 2, 3: return u32(address) * 2
    case 4, 5: return u32(address) * 4
    case 6, 7: unimplemented("version 6 packed addresses") // need to get routine/string offset
    case 8: return u32(address) * 8
    case:
        machine_dump(machine)
        fmt.eprintfln("Unable to get valid version number to get packed_addr(0x%04x). Version %d", address, header.version);
        unreachable()
    }
    machine_dump(machine)
    fmt.eprintfln("Unable to get packed_addr(0x%04x). Version %d", address, header.version);
    unreachable()

}
