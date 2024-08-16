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
    status_off: bool,
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
    if int(address) >= len(machine.memory) do unreachable("Memory out of bounds, READ @ 0x%02x. Max = 0x%02x", address, len(machine.memory))
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

machine_write_header :: proc(machine: ^Machine, address: u32, value: u8) {
    assert(address <= 0x40)
    if address != 0x10 && address != 0x11 {
        // Most bytes are not writable, in fact only flags2
        unreachable("Illegal write to header address 0x%02x", address)
    }
    header := machine_header(machine)
    full_value: u16be
    if address == 0x10 do full_value = (u16be(value) << 8) | (transmute(u16be)header.flags2 & 0xff)
    if address == 0x11 do full_value = u16be(value) | (transmute(u16be)header.flags2 & 0xff00)
    flag := transmute(Flag2)full_value

    diff := (flag - header.flags2) | (header.flags2 - flag)
    if diff - {.transcript, .forced_mono, .redraw} != {} {
        unreachable("Illegal write to header flag 2 @ 0x%02x, value = %08b\nchanging these immutable flags: %w\ncurrent = %w\nnew = %w",
            address, value, diff, header.flags2, flag)
    }

    if (flag & {.transcript}) != (header.flags2 & {.transcript}) {
        if .write in machine.config.trace do fmt.printfln("WRITE header flag2 transcript %v", .transcript in flag)
        unimplemented()
    }

    if (flag & {.forced_mono}) != (header.flags2 & {.forced_mono}) {
        if header.version < 3 do unreachable()
        if .write in machine.config.trace do fmt.printfln("WRITE header flag2 forced monospace %v", .transcript in flag)
        unimplemented()
    }

    if (flag & {.redraw}) != (header.flags2 & {.redraw}) {
        if header.version < 6 do unreachable()
        if .write in machine.config.trace do fmt.printfln("WRITE header flag2 redraw %v", .transcript in flag)
        // This is in response to interpreter asking, so don't care
    }

    if flag != header.flags2 do fmt.printfln("WRITE header flag2 %w -> %w", header.flags2, flag)
    header.flags2 = flag
}

machine_write_byte :: proc(machine: ^Machine, address: u32, value: u8) {
    if address <= 0x40 {
        machine_write_header(machine, address, value)
        return
    }
    if int(address) >= len(machine.memory) do unreachable("Memory out of bounds, WRITE 0x%02X @ 0x%02x. Max = 0x%02x", value, address, len(machine.memory))
    if .write in machine.config.trace do fmt.printfln("WRITE @ 0x%04x: 0x%02x", address, value)
    machine.memory[address] = value
}

machine_write_word :: proc(machine: ^Machine, address: u32, value: u16) {
    if address > 0x40 && .write in machine.config.trace {
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

        case 16..=255: return machine_read_global(machine, variable - 16)
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

        case 16..=255: machine_write_global(machine, variable - 16, value)
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
_initilise_machine_flags1 :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version <= 3 {
        header.flags1.v3 -= {.status_unavail, .screen_split, .variable_font}
        if machine.config.status_off do header.flags1.v3 += {.status_unavail}
        if machine.config.screen_split do header.flags1.v3 += {.screen_split}
        // FIXME add a config option
        if false do header.flags1.v3 += {.variable_font}
    } else {
        header.flags1.v4 = {}
        // FIXME add config options
        if header.version >= 6 && false do header.flags1.v4 += {.pictures}
        if header.version >= 6 && false do header.flags1.v4 += {.sounds}
        if false do header.flags1.v4 += {.timed}
        // FIXME add config options, or detect based on term?
        if header.version >= 5 && false do header.flags1.v4 += {.colors}
        if false do header.flags1.v4 += {.boldface}
        if false do header.flags1.v4 += {.italics}
        if false do header.flags1.v4 += {.monospace}
    }
}

@(private="file")
_initilise_machine_flags2 :: proc(machine: ^Machine) {
    header := machine_header(machine)
    header.flags2 -= {.transcript, .forced_mono, .pictures, .undo, .mouse, .sounds, .menus}

    // FIXME add config options
    if header.version >= 3 && true do header.flags2 += {.forced_mono}
    if false do header.flags2 += {.transcript}
    if header.version >= 5 && false do header.flags2 += {.pictures}
    if header.version >= 5 && false do header.flags2 += {.undo}
    if header.version >= 5 && false do header.flags2 += {.mouse}
    if header.version >= 5 && false do header.flags2 += {.sounds}
    if header.version >= 6 && false do header.flags2 += {.menus}
}

restart_machine :: proc(machine: ^Machine) {
    // https://zspec.jaredreisinger.com/06-game-state#6_1_3
    header := machine_header(machine)
    flags2 := header.flags2

    delete_machine(machine)
    data, ok := os.read_entire_file(machine.romfile)
    if !ok do unreachable("Could not read '%s'", machine.romfile)
    machine.memory = data
    initialise_machine(machine)

    // https://zspec.jaredreisinger.com/06-game-state#6_1_3
    header = machine_header(machine)
    header.flags2 = flags2
}

delete_machine :: proc(machine: ^Machine) {
    clear(&machine.frames)
    delete(machine.memory)
}

initialise_machine :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version == 6 {
        routine := routine_read(machine, packed_addr(machine, u16(header.initialpc)))
        append(&machine.frames, routine)
    } else do append(&machine.frames, Frame { pc = u32(header.initialpc) })

    _initilise_machine_flags1(machine)
    _initilise_machine_flags2(machine)

    if header.version >= 4 {
        header.interpreter_num = Interpreter.IBM_PC
        header.interpreter_version = 0
    }

    if header.version >= 5 && header.extension != 0 {
        // FIXME header extension
        // unimplemented()
    }

    // Adhere's to Standard 1.1
    header.revision = 0x101

    if machine.config.alternate_screen {
        fmt.print("\e[?1049h")
        libc.atexit(proc "c" () {libc.fprintf(libc.stdout, "\e[?1049l")})
    }
    if !is_tty() do return
    // FIXME handle signals to detect change in size
    machine.screen.width, machine.screen.height = get_term_size()
    if header.version >= 4 {
        header.screen_width = u8(machine.screen.width)
        header.screen_height = u8(machine.screen.height)
    }
    if header.version >= 5 {
        header.screen_width_px = u16be(header.screen_width)
        header.screen_height_px = u16be(header.screen_height)
        header.font1 = 1
        header.font2 = 1
        header.bgcolor = .BLACK
        header.fgcolor = .WHITE
    }
    clear_screen()
    set_cursor(0, machine.screen.height - 1)
}
