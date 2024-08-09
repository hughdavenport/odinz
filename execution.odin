package odinz

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:time"

status_line :: proc(machine: ^Machine) {
    // https://zspec.jaredreisinger.com/08-screen#8_2
    header := machine_header(machine)
    if !is_tty() do return
    assert(header.version <= 3)
    flags := header.flags1.v3
    if .status_unavail in flags do return

    x, y := get_cursor()
    defer set_cursor(x, y)
    reverse_graphics()
    defer reset_graphics()
    set_cursor(0, 0)
    clear_line()

    // Get room name, truncating if needed
    name := object_name(machine, machine_read_global(machine, 0))
    if len(name) >= int(machine.screen.width) {
        split_at := strings.last_index(name[:machine.screen.width - 3], " ")
        if split_at == -1 do split_at = int(machine.screen.width) - 3
        name = fmt.tprintf("%s...", name[:split_at])
    }

    status: string
    if .status_time in flags {
        hour := machine_read_global(machine, 1)
        min := machine_read_global(machine, 2)
        status = fmt.tprintf("Time: %02d:%02d ", hour, min)
    } else {
        score := machine_read_global(machine, 1)
        turns := machine_read_global(machine, 2)
        status = fmt.tprintf("Score: %- 3d  Moves: %- 4d ", score, turns)
    }
    if len(name) + 6 + len(status) >= int(machine.screen.width) {
        gap := machine.screen.width - len(name) - 1
        fmt.printf(" %s", name)
        for i in 0..<gap do fmt.print(" ") // For some reason %*s doesn't work
        // No space for status part of string
    } else {
        gap := machine.screen.width - len(name) - len(status) - 2
        fmt.printf(" %s", name)
        for i in 0..<gap do fmt.print(" ") // For some reason %*s doesn't work
        fmt.printf("%s ", status)
    }
}

read_opcode :: proc(machine: ^Machine, instruction: ^Instruction) {
    // https://zspec.jaredreisinger.com/15-opcodes#read
    header := machine_header(machine)
    // NOTE: Spec lists 2 operands or 4
    //          However, TerpEtude has "READ L00" and "READ L01"
    //          Default to 0
    argc := len(instruction.operands)
    assert(argc >= 1)
    if argc != 2 && (header.version >= 4 && argc != 4) do debug("Invalid number of operands given: %d", argc)

    if header.version >= 5 do assert(instruction.has_store)
    else do assert(!instruction.has_store)
    text := u32(machine_read_operand(machine, &instruction.operands[0]))
    assert(text != 0)

    // NOTE: Spec lists 2 operands or 4
    //          However, TerpEtude has "READ L00" and "READ L01"
    //          Default to 0
    if argc < 2 do debug("Using 0 as the 2nd operand")
    parse := argc > 1 ? u32(machine_read_operand(machine, &instruction.operands[1])) : 0

    if header.version >= 1 && header.version <= 3 do status_line(machine)

    if header.version >= 4 && argc > 2 {
        assert(argc == 4)
        time := machine_read_operand(machine, &instruction.operands[2])
        routine := machine_read_operand(machine, &instruction.operands[3])
        if time != 0 && routine != 0 do unimplemented("timed reads")
    }

    ret := lexer_analyse(machine, text, parse)

    if header.version >= 5 do machine_write_variable(machine, u16(instruction.store), u16(ret))
}

