package odinz

import "core:fmt"
import "core:slice"

Machine :: struct {
    romfile: string,
    memory: []u8,
    frames: [dynamic]Frame,
}

machine_header :: proc(machine: ^Machine) -> ^Header {
    raw_header := machine.memory[0:0x40]
    ptr, ok := slice.get_ptr(raw_header, 0)
    if !ok do error("Could not get header slice")
    return transmute(^Header)ptr;
}

machine_read_byte :: proc(machine: ^Machine, address: u32) -> u8 {
    if int(address) >= len(machine.memory) do return 0
    return machine.memory[address]
}

machine_read_word :: proc(machine: ^Machine, address: u32) -> u16 {
    return u16(machine_read_byte(machine, address)) << 16 + u16(machine_read_byte(machine, address + 1))
}

machine_write_byte :: proc(machine: ^Machine, address: u32, value: u8) {
    if int(address) >= len(machine.memory) do return
    machine.memory[address] = value
}

machine_write_word :: proc(machine: ^Machine, address: u32, value: u16) {
    machine_write_byte(machine, address, u8(value >> 16))
    machine_write_byte(machine, address + 1, u8(value))
}

machine_read_global :: proc(machine: ^Machine, global: u16) -> u16 {
    return machine_read_word(machine, u32(machine_header(machine).globals) + u32(global) * 2)
}

machine_write_global :: proc(machine: ^Machine, global: u16, value: u16) {
    machine_write_word(machine, u32(machine_header(machine).globals) + u32(global) * 2, value)
}

machine_read_operand :: proc(machine: ^Machine, operand: ^Operand) -> u16 {
    switch operand.type {
    case .SMALL_CONSTANT, .LARGE_CONSTANT: return operand.value
    case .VARIABLE:
        variable := operand.value
        current_frame := &machine.frames[len(machine.frames) - 1]
        switch variable {
            case 0: return pop(&current_frame.stack)
            case 1..<16: return current_frame.variables[variable - 1]
            case 16..<255: return machine_read_global(machine, variable - 16)
            case: unreachable()
        }
    }
    unreachable()
}

machine_write_variable :: proc(machine: ^Machine, variable: u16, value: u16) {
    current_frame := &machine.frames[len(machine.frames) - 1]
    switch variable {
        case 0: append(&current_frame.stack, value)
        case 1..<16: current_frame.variables[variable - 1] = value
        case 16..<255: machine_write_global(machine, variable - 16, value)
        case: unreachable()
    }
}

initialise_machine :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", header.version, machine.romfile)
        )
    }
    append(&machine.frames, Frame {
        pc = u32(header.initialpc),
    })
    // FIXME set various bits and stuff in header
}
