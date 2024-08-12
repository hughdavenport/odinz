package odinz

import "core:fmt"

Frame :: struct {
    address: u32 `fmt:"04x"`,
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
    defer frame.pc += 2
    return machine_read_word(machine, frame.pc)
}

routine_read :: proc(machine: ^Machine, address: u32) -> (frame: Frame) {
    frame.address = address
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

frame_dump :: proc(frame: Frame) {
    fmt.printfln("FRAME: Routine %04x, %d locals %02x, Stack %02x",
                 frame.address, len(frame.variables), frame.variables, frame.stack)
}

packed_addr :: proc(machine: ^Machine, address: u16) -> u32 {
    header := machine_header(machine)
    switch header.version {
    case 1, 2, 3: return u32(address) * 2
    case 4, 5: return u32(address) * 4
    case 6, 7: unimplemented("version 6 packed addresses") // need to get routine/string offset
    case 8: return u32(address) * 8
    case:
        unreachable("Unable to get valid version number to get packed_addr(0x%04x). Version %d",
                    address, header.version)
    }
    unreachable("Unable to get packed_addr(0x%04x). Version %d", address, header.version)
}
