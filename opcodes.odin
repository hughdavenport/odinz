package odinz

import "core:fmt"

OpcodeType :: enum {
    VAR,
    ZERO,
    ONE,
    TWO,
    EXT,
}

Opcode :: enum {
    UNKNOWN,
    ADD,
    AND,
    CALL,
    INC_CHK,
    INSERT_OBJ,
    JE,
    JUMP,
    JZ,
    LOADB,
    LOADW,
    NEW_LINE,
    PRINT,
    PRINT_CHAR,
    PRINT_NUM,
    PULL,
    PUSH,
    PUT_PROP,
    RET,
    RTRUE,
    STORE,
    STOREW,
    SUB,
    TEST_ATTR,
}

var_ops := [?]Opcode{
    0x00 = .CALL,
    0x01 = .STOREW,
    0x03 = .PUT_PROP,
    0x05 = .PRINT_CHAR,
    0x06 = .PRINT_NUM,
    0x08 = .PUSH,
    0x09 = .PULL,
}

zero_ops := [?]Opcode{
    0x00 = .RTRUE,
    0x02 = .PRINT,
    0x0B = .NEW_LINE,
}

one_ops := [?]Opcode{
    0x00 = .JZ,
    0x0B = .RET,
    0x0C = .JUMP,
}

two_ops := [?]Opcode{
    0x01 = .JE,
    0x05 = .INC_CHK,
    0x09 = .AND,
    0x0A = .TEST_ATTR,
    0x0D = .STORE,
    0x0E = .INSERT_OBJ,
    0x0F = .LOADW,
    0x10 = .LOADB,
    0x14 = .ADD,
    0x15 = .SUB,
}

opcode :: proc(num: u8, type: OpcodeType, address: u32) -> Opcode {
    ops: []Opcode
    switch type {
        case .VAR: ops = var_ops[:]
        case .ZERO: ops = zero_ops[:]
        case .ONE: ops = one_ops[:]
        case .TWO: ops = two_ops[:]
        case .EXT: unimplemented()
    }
    if int(num) >= len(ops) || ops[num] == .UNKNOWN {
        unimplemented(fmt.tprintf("%x: %v[0x%02x] not implemented", address, type, num))
    }
    return ops[num]
}

opcode_needs_branch :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .INC_CHK,
             .JE,
             .JZ,
             .TEST_ATTR: return true

        // Not needed, but good for detecting new instructions
        case .ADD, .AND, .CALL, .INSERT_OBJ, .LOADB, .LOADW, .JUMP, .NEW_LINE, .PRINT, .PRINT_CHAR, .PRINT_NUM, .PULL, .PUSH, .PUT_PROP, .RET, .RTRUE, .STORE, .STOREW, .SUB:
    }
    return false
}

opcode_needs_store :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    header := machine_header(machine)
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .ADD,
             .AND,
             .CALL,
             .LOADB,
             .LOADW,
             .SUB: return true

        case .PULL:
            if header.version >= 6 do return true
            else do return false

        // Not needed, but good for detecting new instructions
        case .INC_CHK, .INSERT_OBJ, .JE, .JUMP, .JZ, .NEW_LINE, .PRINT, .PRINT_CHAR, .PRINT_NUM, .PUSH, .PUT_PROP, .RET, .RTRUE, .STORE, .STOREW, .TEST_ATTR:
    }
    return false
}

opcode_needs_zstring :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .PRINT: return true

        // Not needed, but good for detecting new instructions
        case .ADD, .AND, .CALL, .INC_CHK, .INSERT_OBJ, .JE, .JUMP, .JZ, .LOADB, .LOADW, .NEW_LINE, .PRINT_CHAR, .PRINT_NUM, .PULL, .PUSH, .PUT_PROP, .RET, .RTRUE, .STORE, .STOREW, .SUB, .TEST_ATTR:
    }
    return false
}
