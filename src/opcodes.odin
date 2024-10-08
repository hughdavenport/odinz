package odinz

import "core:c/libc"
import "core:fmt"
import "base:runtime"

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
    EXTENDED,

    // Arithmetic
    ADD, SUB,
    MUL, DIV, MOD,

    // Increment and decrement
    INC, INC_CHK,
    DEC, DEC_CHK,

    // Bitwise operators
    AND, OR, NOT,
    ART_SHIFT, LOG_SHIFT,

    // Function calling and returning
    CALL, CALL_1N, CALL_1S, CALL_2N, CALL_2S, CALL_VN, CALL_VN2, CALL_VS2,
    RET, RFALSE, RTRUE,
    CHECK_ARG_COUNT,
    // Also PRINT_RET and RET_POPPED listed with printing and stacks respectively

    // Branches
    JUMP,
    JZ,
    JL, JE, JG,
    JIN,
    TEST,
    TEST_ATTR, GET_CHILD, GET_SIBLING,
    // Also INC_CHK and DEC_CHK listed with increment and decrement

    // Objects
    CLEAR_ATTR, SET_ATTR,
    GET_PROP, GET_PROP_LEN, GET_PROP_ADDR, GET_NEXT_PROP,
    PUT_PROP,
    GET_PARENT, // Odd one out not being a branch instruction
    INSERT_OBJ, REMOVE_OBJ,

    // Loads and stores
    LOAD, LOADB, LOADW,
    STORE, STOREB, STOREW,

    // Printing
    NEW_LINE,
    PRINT,
    PRINT_CHAR,
    PRINT_NUM,
    PRINT_OBJ,
    PRINT_ADDR,
    PRINT_PADDR,
    PRINT_RET,
    OUTPUT_STREAM,

    // Input
    INPUT_STREAM, READ,

    // Stack
    PUSH, PULL,
    RET_POPPED,

    // Misc
    PIRACY,
    QUIT,
    RANDOM,
    RESTART,
    RESTORE,
    SAVE,
    SHOW_STATUS,
    VERIFY,

    // enum counter
    NUM_OPS,
}

// https://zspec.jaredreisinger.com/14-opcode-table
var_ops := [?]Opcode{
    0x00 = .CALL,
    0x01 = .STOREW,
    0x02 = .STOREB,
    0x03 = .PUT_PROP,
    0x04 = .READ,
    0x05 = .PRINT_CHAR,
    0x06 = .PRINT_NUM,
    0x07 = .RANDOM,
    0x08 = .PUSH,
    0x09 = .PULL,
    0x0A = .UNKNOWN,
    0x0B = .UNKNOWN,
    0x0C = .CALL_VS2,
    0x0D = .UNKNOWN,
    0x0E = .UNKNOWN,
    0x0F = .UNKNOWN,
    0x10 = .UNKNOWN,
    0x11 = .UNKNOWN,
    0x12 = .UNKNOWN,
    0x13 = .OUTPUT_STREAM,
    0x14 = .INPUT_STREAM,
    0x15 = .UNKNOWN,
    0x16 = .UNKNOWN,
    0x17 = .UNKNOWN,
    0x18 = .NOT,
    0x19 = .CALL_VN,
    0x1A = .CALL_VN2,
    0x1B = .UNKNOWN,
    0x1C = .UNKNOWN,
    0x1D = .UNKNOWN,
    0x1E = .UNKNOWN,
    0x1F = .CHECK_ARG_COUNT,
}

// https://zspec.jaredreisinger.com/14-opcode-table
zero_ops := [?]Opcode{
    0x00 = .RTRUE,
    0x01 = .RFALSE,
    0x02 = .PRINT,
    0x03 = .PRINT_RET,
    0x04 = .UNKNOWN,
    0x05 = .SAVE,
    0x06 = .RESTORE,
    0x07 = .RESTART,
    0x08 = .RET_POPPED,
    0x09 = .UNKNOWN,
    0x0A = .QUIT,
    0x0B = .NEW_LINE,
    0x0C = .SHOW_STATUS,
    0x0D = .VERIFY,
    0x0E = .EXTENDED,
    0x0F = .PIRACY,
}

// https://zspec.jaredreisinger.com/14-opcode-table
one_ops := [?]Opcode{
    0x00 = .JZ,
    0x01 = .GET_SIBLING,
    0x02 = .GET_CHILD,
    0x03 = .GET_PARENT,
    0x04 = .GET_PROP_LEN,
    0x05 = .INC,
    0x06 = .DEC,
    0x07 = .PRINT_ADDR,
    0x08 = .CALL_1S,
    0x09 = .REMOVE_OBJ,
    0x0A = .PRINT_OBJ,
    0x0B = .RET,
    0x0C = .JUMP,
    0x0D = .PRINT_PADDR,
    0x0E = .LOAD,
    0x0F = .CALL_1N,
}

