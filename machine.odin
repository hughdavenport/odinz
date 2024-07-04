package odinz

import "core:fmt"
import "core:slice"

Machine :: struct {
    romfile: string,
    memory: []u8,
    pc: u32,
    stack: [dynamic]u8,
}

machine_header :: proc(machine: ^Machine) -> ^Header {
    raw_header := machine.memory[0:0x40]
    ptr, ok := slice.get_ptr(raw_header, 0)
    if !ok do error("Could not get header slice")
    return transmute(^Header)ptr;
}

machine_get_byte :: proc(machine: ^Machine, address: u32) -> u8 {
    if int(address) >= len(machine.memory) do return 0
    return machine.memory[address]
}

initialise_machine :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", header.version, machine.romfile)
        )
    }
    unimplemented("initialise_machine")
}

execute :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", machine.memory[0], machine.romfile)
        )
    }
    unimplemented("execute")
}
