package odinz

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:slice"

Trace :: bit_set[enum {
    instruction,
    read,
    write,
    frame,
    backtrace,
}]

Config :: struct {
    trace: Trace,
    status: bool,
    screen_split: bool,
    alternate_screen: bool,
}

Screen :: struct {
    tty: bool,
    width: uint,
    height: uint,
}

Machine :: struct {
    romfile: string,
    config: Config,
    screen: Screen,
    memory: []u8,
    frames: [dynamic]Frame,
}

machine_header :: proc(machine: ^Machine) -> ^Header {
    raw_header := machine.memory[0:0x40]
    ptr, ok := slice.get_ptr(raw_header, 0)
    if !ok do unreachable("Could not get header slice")
    return transmute(^Header)ptr;
}

machine_dump :: proc(machine: ^Machine, to_disk := false, dump_memory := false) {
    if to_disk {
        if !os.write_entire_file("machine.dump", machine.memory) {
            unreachable("Error writing machine dump")
        }
        return
    }

    // FIXME have a param to say save to disk. Can then use ztools to inspect
    fmt.println()
    fmt.println("***** Machine dump *****")
    fmt.println()
    fmt.println("romfile=", machine.romfile)
    fmt.println(len(machine.frames), "frames:")
    for frame in machine.frames {
        fmt.println(frame)
    }
    if dump_memory {
        fmt.println("memory:")
        for i := 0; i < len(machine.memory); i += 0x10 {
            fmt.printf("%06x ", i)
            for b := 0; b < 0x10; b += 2 {
                fmt.printf(" %02x%02x", machine.memory[i + b], machine.memory[i + b + 1])
            }
            fmt.println()
        }
    }
}

bit :: proc(byte: u8, bit: u8) -> bool {
    return byte | (1<<bit) == byte
}

machine_read_byte :: proc(machine: ^Machine, address: u32) -> u8 {
    if int(address) >= len(machine.memory) do unreachable()
    if .read in machine.config.trace do fmt.printfln("READ @ 0x%04x: 0x%02x", address, machine.memory[address])
    return machine.memory[address]
}

machine_read_word :: proc(machine: ^Machine, address: u32) -> u16 {
    if .read in machine.config.trace {
        machine.config.trace &= ~{.read}
        defer machine.config.trace |= {.read}
        word := u16(machine_read_byte(machine, address)) << 8 + u16(machine_read_byte(machine, address + 1))
        fmt.printfln("READ @ 0x%04x: 0x%04x", address, word)
        return word
    }
    return u16(machine_read_byte(machine, address)) << 8 + u16(machine_read_byte(machine, address + 1))
}

machine_write_byte :: proc(machine: ^Machine, address: u32, value: u8) {
    if int(address) >= len(machine.memory) do unreachable()
    if .write in machine.config.trace do fmt.printfln("WRITE @ 0x%04x: 0x%02x", address, value)
    machine.memory[address] = value
}

machine_write_word :: proc(machine: ^Machine, address: u32, value: u16) {
    if .write in machine.config.trace {
        machine.config.trace &= ~{.write}
        defer machine.config.trace |= {.write}
        fmt.printfln("WRITE @ 0x%04x: 0x%04x", address, value)
        machine_write_byte(machine, address, u8(value >> 8))
        machine_write_byte(machine, address + 1, u8(value))
        return
    }
    machine_write_byte(machine, address, u8(value >> 8))
    machine_write_byte(machine, address + 1, u8(value))
}

machine_read_global :: proc(machine: ^Machine, global: u16) -> u16 {
    if .read in machine.config.trace {
        machine.config.trace &= ~{.read}
        defer machine.config.trace |= {.read}
        word := machine_read_word(machine, u32(machine_header(machine).globals) + u32(global) * 2)
        fmt.printfln("READ @ G%02x: 0x%04x", global, word)
        return word
    }
    return machine_read_word(machine, u32(machine_header(machine).globals) + u32(global) * 2)
}

