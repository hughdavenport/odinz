package odinz

import "core:fmt"

OpcodeType :: enum {
    VAR,
    ZERO,
    ONE,
    TWO,
    EXT,
}

// https://zspec.jaredreisinger.com/15-opcodes
Opcode :: enum {
    UNKNOWN,
    ADD,
    AND,
    CALL,
    GET_CHILD,
    GET_PARENT,
    GET_PROP,
    GET_SIBLING,
    INC_CHK,
    INSERT_OBJ,
    JE,
    JIN,
    JUMP,
    JZ,
    LOADB,
    LOADW,
    NEW_LINE,
    PRINT,
    PRINT_CHAR,
    PRINT_NUM,
    PRINT_OBJ,
    PULL,
    PUSH,
    PUT_PROP,
    RET,
    RTRUE,
    SET_ATTR,
    STORE,
    STOREW,
    SUB,
    TEST_ATTR,
}

// https://zspec.jaredreisinger.com/14-opcode-table
var_ops := [?]Opcode{
    0x00 = .CALL,
    0x01 = .STOREW,
    0x03 = .PUT_PROP,
    0x05 = .PRINT_CHAR,
    0x06 = .PRINT_NUM,
    0x08 = .PUSH,
    0x09 = .PULL,
}

// https://zspec.jaredreisinger.com/14-opcode-table
zero_ops := [?]Opcode{
    0x00 = .RTRUE,
    0x02 = .PRINT,
    0x0B = .NEW_LINE,
}

// https://zspec.jaredreisinger.com/14-opcode-table
one_ops := [?]Opcode{
    0x00 = .JZ,
    0x01 = .GET_SIBLING,
    0x02 = .GET_CHILD,
    0x03 = .GET_PARENT,
    0x0A = .PRINT_OBJ,
    0x0B = .RET,
    0x0C = .JUMP,
}

// https://zspec.jaredreisinger.com/14-opcode-table
two_ops := [?]Opcode{
    0x01 = .JE,
    0x05 = .INC_CHK,
    0x06 = .JIN,
    0x09 = .AND,
    0x0A = .TEST_ATTR,
    0x0B = .SET_ATTR,
    0x0D = .STORE,
    0x0E = .INSERT_OBJ,
    0x0F = .LOADW,
    0x10 = .LOADB,
    0x11 = .GET_PROP,
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
        type_s: string
        offset: u8
        switch type {
            case .VAR:
                type_s = "VAR"
                offset = 224
            case .ZERO:
                type_s = "0OP"
                offset = 176
            case .ONE:
                type_s = "1OP"
                offset = 128
            case .TWO: type_s = "2OP"
            case .EXT: type_s = "EXT"
        }
        unimplemented(fmt.tprintf("\n%x: %s:%d %02x", address, type_s, num + offset, num))
    }
    return ops[num]
}

opcode_needs_branch :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .GET_CHILD,
             .GET_SIBLING,
             .INC_CHK,
             .JE,
             .JIN,
             .JZ,
             .TEST_ATTR: return true

        // Not needed, but good for detecting new instructions
        case .ADD, .AND, .CALL, .GET_PARENT, .GET_PROP, .INSERT_OBJ, .LOADB, .LOADW, .JUMP, .NEW_LINE, .PRINT, .PRINT_CHAR, .PRINT_NUM, .PRINT_OBJ, .PULL, .PUSH, .PUT_PROP, .RET, .RTRUE, .SET_ATTR, .STORE, .STOREW, .SUB:
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
             .GET_CHILD,
             .GET_PARENT,
             .GET_PROP,
             .GET_SIBLING,
             .LOADB,
             .LOADW,
             .SUB: return true

        case .PULL:
            if header.version >= 6 do return true
            else do return false

        // Not needed, but good for detecting new instructions
        case .INC_CHK, .INSERT_OBJ, .JE, .JIN, .JUMP, .JZ, .NEW_LINE, .PRINT, .PRINT_CHAR, .PRINT_NUM, .PRINT_OBJ, .PUSH, .PUT_PROP, .RET, .RTRUE, .SET_ATTR, .STORE, .STOREW, .TEST_ATTR:
    }
    return false
}

opcode_needs_zstring :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .PRINT: return true

        // Not needed, but good for detecting new instructions
        case .ADD, .AND, .CALL, .GET_CHILD, .GET_PARENT, .GET_PROP, .GET_SIBLING, .INC_CHK, .INSERT_OBJ, .JE, .JIN, .JUMP, .JZ, .LOADB, .LOADW, .NEW_LINE, .PRINT_CHAR, .PRINT_NUM, .PRINT_OBJ, .PULL, .PUSH, .PUT_PROP, .RET, .RTRUE, .SET_ATTR, .STORE, .STOREW, .SUB, .TEST_ATTR:
    }
    return false
}
