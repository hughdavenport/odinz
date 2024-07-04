package odinz

import "core:fmt"
import "core:slice"

Frame :: struct {
    pc: u32 `fmt:"04x"`,
    variables: []u16 `fmt:"04x"`,
    stack: [dynamic]u8,
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

machine_get_word :: proc(machine: ^Machine, address: u32) -> u16 {
    if int(address) >= len(machine.memory) do return 0
    if int(address) == len(machine.memory) - 1 do return u16(machine.memory[len(machine.memory) - 1])
    return u16(machine.memory[address]) << 16 + u16(machine.memory[address + 1])
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
    b := machine_get_byte(machine, frame.pc)
    frame.pc += 1
    return b
}

@(private="file")
frame_next_word :: proc(machine: ^Machine, frame: ^Frame) -> u16 {
    high := machine_get_byte(machine, frame.pc)
    low := machine_get_byte(machine, frame.pc)
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
        // fmt.printfln("current frame = %v", current_frame^)
        fmt.printfln("frames = %v", machine.frames)
        instruction := instruction_read(machine, current_frame.pc)

        for i := 0; i < len(machine.frames) - 1; i += 1 do fmt.print(" >  ")
        instruction_dump(machine, &instruction)

        switch instruction.opcode {
        case .CALL:
            assert(len(instruction.operands) > 0)
            assert(instruction.operands[0].type != .VARIABLE)
            routine_addr := packed_addr(machine, instruction.operands[0].value)
            routine := routine_read(machine, routine_addr)
            append(&machine.frames, routine)
        }

        current_frame.pc += u32(instruction.length)
        delete_instruction(instruction)
    }
}
