package odinz

import "core:fmt"
import "core:slice"

Frame :: struct {
    pc: u32 `fmt:"04x"`,
    variables: []u16 `fmt:"04x"`,
    stack: [dynamic]u16 `fmt:"04x"`,
    has_store: bool,
    store: u8,
}

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
    return u16(machine_read_byte(machine, address)) << 16 + u16(machine_read_byte(machine, address + 2))
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

execute :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", machine.memory[0], machine.romfile)
        )
    }

    for {
        current_frame := &machine.frames[len(machine.frames) - 1]
        fmt.printfln("PC = %04x", current_frame.pc)
        fmt.printfln("%v", current_frame^)
        // fmt.printfln("frames = %v", machine.frames)
        instruction := instruction_read(machine, current_frame.pc)

        for i := 0; i < len(machine.frames) - 1; i += 1 do fmt.print(" >  ")
        instruction_dump(machine, &instruction)

        switch instruction.opcode {
        case .UNKNOWN: unreachable()
        case .ADD:
            assert(len(instruction.operands) == 2)
            assert(instruction.has_store)
            a := i16(machine_read_operand(machine, &instruction.operands[0]))
            b := i16(machine_read_operand(machine, &instruction.operands[1]))
            fmt.printfln("a = 0x%x, b = 0x%x, sum = 0x%x, store = 0x%x",
                a, b, u16(a + b), u16(instruction.store))
            machine_write_variable(machine, u16(instruction.store), u16(a + b))

        case .CALL:
            assert(len(instruction.operands) > 0)
            assert(instruction.operands[0].type != .VARIABLE)
            routine_addr := packed_addr(machine, instruction.operands[0].value)
            routine := routine_read(machine, routine_addr)
            routine.has_store = instruction.has_store
            routine.store = instruction.store
            append(&machine.frames, routine)

            if instruction.has_branch do unimplemented()

        }

        current_frame.pc += u32(instruction.length)
        delete_instruction(instruction)
    }
}
