package odinz

import "core:fmt"

Opcode :: enum {
    UNKNOWN,
    ADD,
    CALL,
    LOADW,
    JE,
    JUMP,
    RET,
}

@(private="file")
var_ops := [?]Opcode{
    .CALL,
}

@(private="file")
one_ops := [?]Opcode{
    0x0B = .RET,
    0x0C = .JUMP,
}

@(private="file")
two_ops := [?]Opcode{
    0x01 = .JE,
    0x0F = .LOADW,
    0x14 = .ADD,
}

OperandType :: enum {
    SMALL_CONSTANT,
    LARGE_CONSTANT,
    VARIABLE,
}

Operand :: struct {
    type: OperandType,
    value: u16,
}

Instruction :: struct {
    opcode: Opcode,
    operands: [dynamic]Operand,
    store: u8,
    has_store: bool,
    has_branch: bool,
    branch_offset: i16,
    branch_condition: bool,
    // TODO zstring type
    has_zstring: bool,
    address: u32,
    length: u8,
}

@(private="file")
bit :: proc(byte: u8, bit: u8) -> bool {
    return byte | (1<<bit) == byte
}

@(private="file")
instruction_next_byte :: proc(machine: ^Machine, instruction: ^Instruction) -> u8 {
    b := machine_read_byte(machine, instruction.address + u32(instruction.length))
    instruction.length += 1
    return b
}

@(private="file")
instruction_read_store :: proc(machine: ^Machine, instruction: ^Instruction) {
    switch instruction.opcode {
        case .UNKNOWN: unreachable()
        case .ADD,
             .CALL,
             .LOADW: instruction.has_store = true

        // Not needed, but good for detecting new instructions
        case .JE, .JUMP, .RET:
    }

    if instruction.has_store do instruction.store = instruction_next_byte(machine, instruction)
}

@(private="file")
instruction_read_branch :: proc(machine: ^Machine, instruction: ^Instruction) {
    switch instruction.opcode {
        case .UNKNOWN: unreachable()
        case .JE: instruction.has_branch = true

        // Not needed, but good for detecting new instructions
        case .ADD, .CALL, .LOADW, .JUMP, .RET:
    }

    if instruction.has_branch {
        byte := instruction_next_byte(machine, instruction)
        instruction.branch_condition = bit(byte, 7)
        instruction.branch_offset = i16(byte & 0b111111)

        if !bit(byte, 6) {
            instruction.branch_offset = instruction.branch_offset << 8 + i16(instruction_next_byte(machine, instruction) & 0xFF)
            if bit(byte, 5) {
                instruction.branch_offset = instruction.branch_offset | 0b11 << 13 // Sign extend
            }
        }
    }
}

@(private="file")
instruction_read_zstring :: proc(machine: ^Machine, instruction: ^Instruction) {
    switch instruction.opcode {
        case .UNKNOWN: unreachable()

        // Not needed, but good for detecting new instructions
        case .ADD, .CALL, .JE, .JUMP, .LOADW, .RET:
    }

    if instruction.has_zstring do unimplemented("read zstring")
}

@(private="file")
instruction_read_operand :: proc(machine: ^Machine, instruction: ^Instruction, type: OperandType) {
    value := u16(instruction_next_byte(machine, instruction))
    switch type {
        case .LARGE_CONSTANT:
            value = value << 8 + u16(instruction_next_byte(machine, instruction))

        // Nothing needed
        case .VARIABLE, .SMALL_CONSTANT:
    }
    append(&instruction.operands, Operand {
        type = type,
        value = value,
    })
}

@(private="file")
instruction_read_variable :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8) {
    opcode := byte & 0b11111
    operand_types := instruction_next_byte(machine, instruction)

    if bit(byte, 5) {
        if opcode >= len(var_ops) do unimplemented(fmt.tprintf("var_ops[0x%X]", byte & 0b11111))
        instruction.opcode = var_ops[opcode]
        if instruction.opcode == .UNKNOWN do unimplemented(fmt.tprintf("var_ops[0x%X]", byte & 0b11111))
        instruction.operands = make([dynamic]Operand, 0, 4)
        for ; !(bit(operand_types, 7) && bit(operand_types, 6)); operand_types <<= 2 {
            if bit(operand_types, 7) && !bit(operand_types, 6) {
                instruction_read_operand(machine, instruction, .VARIABLE)
            } else if bit(operand_types, 6) {
                instruction_read_operand(machine, instruction, .SMALL_CONSTANT)
            } else {
                instruction_read_operand(machine, instruction, .LARGE_CONSTANT)
            }
        }
    } else {
        fmt.printfln("%08b", byte)
        unimplemented("2OP") // maybe just the same?
    }
}

@(private="file")
instruction_read_short :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8) {
    opcode := byte & 0b1111
    if bit(byte, 4) && bit(byte, 5) {
        fmt.printfln("%08b", byte)
        unimplemented("0OP")
    } else {
        if opcode >= len(one_ops) do unimplemented(fmt.tprintf("one_ops[0x%X]", opcode))
        instruction.opcode = one_ops[opcode]
        if instruction.opcode == .UNKNOWN do unimplemented(fmt.tprintf("one_ops[0x%X]", opcode))
        instruction.operands = make([dynamic]Operand, 0, 1)

        if bit(byte, 5) do instruction_read_operand(machine, instruction, .VARIABLE)
        else if bit(byte, 4) do instruction_read_operand(machine, instruction, .SMALL_CONSTANT)
        else do instruction_read_operand(machine, instruction, .LARGE_CONSTANT)
    }
}

@(private="file")
instruction_read_long :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8) {
    if byte & 0b11111 >= len(two_ops) do unimplemented(fmt.tprintf("two_ops[0x%X]", byte & 0b11111))
    instruction.opcode = two_ops[byte & 0b11111]
    if instruction.opcode == .UNKNOWN do unimplemented(fmt.tprintf("two_ops[0x%X]", byte & 0b11111))
    instruction.operands = make([dynamic]Operand, 0, 2)

    if bit(byte, 6) do instruction_read_operand(machine, instruction, .VARIABLE)
    else do instruction_read_operand(machine, instruction, .SMALL_CONSTANT)

    if bit(byte, 5) do instruction_read_operand(machine, instruction, .VARIABLE)
    else do instruction_read_operand(machine, instruction, .SMALL_CONSTANT)
}

instruction_read :: proc(machine: ^Machine, address: u32) -> (instruction: Instruction) {
    instruction.address = address
    byte := instruction_next_byte(machine, &instruction)

    if bit(byte, 7) && bit(byte, 6) {
        instruction_read_variable(machine, &instruction, byte)
    } else if bit(byte, 7) && !bit(byte, 6) {
        instruction_read_short(machine, &instruction, byte)
    } else if byte == 0xBE {
        fmt.printfln("%08b", byte)
        unimplemented("instruction extended")
    } else {
        instruction_read_long(machine, &instruction, byte)
    }

    instruction_read_store(machine, &instruction)
    instruction_read_branch(machine, &instruction)
    instruction_read_zstring(machine, &instruction)

    return instruction
}

delete_instruction :: proc(instruction: Instruction) {
    delete(instruction.operands)
    // TODO delete zstrings
}
