package odinz

import "core:fmt"

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
    zstring: string,
    address: u32,
    length: u16,
}

@(private="file")
instruction_next_byte :: proc(machine: ^Machine, instruction: ^Instruction) -> u8 {
    b := machine_read_byte(machine, instruction.address + u32(instruction.length))
    instruction.length += 1
    return b
}

@(private="file")
instruction_read_store :: proc(machine: ^Machine, instruction: ^Instruction) {
    instruction.has_store = opcode_needs_store(machine, instruction.opcode)

    if instruction.has_store do instruction.store = instruction_next_byte(machine, instruction)
}

@(private="file")
instruction_read_branch :: proc(machine: ^Machine, instruction: ^Instruction) {
    instruction.has_branch = opcode_needs_branch(machine, instruction.opcode)

    if instruction.has_branch {
        byte := instruction_next_byte(machine, instruction)
        instruction.branch_condition = bit(byte, 7)
        instruction.branch_offset = i16(byte & 0b111111) // Really this is unsigned, but i16 fits 0-63

        if !bit(byte, 6) {
            instruction.branch_offset = instruction.branch_offset << 8 + i16(instruction_next_byte(machine, instruction) & 0xFF)
            if bit(byte, 5) {
                // Negative offset, sign extend
                instruction.branch_offset = instruction.branch_offset | transmute(i16)u16(0b11 << 14)
            }
        }
    }
}

@(private="file")
instruction_read_zstring :: proc(machine: ^Machine, instruction: ^Instruction) {
    instruction.has_zstring = opcode_needs_zstring(machine, instruction.opcode)

    if instruction.has_zstring {
        length: u16 = 0
        instruction.zstring = zstring_read(machine, instruction.address + u32(instruction.length), &length)
        instruction.length += length
    }
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
instruction_read_operands :: proc(machine: ^Machine, instruction: ^Instruction, operand_types: u8) {
    operand_types := operand_types

    if cap(instruction.operands) == 0 do instruction.operands = make([dynamic]Operand, 0, 4)
    for ; !(bit(operand_types, 7) && bit(operand_types, 6)); operand_types <<= 2 {
        if bit(operand_types, 7) && !bit(operand_types, 6) {
            instruction_read_operand(machine, instruction, .VARIABLE)
        } else if bit(operand_types, 6) {
            instruction_read_operand(machine, instruction, .SMALL_CONSTANT)
        } else {
            instruction_read_operand(machine, instruction, .LARGE_CONSTANT)
        }
        if len(instruction.operands) % 4 == 0 do break
    }
}

@(private="file")
instruction_read_variable :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8, address: u32) {
    num := byte & 0b11111
    operand_types := instruction_next_byte(machine, instruction)

    if bit(byte, 5) {
        instruction.opcode = opcode(machine, num, .VAR, address)
        #partial switch instruction.opcode {
            case .CALL_VN2, .CALL_VS2:
                // https://zspec.jaredreisinger.com/04-instructions#4_4_3_1
                next_types := instruction_next_byte(machine, instruction)
                instruction_read_operands(machine, instruction, operand_types)
                instruction_read_operands(machine, instruction, next_types)

            case:
                instruction_read_operands(machine, instruction, operand_types)
        }
    } else {
        instruction.opcode = opcode(machine, num, .TWO, address)
        // The specs say 2OP, but some opcodes (i.e. JE) allow more, so just read as many as we can
        instruction_read_operands(machine, instruction, operand_types)
        assert(len(instruction.operands) >= 2)
    }
}

@(private="file")
instruction_read_short :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8, address: u32) {
    num := byte & 0b1111
    if bit(byte, 4) && bit(byte, 5) {
        instruction.opcode = opcode(machine, num, .ZERO, address)
        if instruction.opcode == .EXTENDED {
            header := machine_header(machine)
            assert(header.version >= 5)
            num = instruction_next_byte(machine, instruction)
            operand_types := instruction_next_byte(machine, instruction)
            instruction.opcode = opcode(machine, num, .EXT, address)
            instruction_read_operands(machine, instruction, operand_types)
        }
    } else {
        instruction.opcode = opcode(machine, num, .ONE, address)
        instruction.operands = make([dynamic]Operand, 0, 1)

        if bit(byte, 5) do instruction_read_operand(machine, instruction, .VARIABLE)
        else if bit(byte, 4) do instruction_read_operand(machine, instruction, .SMALL_CONSTANT)
        else do instruction_read_operand(machine, instruction, .LARGE_CONSTANT)
    }
}


@(private="file")
instruction_read_long :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8, address: u32) {
    instruction.opcode = opcode(machine, byte & 0b11111, .TWO, address)
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
        instruction_read_variable(machine, &instruction, byte, address)
    } else if bit(byte, 7) && !bit(byte, 6) {
        instruction_read_short(machine, &instruction, byte, address)
    } else if byte == 0xBE {
        fmt.printfln("%08b", byte)
        unimplemented("instruction extended")
    } else {
        instruction_read_long(machine, &instruction, byte, address)
    }

    instruction_read_store(machine, &instruction)
    instruction_read_branch(machine, &instruction)
    instruction_read_zstring(machine, &instruction)

    return instruction
}

delete_instruction :: proc(instruction: Instruction) {
    delete(instruction.operands)
}
