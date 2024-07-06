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
        current_frame := &machine.frames[len(machine.frames) - 1]

        fmt.printfln("PC = %04x", current_frame.pc)
        // fmt.printfln("%v", current_frame^)
        // fmt.printfln("frames = %v", machine.frames)

        instruction := instruction_read(machine, current_frame.pc)
        current_frame.pc += u32(instruction.length)

        for i := 0; i < len(machine.frames) - 1; i += 1 do fmt.print(" >  ")
        instruction_dump(machine, &instruction, len(machine.frames) - 1)

        jump_condition := false

        switch instruction.opcode {
            case .UNKNOWN: unreachable()
            case .ADD:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                a := i16(machine_read_operand(machine, &instruction.operands[0]))
                b := i16(machine_read_operand(machine, &instruction.operands[1]))
                machine_write_variable(machine, u16(instruction.store), u16(a + b))

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

            case .LOADW:
                assert(len(instruction.operands) == 2)
                assert(instruction.has_store)
                array := machine_read_operand(machine, &instruction.operands[0])
                index := machine_read_operand(machine, &instruction.operands[1])
                machine_write_variable(machine, u16(instruction.store), machine_read_word(machine, u32(array + 2 * index)))

            case .PUT_PROP:
                assert(len(instruction.operands) == 3)
                object := machine_read_operand(machine, &instruction.operands[0])
                property := machine_read_operand(machine, &instruction.operands[1])
                value := machine_read_operand(machine, &instruction.operands[2])

                object_put_property(machine, object, property, value)

            case .RET:
                assert(len(instruction.operands) == 1)
                ret := machine_read_operand(machine, &instruction.operands[0])
                pop(&machine.frames)
                if current_frame.has_store do machine_write_variable(machine, u16(current_frame.store), ret)
                delete_frame(current_frame)

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

        }


        if instruction.has_branch && jump_condition == instruction.branch_condition {
            fmt.println("Jumping")
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
