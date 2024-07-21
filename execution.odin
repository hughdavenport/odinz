package odinz

import "core:fmt"

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

        for i := 0; i < len(machine.frames) - 1; i += 1 do fmt.print(" >  ")
        instruction_dump(machine, &instruction, len(machine.frames) - 1)

        // fmt.printfln("Frame = %v", current_frame^)
        // fmt.printfln("All frames = %v", machine.frames)

        jump_condition := false

        switch instruction.opcode {
            case .UNKNOWN:
                unreach("Invalid opcode while executing instruction %v",
                        instruction, machine=machine)
            case .ADD:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a + b))

            case .AND:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := u16(machine_read_operand(machine, &instruction.operands[0]))
                b := u16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), a & b)

            case .CALL:
                assert(len(instruction.operands) > 0)
                assert(instruction.operands[0].type != .VARIABLE)
                assert(instruction.has_store)
                routine_addr := packed_addr(machine, instruction.operands[0].value)
                if routine_addr == 0 {
                    machine_write_variable(machine, u16(instruction.store), 0)
                } else {
                    routine := routine_read(machine, routine_addr)
                    routine.has_store = instruction.has_store
                    routine.store = instruction.store
                    append(&machine.frames, routine)
                }

            case .GET_PARENT:
                assert(len(instruction.operands) == 1)
                assert(instruction.has_store)
                object := machine_read_operand(machine, &instruction.operands[0])
                parent := object_parent(machine, object)
                machine_write_variable(machine, u16(instruction.store), parent)

            case .GET_PROP:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                object := machine_read_operand(machine, &instruction.operands[0])
                property := machine_read_operand(machine, &instruction.operands[1])
                data := object_get_property(machine, object, property)
                machine_write_variable(machine, u16(instruction.store), data)

            case .INC_CHK:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                variable := machine_read_operand(machine, &instruction.operands[0])
                value := machine_read_operand(machine, &instruction.operands[1])
                x := machine_read_variable(machine, variable)
                x += 1
                machine_write_variable(machine, variable, x)
                jump_condition = x > value

            case .INSERT_OBJ:
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                destination := machine_read_operand(machine, &instruction.operands[1])
                object_insert_object(machine, object, destination)

            case .JE:
                assert(len(instruction.operands) > 1)
                assert(instruction.has_branch)
                a := machine_read_operand(machine, &instruction.operands[0])
                jump_condition = false
                for &operand in instruction.operands[1:] {
                    if machine_read_operand(machine, &operand) == a {
                        jump_condition = true
                        break
                    }
                }

            case .JIN:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                object1 := machine_read_operand(machine, &instruction.operands[0])
                object2 := machine_read_operand(machine, &instruction.operands[1])
                jump_condition = object_parent(machine, object1) == object2

            case .JUMP:
                assert(len(instruction.operands) == 1)
                // JUMP is different in that it takes the offset as an operand
                offset := i16(machine_read_operand(machine, &instruction.operands[0]))
                switch offset {
                    case 0: unimplemented("RFALSE")
                    case 1: unimplemented("RTRUE")
                    case: current_frame.pc = u32(i32(current_frame.pc) + i32(offset) - 2)
                }

            case .JZ:
                assert(len(instruction.operands) == 1)
                assert(instruction.has_branch)
                a := machine_read_operand(machine, &instruction.operands[0])
                jump_condition = a == 0

            case .LOADB:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, u16(instruction.store), u16(machine_read_byte(machine, u32(array + index))))

            case .LOADW:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, u16(instruction.store), machine_read_word(machine, u32(array + 2 * index)))

            case .NEW_LINE:
                fmt.println()

            case .PRINT:
                assert(instruction.has_zstring)
                fmt.print(instruction.zstring)

            case .PRINT_CHAR:
                assert(len(instruction.operands) == 1)
                char := machine_read_operand(machine, &instruction.operands[0])
                zstring_output_zscii(machine, char)

            case .PRINT_NUM:
                assert(len(instruction.operands) == 1)
                value := i16(machine_read_operand(machine, &instruction.operands[0]))
                fmt.print(value)

            case .PRINT_OBJ:
                assert(len(instruction.operands) == 1)
                object := machine_read_operand(machine, &instruction.operands[0])
                object_dump(machine, object)

            case .PULL:
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
                assert(len(instruction.operands) == 1)
                value := machine_read_operand(machine, &instruction.operands[0])
                append(&current_frame.stack, value)

            case .PUT_PROP:
                assert(len(instruction.operands) == 3)
                object := machine_read_operand(machine, &instruction.operands[0])
                property := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])

                object_put_property(machine, object, property, value)

            case .RTRUE:
                assert(len(instruction.operands) == 0)
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), 1)
                delete_frame(current_frame)

            case .RET:
                assert(len(instruction.operands) == 1)
                ret := machine_read_operand(machine, &instruction.operands[0])
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), ret)
                delete_frame(current_frame)

            case .SET_ATTR:
                assert(len(instruction.operands) == 2)
                object := machine_read_operand(machine, &instruction.operands[0])
                attribute := machine_read_operand(machine, &instruction.operands[1])
                object_set_attr(machine, object, attribute)

            case .STORE:
                assert(len(instruction.operands) == 2)
                variable := machine_read_operand(machine, &instruction.operands[0])
                value := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, variable, value)

            case .STOREW:
                assert(len(instruction.operands) == 3)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])
                machine_write_word(machine, u32(array + 2 * index), value)

            case .SUB:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a - b))

            case .TEST_ATTR:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_branch)
                object := machine_read_operand(machine, &instruction.operands[0])
                attribute := machine_read_operand(machine, &instruction.operands[1])
                jump_condition = object_test_attr(machine, object, attribute)

        }


        if instruction.has_branch && jump_condition == instruction.branch_condition {
            offset := i16(instruction.branch_offset)
            switch offset {
                case 0: unimplemented("RFALSE")
                case 1: unimplemented("RTRUE")
                case: current_frame.pc = u32(i32(current_frame.pc) + i32(offset) - 2)
            }
        }

        delete_instruction(instruction)
    }
}