machine_write_global :: proc(machine: ^Machine, global: u16, value: u16) {
    if .write in machine.config.trace {
        machine.config.trace &= ~{.write}
        defer machine.config.trace |= {.write}
        fmt.printfln("WRITE @ G%02x: 0x%04x", global, value)
        machine_write_word(machine, u32(machine_header(machine).globals) + u32(global) * 2, value)
        return
    }
    machine_write_word(machine, u32(machine_header(machine).globals) + u32(global) * 2, value)
}

machine_read_variable :: proc(machine: ^Machine, variable: u16) -> u16 {
    current_frame := &machine.frames[len(machine.frames) - 1]
    switch variable {
        case 0:
            if len(current_frame.stack) == 0 do unreachable("Stack underflow")
            if .read in machine.config.trace {
                fmt.printfln("READ @ STACK: 0x%04x, %v", current_frame.stack[0], current_frame.stack[1:])
            }
            return pop(&current_frame.stack)

        case 1..<16:
            if int(variable) > len(current_frame.variables) do unreachable("Variable overflow")
            word := current_frame.variables[variable - 1]
            if .read in machine.config.trace {
                fmt.printfln("READ @ L%02x: 0x%04x", variable - 1, word)
            }
            return word

        case 16..<255: return machine_read_global(machine, variable - 16)
        case: unreachable("Error while reading variable. Unexpected number %d", variable)
    }
}

machine_write_variable :: proc(machine: ^Machine, variable: u16, value: u16) {
    current_frame := &machine.frames[len(machine.frames) - 1]
    switch variable {
        case 0:
            append(&current_frame.stack, value)
            if .write in machine.config.trace {
                fmt.printfln("WRITE @ STACK: 0x%04x, %v", value, current_frame.stack)
            }
        case 1..<16:
            if int(variable) > len(current_frame.variables) do unreachable("Variable overflow")
            if .write in machine.config.trace {
                fmt.printfln("WRITE @ L%02x: 0x%04x", variable - 1, value)
            }
            current_frame.variables[variable - 1] = value

        case 16..<255: machine_write_global(machine, variable - 16, value)
        case:
            unreachable("Error while writing variable. Unexpected number %d", variable)
    }
}

machine_read_operand :: proc(machine: ^Machine, operand: ^Operand) -> u16 {
    switch operand.type {
        case .SMALL_CONSTANT, .LARGE_CONSTANT: return operand.value
        case .VARIABLE: return machine_read_variable(machine, operand.value)
    }
    unreachable("Error while reading operand")
}

@(private="file")
add_flag1_v3 :: proc(machine: ^Machine, flag: Flags1_V3) {
    header := machine_header(machine)
    header.flags1 = transmute(u8)(transmute(Flags1_V3)header.flags1 + flag)
}

initialise_machine :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version != 3 {
        unimplemented(
            fmt.tprintf("Unsupported version %d in '%s'", header.version, machine.romfile)
        )
    }
    append(&machine.frames, Frame {
        pc = u32(header.initialpc),
    })
    // FIXME set various bits and stuff in header

    if header.version <= 3 {
        if !machine.config.status do add_flag1_v3(machine, {.status_unavail})
        if machine.config.screen_split do add_flag1_v3(machine, {.screen_split})
    }

    if machine.config.alternate_screen {
        fmt.print("\e[?1049h")
        libc.atexit(proc "c" () {libc.fprintf(libc.stdout, "\e[?1049l")})
    }
    if !is_tty() do return
    // FIXME handle signals to detect change in size
    fmt.printfln("tty = %v", is_tty())
    machine.screen.width, machine.screen.height = get_term_size()
    fmt.printfln("width = %d, height = %d", machine.screen.width, machine.screen.height)
    clear_screen()
    set_cursor(0, machine.screen.height - 1)
}
