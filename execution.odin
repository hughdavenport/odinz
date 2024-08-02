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
    flags := transmute(Flags1_V3)header.flags1
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
    assert(len(instruction.operands) >= 2)
    if header.version >= 5 do assert(instruction.has_store)
    else do assert(!instruction.has_store)
    text := u32(machine_read_operand(machine, &instruction.operands[0]))
    parse := u32(machine_read_operand(machine, &instruction.operands[1]))
    assert(text != 0)
    assert(parse != 0)

    if header.version >= 1 && header.version <= 3 do status_line(machine)

    if header.version >= 4 && len(instruction.operands) > 2 {
        assert(len(instruction.operands) == 4)
        time := machine_read_operand(machine, &instruction.operands[2])
        routine := machine_read_operand(machine, &instruction.operands[3])
        if time != 0 && routine != 0 do unimplemented("timed reads")
    }

    lexer_analyse(machine, text, parse)

    if header.version >= 5 do unimplemented("store")
}

execute :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", machine.memory[0], machine.romfile)
        )
    }

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
            case .ADD:
                // https://zspec.jaredreisinger.com/15-opcodes#add
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a + b))

            case .AND:
                // https://zspec.jaredreisinger.com/15-opcodes#and
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := u16(machine_read_operand(machine, &instruction.operands[0]))
                b := u16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), a & b)

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

            case .CLEAR_ATTR:
                // https://zspec.jaredreisinger.com/15-opcodes#clear_attr
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                attribute := machine_read_operand(machine, &instruction.operands[1])
                object_clear_attr(machine, object, attribute)

            case .DEC:
                // https://zspec.jaredreisinger.com/15-opcodes#dec
                assert(len(instruction.operands) == 1)
                variable := machine_read_operand(machine, &instruction.operands[0])
                x := i16(machine_read_variable(machine, variable))
                x -= 1
                machine_write_variable(machine, variable, u16(x))

            case .DEC_CHK:
                // https://zspec.jaredreisinger.com/15-opcodes#dec_chk
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                variable := machine_read_operand(machine, &instruction.operands[0])
                value := i16(machine_read_operand(machine, &instruction.operands[1]))
                x := i16(machine_read_variable(machine, variable))
                x -= 1
                machine_write_variable(machine, variable, u16(x))
                jump_condition = x < value

            case .DIV:
                // https://zspec.jaredreisinger.com/15-opcodes#div
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a / b))

            case .GET_CHILD:
                // https://zspec.jaredreisinger.com/15-opcodes#get_child
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                assert(instruction.has_branch)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                child := object_child(machine, object)
                machine_write_variable(machine, u16(instruction.store), child)
                jump_condition = child != 0

            case .GET_NEXT_PROP:
                // https://zspec.jaredreisinger.com/15-opcodes#get_next_prop
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                object := machine_read_operand(machine, &instruction.operands[0])
                property := machine_read_operand(machine, &instruction.operands[1])
                assert(object != 0)
                next := object_next_property(machine, object, property)
                machine_write_variable(machine, u16(instruction.store), next)

            case .GET_PARENT:
                // https://zspec.jaredreisinger.com/15-opcodes#get_parent
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                assert(!instruction.has_branch) // No branch on this instruction
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                parent := object_parent(machine, object)
                machine_write_variable(machine, u16(instruction.store), parent)

            case .GET_PROP:
                // https://zspec.jaredreisinger.com/15-opcodes#get_prop
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                property := machine_read_operand(machine, &instruction.operands[1])
                data := object_get_property(machine, object, property)
                machine_write_variable(machine, u16(instruction.store), data)

            case .GET_PROP_ADDR:
                // https://zspec.jaredreisinger.com/15-opcodes#get_prop_addr
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                property := machine_read_operand(machine, &instruction.operands[1])
                addr := object_get_property_addr(machine, object, property)
                machine_write_variable(machine, u16(instruction.store), addr)

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

            case .GET_SIBLING:
                // https://zspec.jaredreisinger.com/15-opcodes#get_sibling
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                assert(instruction.has_branch)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                sibling := object_sibling(machine, object)
                machine_write_variable(machine, u16(instruction.store), sibling)
                jump_condition = sibling != 0

            case .INC:
                // https://zspec.jaredreisinger.com/15-opcodes#inc
                assert(len(instruction.operands) == 1)
                variable := machine_read_operand(machine, &instruction.operands[0])
                x := machine_read_variable(machine, variable)
                x += 1
                machine_write_variable(machine, variable, x)

            case .INC_CHK:
                // https://zspec.jaredreisinger.com/15-opcodes#inc_chk
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                variable := machine_read_operand(machine, &instruction.operands[0])
                value := i16(machine_read_operand(machine, &instruction.operands[1]))
                x := i16(machine_read_variable(machine, variable))
                x += 1
                machine_write_variable(machine, variable, u16(x))
                jump_condition = x > value

            case .INSERT_OBJ:
                // https://zspec.jaredreisinger.com/15-opcodes#insert_obj
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                destination := machine_read_operand(machine, &instruction.operands[1])
                assert(destination != 0)
                object_insert_object(machine, object, destination)

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

            case .JG:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                jump_condition = a > b

            case .JIN:
                // https://zspec.jaredreisinger.com/15-opcodes#jin
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                a := machine_read_operand(machine, &instruction.operands[0])
                b := machine_read_operand(machine, &instruction.operands[1])
                jump_condition = object_parent(machine, a) == b

            case .JL:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                jump_condition = a < b

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

            case .JZ:
                // https://zspec.jaredreisinger.com/15-opcodes#jz
                assert(len(instruction.operands) == 1)
                assert(instruction.has_branch)
                a := machine_read_operand(machine, &instruction.operands[0])
                jump_condition = a == 0

            case .LOADB:
                // https://zspec.jaredreisinger.com/15-opcodes#loadb
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, u16(instruction.store), u16(machine_read_byte(machine, u32(array + index))))

            case .LOADW:
                // https://zspec.jaredreisinger.com/15-opcodes#loadw
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, u16(instruction.store), machine_read_word(machine, u32(array + 2 * index)))

            case .MUL:
                // https://zspec.jaredreisinger.com/15-opcodes#mul
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a * b))

            case .NEW_LINE:
                // https://zspec.jaredreisinger.com/15-opcodes#new_line
                fmt.println()

            case .PRINT:
                // https://zspec.jaredreisinger.com/15-opcodes#print
                assert(len(instruction.operands) == 0)
                assert(instruction.has_zstring)
                fmt.print(instruction.zstring)

            case .PRINT_CHAR:
                // https://zspec.jaredreisinger.com/15-opcodes#print_char
                assert(len(instruction.operands) == 1)
                char := machine_read_operand(machine, &instruction.operands[0])
                fmt.print(zstring_output_zscii(machine, char))

            case .PRINT_NUM:
                // https://zspec.jaredreisinger.com/15-opcodes#print_num
                assert(len(instruction.operands) == 1)
                value := i16(machine_read_operand(machine, &instruction.operands[0]))
                fmt.print(value)

            case .PRINT_OBJ:
                // https://zspec.jaredreisinger.com/15-opcodes#print_obj
                assert(len(instruction.operands) == 1)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                fmt.print(object_name(machine, object))

            case .PRINT_PADDR:
                // https://zspec.jaredreisinger.com/15-opcodes#print_paddr
                assert(len(instruction.operands) == 1)
                packed := machine_read_operand(machine, &instruction.operands[0])
                str_addr := packed_addr(machine, packed)
                zstring_dump(machine, str_addr)

            case .PRINT_RET:
                // https://zspec.jaredreisinger.com/15-opcodes#print_ret
                assert(len(instruction.operands) == 0)
                assert(instruction.has_zstring)
                fmt.println(instruction.zstring)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), 1)
                delete_frame(current_frame)
                continue

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

            case .PUSH:
                // https://zspec.jaredreisinger.com/15-opcodes#push
                assert(len(instruction.operands) == 1)
                value := machine_read_operand(machine, &instruction.operands[0])
                append(&current_frame.stack, value)

            case .PUT_PROP:
                // https://zspec.jaredreisinger.com/15-opcodes#put_prop
                assert(len(instruction.operands) == 3)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                property := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])
                object_put_property(machine, object, property, value)

            case .RFALSE:
                // https://zspec.jaredreisinger.com/15-opcodes#rfalse
                assert(len(instruction.operands) == 0)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), 0)
                delete_frame(current_frame)
                continue

            case .RTRUE:
                // https://zspec.jaredreisinger.com/15-opcodes#rtrue
                assert(len(instruction.operands) == 0)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), 1)
                delete_frame(current_frame)
                continue

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

            case .QUIT:
                // https://zspec.jaredreisinger.com/15-opcodes#quit
                return

            case .READ:
                // https://zspec.jaredreisinger.com/15-opcodes#read
                read_opcode(machine, &instruction)

            case .RET:
                // https://zspec.jaredreisinger.com/15-opcodes#ret
                assert(len(instruction.operands) == 1)
                ret := machine_read_operand(machine, &instruction.operands[0])
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), ret)
                delete_frame(current_frame)
                continue

            case .RET_POPPED:
                // https://zspec.jaredreisinger.com/15-opcodes#ret_popped
                assert(len(instruction.operands) == 0)
                ret := machine_read_variable(machine, 0)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), ret)
                delete_frame(current_frame)
                continue

            case .SET_ATTR:
                // https://zspec.jaredreisinger.com/15-opcodes#set_attr
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                attribute := machine_read_operand(machine, &instruction.operands[1])
                object_set_attr(machine, object, attribute)

            case .STORE:
                // https://zspec.jaredreisinger.com/15-opcodes#store
                assert(len(instruction.operands) == 2)
                variable := machine_read_operand(machine, &instruction.operands[0])
                value := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, variable, value)

            case .STOREB:
                // https://zspec.jaredreisinger.com/15-opcodes#storeb
                assert(len(instruction.operands) == 3)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])
                assert(value <= 255)
                machine_write_byte(machine, u32(array + index), u8(value))

            case .STOREW:
                // https://zspec.jaredreisinger.com/15-opcodes#storew
                assert(len(instruction.operands) == 3)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])
                machine_write_word(machine, u32(array + 2 * index), value)

            case .SUB:
                // https://zspec.jaredreisinger.com/15-opcodes#sub
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a - b))

            case .TEST:
                // https://zspec.jaredreisinger.com/15-opcodes#test
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                bitmap := machine_read_operand(machine, &instruction.operands[0])
                flags := machine_read_operand(machine, &instruction.operands[1])
                jump_condition = bitmap & flags == flags

            case .TEST_ATTR:
                // https://zspec.jaredreisinger.com/15-opcodes#test_attr
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                object := machine_read_operand(machine, &instruction.operands[0])
                assert(object != 0)
                attribute := machine_read_operand(machine, &instruction.operands[1])
                jump_condition = object_test_attr(machine, object, attribute)

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
