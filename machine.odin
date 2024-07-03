package odinz

import "core:fmt"

Machine :: struct {
    romfile: string,
    memory: []u8,
    pc: u32,
    stack: [dynamic]u8,
}

initialise_machine :: proc(machine: ^Machine) {
    if machine.memory[0] != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", machine.memory[0], machine.romfile)
        )
    }
    unimplemented("initialise_machine")
}

execute :: proc(machine: ^Machine) {
    if machine.memory[0] != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", machine.memory[0], machine.romfile)
        )
    }
    unimplemented("execute")
}
