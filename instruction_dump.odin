package odinz

import "core:fmt"

@(private="file")
variable_dump :: proc(value: u16, store := false) {
    switch value {
    case 0:
        if store do fmt.print("-(SP)")
        else do fmt.print("(SP)+")
    case 1..<16: fmt.printf("L%02x", value - 1)
    case 16..<256: fmt.printf("G%02x", value - 16)
    case: unreachable()
    }
}

@(private="file")
operand_dump :: proc(operand: Operand) {
    switch operand.type {
        case .SMALL_CONSTANT: fmt.printf("#%02x", operand.value)
        case .LARGE_CONSTANT: fmt.printf("#%04x", operand.value)
        case .VARIABLE: variable_dump(operand.value)
    }
}

@(private="file")
operands_dump :: proc(operands: []Operand) {
    first := true
    for operand in operands {
        if !first do fmt.print(",")
        else do first = false
        operand_dump(operand)
    }
}

instruction_dump :: proc(machine: ^Machine, instruction: ^Instruction) {
    fmt.printf("% 5x: ", instruction.address)
    for byte in machine.memory[instruction.address:][:instruction.length] {
        fmt.printf(" %02x", byte)
    }

    if instruction.length > 8 {
        fmt.println()
        fmt.printf("%31s", "")
    } else {
        fmt.printf("%*[1]s", "", 1 + 2 * (9 - instruction.length))
    }

    opcode_s, ok := fmt.enum_value_to_string(instruction.opcode)
    if !ok do opcode_s = "???"

    fmt.printf("%-16s", opcode_s)
    switch instruction.opcode {
    case .UNKNOWN: unreachable()
    case .ADD,
         .JE:
        operands_dump(instruction.operands[:])

    case .CALL:
        assert(len(instruction.operands) > 0)
        switch instruction.operands[0].type {
        case .SMALL_CONSTANT, .LARGE_CONSTANT:
            routine_addr := packed_addr(machine, instruction.operands[0].value)
            fmt.printf("%04x", routine_addr)
        case .VARIABLE:
            operand_dump(instruction.operands[0])
        }
        if len(instruction.operands) > 1 {
            fmt.print(" (")
            operands_dump(instruction.operands[1:])
            fmt.print(")")
        }
    }

    if instruction.has_store {
        fmt.print(" -> ")
        variable_dump(u16(instruction.store), store = true)
    }

    if instruction.has_branch {
        if instruction.branch_condition do fmt.print(" [TRUE] ")
        else do fmt.print(" [FALSE] ")

        switch i16(instruction.branch) {
            case 0: fmt.print(" RFALSE")
            case 1: fmt.print(" RTRUE")
            case:
                address := u32(i32(instruction.address + u32(instruction.length)) + i32(i16(instruction.branch)) - 2)
                fmt.printf("%04x", address)
        }
    }

    if instruction.has_zstring {
        unimplemented("print zstring")
    }

    fmt.println()
}

