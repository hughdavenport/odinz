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
    case: unreachable("Error while dumping variable. Unexpected number %d", value)
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

@(private="file")
_object_dump :: proc(machine: ^Machine, operand: Operand) {
    switch operand.type {
        case .SMALL_CONSTANT, .LARGE_CONSTANT:
            if object_has_name(machine, operand.value) {
                fmt.printf("\"%s\"", object_name(machine, operand.value))
            } else {
                operand_dump(operand)
            }
        case .VARIABLE:
            operand_dump(operand)
    }
}

instruction_dump :: proc(machine: ^Machine, instruction: ^Instruction, indent := 0) {
    header := machine_header(machine)
    fmt.printf("% 5x: ", instruction.address)
    for byte in machine.memory[instruction.address:][:instruction.length] {
        fmt.printf(" %02x", byte)
    }

    if instruction.length > 8 {
        fmt.println()
        for i := 0; i < indent; i += 1 do fmt.print(" >  ")
        fmt.printf("%31s", "")
    } else {
        fmt.printf("%*[1]s", "", 3 * (8 - instruction.length))
    }

    opcode_s, ok := fmt.enum_value_to_string(instruction.opcode)
    if !ok do opcode_s = "???"

    fmt.printf(" %-16s", opcode_s)
    switch instruction.opcode {
        case .UNKNOWN: unreachable("Invalid opcode while dumping instruction")
        case .ADD, .SUB, .MUL, .DIV, .MOD,
             .AND, .OR, .NOT,
             .RET, .RFALSE, .RTRUE,
             .GET_PROP_LEN,
             .JZ, .JL, .JE, .JG, .TEST,
             .LOADB, .LOADW,
             .STOREB, .STOREW,
             .NEW_LINE, .PRINT_CHAR, .PRINT_NUM, .PRINT_ADDR, .PRINT_PADDR,
             .OUTPUT_STREAM, // FIXME txd shows RECORD_ENABLE, but then #fffc isn't DISABLE
             .INPUT_STREAM, .READ,
             .PUSH, .RET_POPPED,
             .QUIT, .RANDOM, .RESTART, .RESTORE, .SHOW_STATUS, .VERIFY:
            operands_dump(instruction.operands[:])

        case .CALL, .CALL_1N, .CALL_2N, .CALL_2S, .CALL_VN:
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

        case .CLEAR_ATTR,
             .GET_CHILD,
             .GET_NEXT_PROP,
             .GET_PARENT,
             .GET_PROP,
             .GET_PROP_ADDR,
             .GET_SIBLING,
             .INSERT_OBJ,
             .PUT_PROP,
             .REMOVE_OBJ,
             .SET_ATTR,
             .TEST_ATTR:
            assert(len(instruction.operands) >= 1)
            _object_dump(machine, instruction.operands[0])
            if len(instruction.operands) >= 2 do fmt.print(",")
            operands_dump(instruction.operands[1:])

        case .DEC,
             .DEC_CHK,
             .INC,
             .INC_CHK,
             .LOAD,
             .STORE:
            assert(len(instruction.operands) >= 1)
            if instruction.operands[0].type == .VARIABLE do fmt.print("[")
            variable_dump(instruction.operands[0].value)
            if instruction.operands[0].type == .VARIABLE do fmt.print("]")
            if len(instruction.operands) >= 2 do fmt.print(",")
            operands_dump(instruction.operands[1:])

        case .JIN:
            assert(len(instruction.operands) == 2)
            _object_dump(machine, instruction.operands[0])
            fmt.print(",")
            _object_dump(machine, instruction.operands[1])

        case .JUMP:
            assert(len(instruction.operands) == 1)
            // This could cause issues if JUMP SP, as would alter the stack for the dump
            // However, this does not show up in Zork 1 (840726)
            assert(!(instruction.operands[0].type == .VARIABLE && instruction.operands[0].value == 0))
            offset := i16(machine_read_operand(machine, &instruction.operands[0]))
            switch offset {
                case 0: fmt.print("RFALSE")
                case 1: fmt.print("RTRUE")
                case:
                    next := i32(instruction.address + u32(instruction.length))
                    address := u32(next + i32(offset) - 2)
                    fmt.printf("%04x", address)
            }
            fmt.println()
            return

        case .PULL:
            assert(len(instruction.operands) == 1)
            if header.version >= 6 {
                assert(instruction.has_store)
                unimplemented()
            } else {
                if instruction.operands[0].type == .VARIABLE do fmt.print("[")
                variable_dump(instruction.operands[0].value)
                if instruction.operands[0].type == .VARIABLE do fmt.print("]")
            }

        case .PRINT, .PRINT_RET:
            fmt.printf("\"%s\"", instruction.zstring)

        case .PRINT_OBJ:
            _object_dump(machine, instruction.operands[0])
    }

    if instruction.has_store {
        fmt.print(" -> ")
        variable_dump(u16(instruction.store), store = true)
    }

    if instruction.has_branch {
        if instruction.branch_condition do fmt.print(" [TRUE] ")
        else do fmt.print(" [FALSE] ")

        switch i16(instruction.branch_offset) {
            case 0: fmt.print("RFALSE")
            case 1: fmt.print("RTRUE")
            case:
                next := instruction.address + u32(instruction.length)
                address := u32(i32(next) + i32(i16(instruction.branch_offset)) - 2)
                fmt.printf("%04x", address)
        }
    }

    // Z-string's are handled in switch case (only PRINT and PRINT_RET use them)

    fmt.println()
}

