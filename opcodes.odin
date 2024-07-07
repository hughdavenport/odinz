package odinz

import "core:fmt"

Opcode :: enum {
    UNKNOWN,
    ADD,
    CALL,
    JE,
    JUMP,
    JZ,
    LOADW,
    PUT_PROP,
    RET,
    STOREW,
    SUB,
}

OpcodeType :: enum {
    VAR,
    ZERO,
    ONE,
    TWO,
    EXT,
}

var_ops := [?]Opcode{
    0x00 = .CALL,
    0x01 = .STOREW,
    0x03 = .PUT_PROP,
}

one_ops := [?]Opcode{
    0x00 = .JZ,
    0x0B = .RET,
    0x0C = .JUMP,
}

two_ops := [?]Opcode{
    0x01 = .JE,
    0x0F = .LOADW,
    0x14 = .ADD,
    0x15 = .SUB,
}

opcode :: proc(num: u8, type: OpcodeType) -> Opcode {
    ops: []Opcode
    switch type {
        case .VAR: ops = var_ops[:]
        case .ZERO: unimplemented()
        case .ONE: ops = one_ops[:]
        case .TWO: ops = two_ops[:]
        case .EXT: unimplemented()
    }
    if int(num) > len(ops) || ops[num] == .UNKNOWN {
        unimplemented(fmt.tprintf("%v[0x%02x] not implemented", type, num))
    }
    return ops[num]
}

opcode_needs_branch :: proc(opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .JE,
             .JZ: return true

        // Not needed, but good for detecting new instructions
        case .ADD, .CALL, .LOADW, .JUMP, .PUT_PROP, .RET, .STOREW, .SUB:
    }
    return false
}

opcode_needs_store :: proc(opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")
        case .ADD,
             .CALL,
             .LOADW,
             .SUB: return true

        // Not needed, but good for detecting new instructions
        case .JE, .JUMP, .JZ, .PUT_PROP, .RET, .STOREW:
    }
    return false
}

opcode_needs_zstring :: proc(opcode: Opcode) -> bool {
    switch opcode {
        case .UNKNOWN: unreach("Invalid opcode during instruction parsing")

        // Not needed, but good for detecting new instructions
        case .ADD, .CALL, .JE, .JUMP, .JZ, .LOADW, .PUT_PROP, .RET, .STOREW, .SUB:
    }
    return false
}
