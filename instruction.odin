package odinz

Opcode :: enum {
   CALL,
}

@(private="file")
var_ops := [?]Opcode{
    Opcode.CALL,
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
    branch: u16,
    has_branch: bool,
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
    b := machine_get_byte(machine, instruction.address + u32(instruction.length))
    instruction.length += 1
    return b
}

@(private="file")
instruction_read_store :: proc(machine: ^Machine, instruction: ^Instruction) {
    switch instruction.opcode {
        case .CALL: instruction.has_store = true
    }

    if instruction.has_store do instruction.store = instruction_next_byte(machine, instruction)
}

@(private="file")
instruction_read_branch :: proc(machine: ^Machine, instruction: ^Instruction) {
    switch instruction.opcode {
        case .CALL: instruction.has_branch = false
    }

    if instruction.has_branch do unimplemented("read branch")
        // need to read one byte, test some bits to see if true/false and extra byte or not
        // probably use a struct for branch
}

@(private="file")
instruction_read_zstring :: proc(machine: ^Machine, instruction: ^Instruction) {
    switch instruction.opcode {
        case .CALL: instruction.has_zstring = false
    }

    if instruction.has_zstring do unimplemented("read zstring")
}

@(private="file")
instruction_read_variable :: proc(machine: ^Machine, instruction: ^Instruction, byte: u8) {
    opcode := byte & 0b11111
    operand_types := instruction_next_byte(machine, instruction)

    if bit(byte, 5) {
        instruction.opcode = var_ops[opcode]
        instruction.operands = make([dynamic]Operand, 0, 4)
        for ; !(bit(operand_types, 7) && bit(operand_types, 6)); operand_types <<= 2 {
            value := u16(instruction_next_byte(machine, instruction))
            operand : Operand
            if bit(operand_types, 7) && !bit(operand_types, 6) {
                operand = Operand {
                    type = OperandType.VARIABLE,
                    value = value,
                }
            } else {
                if bit(operand_types, 6) {
                    operand = Operand {
                        type = OperandType.SMALL_CONSTANT,
                        value = value,
                    }
                } else {
                    value = value << 8 + u16(instruction_next_byte(machine, instruction))
                    operand = Operand {
                        type = OperandType.LARGE_CONSTANT,
                        value = value,
                    }
                }
            }
            append(&instruction.operands, operand)
        }
    } else {
        unimplemented("2OP") // maybe just the same?
    }
}

instruction_read :: proc(machine: ^Machine, address: u32) -> (instruction: Instruction) {
    instruction.address = address
    byte := instruction_next_byte(machine, &instruction)

    if bit(byte, 7) && bit(byte, 6) {
        instruction_read_variable(machine, &instruction, byte)
    } else {
        unimplemented("instruction other forms")
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
