package odinz

import "core:fmt"

Header :: struct {
    version: u8 `fmt:"x"`,
    flags1: u8 `fmt:"b"`,
    release: u16be `fmt:"d"`,
    highmem: u16be `fmt:"x"`,
    initialpc: u16be `fmt:"x"`,
    dictionary: u16be `fmt:"x"`,
    objects: u16be `fmt:"x"`,
    globals: u16be `fmt:"x"`,
    static: u16be `fmt:"x"`,
    flags2: u16be `fmt:"b"`,
    serial: [6]u8 `fmt:"s"`,
    abbreviations: u16be `fmt:"x"`,
    length: u16be `fmt:"x"`,
    checksum: u16be `fmt:"x"`,

    // TODO rest of header defined in 4+
}

Flags1_V3 :: bit_set[enum {
    _unused1,
    status_time,
    split,
    tandy,          // Appendix B of standard 1.1 defines this
    status_unavail,
    screen_split,
    variable_font,
    _unused2,
}; u8]

@(private="file")
Flags1_V4 :: bit_set[enum {
    colors,     // V5
    pictures,   // V6
    boldface,
    italics,
    monospace,
    sounds,     // V6
    _unused,
    timed,
}; u8]

@(private="file")
Flags2 :: bit_set[enum {
    transcript,     // V1
    forced_mono,    // V3
    redraw,         // V6
    pictures,       // V5
    undo,           // V5
    mouse,          // V5
    colour,         // V5
    sounds,         // V5
    menus,          // V6
    unused,
    print_error,    // Appendix B
    // rest unused
}; u16be]

@(private="file")
header_flags1_print :: proc(header: ^Header) {
    switch (header.version) {
    case 1, 2:
        // No flags in these versions. Implicit break in Odin
    case 3:
        flags := transmute(Flags1_V3)header.flags1
        if .status_time in flags {
            fmt.print("Display hours:minutes")
        } else {
            fmt.print("Display scores/moves")
        }
        if .split in flags do fmt.print(", Split over two discs")
        if .tandy in flags do fmt.print(", Tandy-bit set")
        if rest := flags - {.status_time, .split, .tandy}; rest != {} {
            fmt.printf(", and also these: %w", rest)
        }

    case 4, 5, 6:
        unimplemented(fmt.tprint("Unsupported version", header.version))

    case: unreachable("Error printing flags of header, invalid version %d", header.version)
    }
    fmt.println()
}

@(private="file")
header_flags2_print :: proc(header: ^Header) {
    print_comma := false
    flags := transmute(Flags2)header.flags2
    switch (header.version) {
        // Go from highest to lowest, add new bit in that version, then *fallthrough*
    case 6:
        unimplemented(fmt.tprint("Unsupported version", header.version))
        // fallthrough
    case 5:
        unimplemented(fmt.tprint("Unsupported version", header.version))
        // fallthrough
    case 4:
        unimplemented(fmt.tprint("Unsupported version", header.version))
        // fallthrough
    case 3:
        if .forced_mono in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Forced monospace")
        }
        // TODO, check if game is lurking horror
        //          if so, then check .undo and print about sounds
        //          Appendix B
        fallthrough
    case 2:
        fallthrough
    case 1:
        if .transcript in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Transcripting")
        }

    case: unreachable("Error printing flags 2 of header, invalid version %d", header.version)
    }
    if ! print_comma do fmt.print("None")
    fmt.println()

}

header_dump :: proc(machine: ^Machine) {
    header := machine_header(machine)

    raw_header := machine.memory[0:0x40]
    fmt.eprintfln("raw header = %02x", raw_header)
    fmt.eprintfln("header struct = %#v", header^)

    if header.version != 3 do unimplemented(fmt.tprint("Unsupported version", header.version))
    // Based off output from infodump

    fmt.printfln("Story file is %s", machine.romfile)
    fmt.println()
    fmt.println( "    **** Story file header ****" )
    fmt.println()
    fmt.printfln("%-26s%x", "Z-code version:" , header.version)
    fmt.printf("%-26s", "Interpreter flags:")
    header_flags1_print(header)
    fmt.printfln("%-26s%d", "Release number:" , header.release)
    fmt.printfln("%-26s%04x", "Size of resident memory:", header.highmem)
    fmt.printfln("%-26s%04x", "Start PC:", header.initialpc)
    fmt.printfln("%-26s%04x", "Dictionary address:", header.dictionary)
    fmt.printfln("%-26s%04x", "Object table address:", header.objects)
    fmt.printfln("%-26s%04x", "Global variables adress:", header.globals)
    fmt.printfln("%-26s%04x", "Size of dynamic memory:", header.static)
    fmt.printf("%-26s", "Game flags:")
    header_flags2_print(header)

    fmt.printfln("%-26s%s", "Serial number:", header.serial)
    fmt.printfln("%-26s%04x", "Abbreviations address:", header.abbreviations)

    file_length := int(header.length)
    switch {
    case header.version <=3: file_length *= 2
    case header.version <= 5: file_length *= 4
    case: file_length *= 8
    }
    if len(machine.memory) != file_length {
        fmt.printfln("%-26s%04x (%04x)", "File size (actual):", file_length, len(machine.memory))
    } else {
        fmt.printfln("%-26s%04x", "File size:", file_length)
    }

    actual_checksum : u16be = 0
    if file_length > len(machine.memory) do file_length = len(machine.memory)
    for num in machine.memory[0x40:file_length] do actual_checksum += u16be(num)
    if actual_checksum != header.checksum {
        fmt.printfln("%-26s%04x (%04x)", "Checksum (actual):", header.checksum, actual_checksum)
    } else {
        fmt.printfln("%-26s%04x", "Checksum (matches):", header.checksum)
    }

    // TODO rest of header defined in 4+

    // TODO header extension defined in 5+
    //          will include flags3
}


