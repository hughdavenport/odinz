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
    machine.pc = u32(header.initialpc)
    // FIXME set various bits and stuff in header
}

packed_addr :: proc(machine: ^Machine, address: u16) -> u32 {
    header := machine_header(machine)
    switch header.version {
    case 1, 2, 3: return u32(address) * 2
    case 4, 5: return u32(address) * 4
    case 6, 7: unimplemented("version 6 packed addresses") // need to get routine/string offset
    case 8: return u32(address) * 8
    }
    unreachable()

}

execute :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", machine.memory[0], machine.romfile)
        )
    }
    fmt.printfln("PC = %04x", machine.pc)

    instruction := instruction_read(machine, machine.pc)
    defer delete_instruction(instruction)

    instruction_dump(machine, &instruction)

    switch instruction.opcode {
    case .CALL:
        assert(len(instruction.operands) > 0)
        assert(instruction.operands[0].type != .VARIABLE)
        routine_addr := packed_addr(machine, instruction.operands[0].value)

        unimplemented("call")
    }
}