// https://zspec.jaredreisinger.com/14-opcode-table
two_ops := [?]Opcode{
    0x00 = .UNKNOWN,
    0x01 = .JE,
    0x02 = .JL,
    0x03 = .JG,
    0x04 = .DEC_CHK,
    0x05 = .INC_CHK,
    0x06 = .JIN,
    0x07 = .TEST,
    0x08 = .OR,
    0x09 = .AND,
    0x0A = .TEST_ATTR,
    0x0B = .SET_ATTR,
    0x0C = .CLEAR_ATTR,
    0x0D = .STORE,
    0x0E = .INSERT_OBJ,
    0x0F = .LOADW,
    0x10 = .LOADB,
    0x11 = .GET_PROP,
    0x12 = .GET_PROP_ADDR,
    0x13 = .GET_NEXT_PROP,
    0x14 = .ADD,
    0x15 = .SUB,
    0x16 = .MUL,
    0x17 = .DIV,
    0x18 = .MOD,
    0x19 = .CALL_2S,
    0x1A = .CALL_2N,
    0x1B = .UNKNOWN,
    0x1C = .UNKNOWN,
    0x1D = .UNKNOWN,
    0x1E = .UNKNOWN,
    0x1F = .UNKNOWN,
}

// https://zspec.jaredreisinger.com/14-opcode-table
ext_ops := [?]Opcode{
    0x00 = .UNKNOWN,
    0x01 = .UNKNOWN,
    0x02 = .LOG_SHIFT,
    0x03 = .ART_SHIFT,
    0x04 = .UNKNOWN,
    0x05 = .UNKNOWN,
    0x06 = .UNKNOWN,
    0x07 = .UNKNOWN,
    0x08 = .UNKNOWN,
    0x09 = .UNKNOWN,
    0x0A = .UNKNOWN,
    0x0B = .UNKNOWN,
    0x0C = .UNKNOWN,
    0x0D = .UNKNOWN,
    0x0E = .UNKNOWN,
    0x0F = .UNKNOWN,
    0x10 = .UNKNOWN,
    0x11 = .UNKNOWN,
    0x12 = .UNKNOWN,
    0x13 = .UNKNOWN,
    0x14 = .UNKNOWN,
    0x15 = .UNKNOWN,
    0x16 = .UNKNOWN,
    0x17 = .UNKNOWN,
    0x18 = .UNKNOWN,
    0x19 = .UNKNOWN,
    0x1A = .UNKNOWN,
    0x1B = .UNKNOWN,
    0x1C = .UNKNOWN,
    0x1D = .UNKNOWN,
}

opcode :: proc(machine: ^Machine, num: u8, type: OpcodeType, address: u32) -> Opcode {
    ops: []Opcode
    switch type {
        case .VAR: ops = var_ops[:]
        case .ZERO: ops = zero_ops[:]
        case .ONE: ops = one_ops[:]
        case .TWO: ops = two_ops[:]
        case .EXT: ops = ext_ops[:]
    }
    if int(num) >= len(ops) || ops[num] == .UNKNOWN {
        type_s: string
        offset: u8
        loc: runtime.Source_Code_Location
        switch type {
            case .VAR:
                loc = #location(var_ops)
                type_s = "VAR"
                offset = 224
            case .ZERO:
                loc = #location(zero_ops)
                type_s = "0OP"
                offset = 176
            case .ONE:
                loc = #location(one_ops)
                type_s = "1OP"
                offset = 128
            case .TWO:
                loc = #location(two_ops)
                type_s = "2OP"
            case .EXT:
                loc = #location(ext_ops)
                type_s = "EXT"
        }
        loc.line += i32(num) + 1 // Where the entry should be (if array filled til then)
        fmt.println()
        fmt.printfln("%s Unimplemented Opcode 0x%02X\n%x: %s:%d %02X", loc, num, address, type_s, num + offset, num)
        cmd := fmt.ctprintf("txd -n -g %s | grep %x:", machine.romfile, address)
        debug("CMD: %v", cmd)
        libc.system(cmd)
        unimplemented()
    }
    return ops[num]
}

opcode_needs_branch :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    header := machine_header(machine)
    #assert(uint(Opcode.NUM_OPS) == 76)
    #partial switch opcode {
        case .UNKNOWN, .EXTENDED: unreachable("Invalid opcode during instruction parsing")
        case .INC_CHK, .DEC_CHK,
             .CHECK_ARG_COUNT,
             .JZ, .JL, .JE, .JG, .JIN,
             .TEST, .TEST_ATTR, .GET_CHILD, .GET_SIBLING,
             .PIRACY, .VERIFY:
                 return true

        case .RESTORE, .SAVE: if header.version <= 3 do return true
    }
    return false
}

opcode_needs_store :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    header := machine_header(machine)
    #assert(uint(Opcode.NUM_OPS) == 76)
    #partial switch opcode {
        case .UNKNOWN, .EXTENDED, .NUM_OPS:
            unreachable("Invalid opcode during instruction parsing")

        case .ADD, .SUB, .MUL, .DIV, .MOD,
             .AND, .OR, .NOT,
             .ART_SHIFT, .LOG_SHIFT,
             .CALL, .CALL_1S, .CALL_2S, .CALL_VS2,
             .GET_PROP, .GET_PROP_LEN, .GET_PROP_ADDR, .GET_NEXT_PROP,
             .GET_PARENT, .GET_CHILD, .GET_SIBLING,
             .LOAD, .LOADB, .LOADW,
             .RANDOM:
                return true

        case .PULL: if header.version >= 6 do return true
        case .READ: if header.version >= 5 do return true

        case .RESTORE, .SAVE: if header.version >= 4 do return true
    }
    return false
}

opcode_needs_zstring :: proc(machine: ^Machine, opcode: Opcode) -> bool {
    #assert(uint(Opcode.NUM_OPS) == 76)
    #partial switch opcode {
        case .UNKNOWN, .EXTENDED, .NUM_OPS:
            unreachable("Invalid opcode during instruction parsing")

        case .PRINT, .PRINT_RET: return true
    }
    return false
}