execute :: proc(machine: ^Machine) {
    header := machine_header(machine)

    for {
        machine_dump(machine, to_disk = true)

        current_frame := &machine.frames[len(machine.frames) - 1]

        instruction := instruction_read(machine, current_frame.pc)
        current_frame.pc += u32(instruction.length)
        defer delete_instruction(instruction)

        if .frame in machine.config.trace do frame_dump(current_frame^)
        if .backtrace in machine.config.trace {
            fmt.println("BACKTRACE:")
            for i := len(machine.frames) - 1; i >= 0; i -= 1 {
                frame := machine.frames[i]
                fmt.printfln("%d  %04x in routine %04x",
                    len(machine.frames) - 1 - i, frame.pc, frame.address)
            }
        }
        if .instruction in machine.config.trace {
            for i := 0; i < len(machine.frames) - 1; i += 1 do fmt.print(" >  ")
            instruction_dump(machine, &instruction, len(machine.frames) - 1)
        }

        jump_condition := false

        switch instruction.opcode {
            case .UNKNOWN:
                unreachable("Invalid opcode while executing instruction %v", instruction)
            // Arithmetic
            case .ADD, .SUB, .MUL, .DIV, .MOD:
                // https://zspec.jaredreisinger.com/15-opcodes#add
                // https://zspec.jaredreisinger.com/15-opcodes#sub
                // https://zspec.jaredreisinger.com/15-opcodes#mul
                // https://zspec.jaredreisinger.com/15-opcodes#div
                // https://zspec.jaredreisinger.com/15-opcodes#mod
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                value: i16
                #partial switch instruction.opcode {
                    case .ADD: value = a + b
                    case .SUB: value = a - b
                    case .MUL: value = a * b
                    case .DIV: value = a / b
                    case .MOD: value = a % b
                    case: unreachable()
                }
                machine_write_variable(machine, u16(instruction.store), u16(value))


            // Increment and decement
            case .INC, .INC_CHK, .DEC, .DEC_CHK:
                // https://zspec.jaredreisinger.com/15-opcodes#inc
                // https://zspec.jaredreisinger.com/15-opcodes#inc_chk
                // https://zspec.jaredreisinger.com/15-opcodes#dec
                // https://zspec.jaredreisinger.com/15-opcodes#dec_chk
                assert(len(instruction.operands) >= 1)
                variable := machine_read_operand(machine, &instruction.operands[0])
                x := i16(machine_read_variable(machine, variable))
                #partial switch instruction.opcode {
                    case .INC, .INC_CHK: x += 1
                    case .DEC, .DEC_CHK: x -= 1
                    case: unreachable()
                }
                machine_write_variable(machine, variable, u16(x))
                #partial switch instruction.opcode {
                    case .INC, .DEC: // Ignore
                    case .INC_CHK, .DEC_CHK:
                        assert(len(instruction.operands) == 2)
                        value := i16(machine_read_operand(machine, &instruction.operands[1]))
                        #partial switch instruction.opcode {
                            case .INC_CHK: jump_condition = x > value
                            case .DEC_CHK: jump_condition = x < value
                            case: unreachable()
                        }
                    case: unreachable()
                }


            // Bitwise operators
            case .AND:
                // https://zspec.jaredreisinger.com/15-opcodes#and
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := u16(machine_read_operand(machine, &instruction.operands[0]))
                b := u16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), a & b)

            case .OR:
                // https://zspec.jaredreisinger.com/15-opcodes#or
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := u16(machine_read_operand(machine, &instruction.operands[0]))
                b := u16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), a | b)


            // Function calling and returning
            case .CALL:
                // https://zspec.jaredreisinger.com/15-opcodes#call
                assert(len(instruction.operands) > 0)
                assert(instruction.has_store)
                packed := machine_read_operand(machine, &instruction.operands[0])
                routine_addr := packed_addr(machine, packed)
                if routine_addr == 0 {
                    machine_write_variable(machine, u16(instruction.store), 0)
                } else {
                    routine := routine_read(machine, routine_addr)
                    routine.has_store = instruction.has_store
                    routine.store = instruction.store
                    for i := 1; i < len(instruction.operands); i += 1 {
                        value := machine_read_operand(machine, &instruction.operands[i])
                        routine.variables[i - 1] = value
                    }
                    append(&machine.frames, routine)
                    continue
                }

            case .CALL_1N:
                // https://zspec.jaredreisinger.com/15-opcodes#call_1n
                assert(len(instruction.operands) == 1)
                packed := machine_read_operand(machine, &instruction.operands[0])
                routine_addr := packed_addr(machine, packed)
                if routine_addr == 0 do continue
                routine := routine_read(machine, routine_addr)
                append(&machine.frames, routine)
                continue

            case .CALL_VN:
                // https://zspec.jaredreisinger.com/15-opcodes#call_vn
                assert(len(instruction.operands) > 0)
                assert(!instruction.has_store)
                packed := machine_read_operand(machine, &instruction.operands[0])
                routine_addr := packed_addr(machine, packed)
                if routine_addr == 0 do continue
                routine := routine_read(machine, routine_addr)
                for i := 1; i < len(instruction.operands); i += 1 {
                    value := machine_read_operand(machine, &instruction.operands[i])
                    routine.variables[i - 1] = value
                }
                append(&machine.frames, routine)
                continue

            case .RET, .RFALSE, .RTRUE:
                // https://zspec.jaredreisinger.com/15-opcodes#ret
                // https://zspec.jaredreisinger.com/15-opcodes#rfalse
                // https://zspec.jaredreisinger.com/15-opcodes#rtrue
                ret: u16
                #partial switch instruction.opcode {
                    case .RET:
                        assert(len(instruction.operands) == 1)
                        ret = machine_read_operand(machine, &instruction.operands[0])
                    case .RFALSE: ret = 0
                    case .RTRUE: ret = 1
                    case: unreachable()
                }
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), ret)
                delete_frame(current_frame)
                continue


            // Branches
            case .JUMP:
                // https://zspec.jaredreisinger.com/15-opcodes#jump
                assert(len(instruction.operands) == 1)
                // JUMP is different in that it takes the offset as an operand
                offset := i16(machine_read_operand(machine, &instruction.operands[0]))
                switch offset {
                    case 0: unimplemented("RFALSE")
                    case 1: unimplemented("RTRUE")
                    case: current_frame.pc = u32(i32(current_frame.pc) + i32(offset) - 2)
                }

            case .JZ, .JL, .JG, .JIN, .TEST, .TEST_ATTR:
                // https://zspec.jaredreisinger.com/15-opcodes#jz
                // https://zspec.jaredreisinger.com/15-opcodes#jl
                // https://zspec.jaredreisinger.com/15-opcodes#jg
                // https://zspec.jaredreisinger.com/15-opcodes#jin
                // https://zspec.jaredreisinger.com/15-opcodes#test
                // https://zspec.jaredreisinger.com/15-opcodes#test_attr
                assert(len(instruction.operands) >= 1)
                assert(instruction.has_branch)
                a := machine_read_operand(machine, &instruction.operands[0])
                if instruction.opcode == .JZ do jump_condition = a == 0
                else {
                    assert(len(instruction.operands) == 2)
                    b := machine_read_operand(machine, &instruction.operands[1])
                    #partial switch instruction.opcode {
                        case .JL: jump_condition = i16(a) < i16(b)
                        case .JG: jump_condition = i16(a) > i16(b)
                        case .JIN:
                            // NOTE: Not listed in spec on how to use object 0
                            //          However, strictz.z5 requires these checks to succeed
                            if a == 0 do debug("Invalid use of object 0")
                            if a == 0 && b == 0 do jump_condition = true
                            else if a == 0 do jump_condition = false
                            else do jump_condition = object_parent(machine, a) == b
                        case .TEST: jump_condition = a & b == b
                        case .TEST_ATTR:
                            assert(a != 0)
                            jump_condition = object_test_attr(machine, a, b)
                        case: unreachable()
                    }
                }

            case .JE:
                // https://zspec.jaredreisinger.com/15-opcodes#je
                assert(len(instruction.operands) > 1)
                assert(instruction.has_branch)
                a := machine_read_operand(machine, &instruction.operands[0])
                jump_condition = false
                for &operand in instruction.operands[1:] {
                    if machine_read_operand(machine, &operand) == a {
                        jump_condition = true
                        // Keep going in the loop, incase an operand is the stack
                    }
                }
                break

            case .GET_CHILD, .GET_SIBLING:
                // https://zspec.jaredreisinger.com/15-opcodes#get_child
                // https://zspec.jaredreisinger.com/15-opcodes#get_sibling
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                assert(instruction.has_branch)
                object := machine_read_operand(machine, &instruction.operands[0])
                result: u16
                // NOTE: Not listed in spec on how to use object 0
                //          However, strictz.z5 requires this to succeed
                if object == 0 do debug("Invalid use of object 0")
                if object == 0 do result = 0
                else do #partial switch instruction.opcode {
                    case .GET_CHILD: result = object_child(machine, object)
                    case .GET_SIBLING: result = object_sibling(machine, object)
                    case: unreachable()
                }
                machine_write_variable(machine, u16(instruction.store), result)
                jump_condition = result != 0



            // Objects
            case .CLEAR_ATTR, .SET_ATTR:
                // https://zspec.jaredreisinger.com/15-opcodes#clear_attr
                // https://zspec.jaredreisinger.com/15-opcodes#set_attr
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                attribute := machine_read_operand(machine, &instruction.operands[1])
                #partial switch instruction.opcode {
                    case .CLEAR_ATTR: object_clear_attr(machine, object, attribute)
                    case .SET_ATTR: object_set_attr(machine, object, attribute)
                    case: unreachable()
                }

            case .GET_PROP, .GET_PROP_ADDR, .GET_NEXT_PROP:
                // https://zspec.jaredreisinger.com/15-opcodes#get_prop
                // https://zspec.jaredreisinger.com/15-opcodes#get_prop_addr
                // https://zspec.jaredreisinger.com/15-opcodes#get_next_prop
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                property := machine_read_operand(machine, &instruction.operands[1])
                data: u16
                #partial switch instruction.opcode {
                    case .GET_PROP: data = object_get_property(machine, object, property)
                    case .GET_PROP_ADDR: data = object_get_property_addr(machine, object, property)
                    case .GET_NEXT_PROP: data = object_next_property(machine, object, property)
                    case: unreachable()
                }
                machine_write_variable(machine, u16(instruction.store), data)

            case .GET_PROP_LEN:
                // https://zspec.jaredreisinger.com/15-opcodes#get_prop_len
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                address := machine_read_operand(machine, &instruction.operands[0])
                if address == 0 { // Return false
                    pop(&machine.frames)
                    if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), 0)
                    delete_frame(current_frame)
                    continue
                }
                len := object_get_property_len(machine, address)
                machine_write_variable(machine, u16(instruction.store), len)

            case .PUT_PROP:
                // https://zspec.jaredreisinger.com/15-opcodes#put_prop
                assert(len(instruction.operands) == 3)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                property := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])
                object_put_property(machine, object, property, value)

            case .GET_PARENT:
                // https://zspec.jaredreisinger.com/15-opcodes#get_parent
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                assert(!instruction.has_branch) // No branch on this instruction
                object := machine_read_operand(machine, &instruction.operands[0])
                // NOTE: Not listed in spec on how to use object 0
                //          However, strictz.z5 requires this to succeed
                if object == 0 do debug("Invalid use of object 0")
                result: u16
                if object == 0 do result = 0
                else do result = object_parent(machine, object)
                machine_write_variable(machine, u16(instruction.store), result)

            case .INSERT_OBJ:
                // https://zspec.jaredreisinger.com/15-opcodes#insert_obj
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                destination := machine_read_operand(machine, &instruction.operands[1])
                assert(destination != 0)
                object_insert_object(machine, object, destination)

            case .REMOVE_OBJ:
                // https://zspec.jaredreisinger.com/15-opcodes#remove_obj
                assert(len(instruction.operands) == 1)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                object_remove_object(machine, object)


            // Loads and stores
            case .LOAD, .LOADB, .LOADW:
                // https://zspec.jaredreisinger.com/15-opcodes#load
                // https://zspec.jaredreisinger.com/15-opcodes#loadb
                // https://zspec.jaredreisinger.com/15-opcodes#loadw
                assert(len(instruction.operands) >= 1)
                assert(instruction.has_store)
                a := machine_read_operand(machine, &instruction.operands[0])
                value: u16
                #partial switch instruction.opcode {
                    case .LOAD: value = machine_read_variable(machine, a)
                    case .LOADB:
                        index := machine_read_operand(machine, &instruction.operands[1])
                        value = u16(machine_read_byte(machine, u32(a + index)))
                    case .LOADW:
                        index := machine_read_operand(machine, &instruction.operands[1])
                        value = u16(machine_read_word(machine, u32(a + 2 * index)))

                    case: unreachable()
                }
                machine_write_variable(machine, u16(instruction.store), value)

            case .STORE:
                // https://zspec.jaredreisinger.com/15-opcodes#store
                assert(len(instruction.operands) == 2)
                variable := machine_read_operand(machine, &instruction.operands[0])
                value := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, variable, value)

            case .STOREB, .STOREW:
                // https://zspec.jaredreisinger.com/15-opcodes#storeb
                // https://zspec.jaredreisinger.com/15-opcodes#storew
                assert(len(instruction.operands) == 3)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])
                #partial switch instruction.opcode {
                    case .STOREB:
                        assert(value <= 255)
                        machine_write_byte(machine, u32(array + index), u8(value))
                    case .STOREW: machine_write_word(machine, u32(array + 2 * index), value)
                    case: unreachable()
                }


            // Printing
            case .NEW_LINE:
                // https://zspec.jaredreisinger.com/15-opcodes#new_line
                fmt.println()

            case .PRINT:
                // https://zspec.jaredreisinger.com/15-opcodes#print
                assert(len(instruction.operands) == 0)
                assert(instruction.has_zstring)
                fmt.print(instruction.zstring)

            case .PRINT_CHAR, .PRINT_NUM, .PRINT_OBJ, .PRINT_ADDR, .PRINT_PADDR:
                // https://zspec.jaredreisinger.com/15-opcodes#print_char
                // https://zspec.jaredreisinger.com/15-opcodes#print_num
                // https://zspec.jaredreisinger.com/15-opcodes#print_obj
                // https://zspec.jaredreisinger.com/15-opcodes#print_addr
                // https://zspec.jaredreisinger.com/15-opcodes#print_paddr
                assert(len(instruction.operands) == 1)
                a := machine_read_operand(machine, &instruction.operands[0])
                #partial switch instruction.opcode {
                    case .PRINT_CHAR: fmt.print(zstring_output_zscii(machine, a))
                    case .PRINT_NUM: fmt.print(i16(a))
                    case .PRINT_OBJ:
                        assert(a != 0)
                        fmt.print(object_name(machine, a))
                    case .PRINT_ADDR: fmt.print(zstring_read(machine, u32(a)))
                    case .PRINT_PADDR: fmt.print(zstring_read(machine, packed_addr(machine, a)))
                    case: unreachable()
                }

            case .PRINT_RET:
                // https://zspec.jaredreisinger.com/15-opcodes#print_ret
                assert(len(instruction.operands) == 0)
                assert(instruction.has_zstring)
                fmt.println(instruction.zstring)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), 1)
                delete_frame(current_frame)
                continue


            // Input
            case .READ:
                // https://zspec.jaredreisinger.com/15-opcodes#read
                read_opcode(machine, &instruction)


            // Stack
            case .PUSH:
                // https://zspec.jaredreisinger.com/15-opcodes#push
                assert(len(instruction.operands) == 1)
                value := machine_read_operand(machine, &instruction.operands[0])
                append(&current_frame.stack, value)

            case .PULL:
                // https://zspec.jaredreisinger.com/15-opcodes#pull
                assert(len(instruction.operands) == 1)
                if header.version >= 6 {
                    assert(instruction.has_store)
                    unimplemented()
                } else {
                    variable := machine_read_operand(machine, &instruction.operands[0])
                    value := pop(&current_frame.stack)
                    machine_write_variable(machine, variable, value)
                }

            case .RET_POPPED:
                // https://zspec.jaredreisinger.com/15-opcodes#ret_popped
                assert(len(instruction.operands) == 0)
                ret := machine_read_variable(machine, 0)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), ret)
                delete_frame(current_frame)
                continue


            // Misc
            case .RANDOM:
                // https://zspec.jaredreisinger.com/15-opcodes#random
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                range := i16(machine_read_operand(machine, &instruction.operands[0]))
                ret := u16(0)
                if range < 0 do rand.reset(u64(abs(range)))
                else if range == 0 do rand.reset(u64(time.time_to_unix_nano(time.now())))
                else do ret = (u16(rand.uint32()) % u16(range)) + 1
                machine_write_variable(machine, u16(instruction.store), ret)

            case .SHOW_STATUS:
                // https://zspec.jaredreisinger.com/15-opcodes#random
                // NOTE: Spec lists version 3 only
                //          However, Wishbringer accidently contains it
                //          Default to no-op
                if header.version != 3 {
                    debug("SHOW_STATUS is undefined for version %d. nop", header.version)
                    continue
                }
                status_line(machine)

            case .QUIT:
                // https://zspec.jaredreisinger.com/15-opcodes#quit
                return

        } // switch instruction.opcode

        if instruction.has_branch && jump_condition == instruction.branch_condition {
            offset := i16(instruction.branch_offset)
            switch offset {
                case 0, 1:
                    pop(&machine.frames)
                    if current_frame.has_store {
                        machine_write_variable(machine, u16(current_frame.store), u16(offset) & 1)
                    }
                    delete_frame(current_frame)
                    continue
                case: current_frame.pc = u32(i32(current_frame.pc) + i32(offset) - 2)
            }
        }

    }
}
