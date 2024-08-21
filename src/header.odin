package odinz

import "core:fmt"

// https://zspec.jaredreisinger.com/11-header#11_1_3
Interpreter :: enum u8 {
    UNKNOWN,
    DEC_SYSTEM_20,
    APPLE_IIE,
    MACINTOSH,
    AMIGA,
    ATARI_ST,
    IBM_PC,
    COMMODORE_128,
    COMMODORE_64,
    APPLE_IIC,
    APPLE_IIGS,
    TANDY_COLOUR,
    NUM_INTERPRETERS
}
#assert(u8(Interpreter.NUM_INTERPRETERS) == 12)

// https://zspec.jaredreisinger.com/08-screen#8_3_1
Color :: enum u8 {
    CURRENT,
    DEFAULT,
    BLACK,
    RED,
    GREEN,
    YELLOW,
    BLUE,
    MAGENTA,
    CYAN,
    WHITE,
    LIGHT_GREY,
    MEDIUM_GREY,
    DARK_GREY,
    _RESERVED1,
    _RESERVED2,
    TRANSPARENT,
    PIXEL,
}

// https://zspec.jaredreisinger.com/08-screen#8_3_1
TrueColor :: enum i16be {
    CURRENT     = -2,
    DEFAULT     = -1,
    BLACK       = 0x0000,
    RED         = 0x001D,
    GREEN       = 0x0340,
    YELLOW      = 0x03BD,
    BLUE        = 0x59A0,
    MAGENTA     = 0x7C1F,
    CYAN        = 0x77A0,
    WHITE       = 0x7FFF,
    LIGHT_GREY  = 0x5AD6,
    MEDIUM_GREY = 0x4631,
    DARK_GREY   = 0x2D6B,
    TRANSPARENT = -4,
}

HeaderExtra :: struct #raw_union {
    infocom: [8]u8 `fmt:"s"`,
    inform: struct {
        unused: [4]u8,
        version: [4]u8 `fmt:"s"`,
    },
}

// https://zspec.jaredreisinger.com/11-header
Header :: struct {
    version: u8 `fmt:"x"`,
    flags1: Flag1 `fmt:"b"`,
    release: u16be `fmt:"d"`,
    highmem: u16be `fmt:"x"`,
    initialpc: u16be `fmt:"x"`,
    dictionary: u16be `fmt:"x"`,
    objects: u16be `fmt:"x"`,
    globals: u16be `fmt:"x"`,
    static: u16be `fmt:"x"`,
    flags2: Flag2 `fmt:"b"`,
    serial: [6]u8 `fmt:"s"`,
    abbreviations: u16be `fmt:"x"`,
    length: u16be `fmt:"x"`,
    checksum: u16be `fmt:"x"`,
    interpreter_num: Interpreter `fmt:"d"`,
    interpreter_version: u8 `fmt:"d"`,
    screen_height: u8 `fmt:"d"`,
    screen_width: u8 `fmt:"d"`,
    screen_width_px: u16be `fmt:"d"`,
    screen_height_px: u16be `fmt:"d"`,
    font1: u8 `fmt:"d"`,
    font2: u8 `fmt:"d"`,
    routines: u16be `fmt:"x"`,
    strings: u16be `fmt:"x"`,
    bgcolor: Color `fmt:"d"`,
    fgcolor: Color `fmt:"d"`,
    terminating: u16be `fmt:"x"`,
    stream3_width: u16be `fmt:"x"`,
    revision: u16be `fmt:"x"`,
    alphabet: u16be `fmt:"x"`,
    extension: u16be `fmt:"x"`,
    extra: HeaderExtra,
}
#assert(size_of(Header) == 0x40)

HeaderExtension :: struct {
    size: u16be `fmt:"d"`,
    xclick: u16be `fmt:"d"`,
    yclick: u16be `fmt:"d"`,
    unicode: u16be `fmt:"d"`,
    flags3: Flag3,
    fgcolor: TrueColor `fmt:"d"`,
    bgcolor: TrueColor `fmt:"d"`,
}
#assert(size_of(HeaderExtension) == 14)

header_font_width :: proc(header: ^Header) -> u8 {
    if header.version >= 6 do return header.font2
    else do return header.font1
}

header_font_height :: proc(header: ^Header) -> u8 {
    if header.version >= 6 do return header.font1
    else do return header.font2
}

Flag1 :: struct #raw_union { v3: Flag1_V3, v4: Flag1_V4 }

Flag1_V3 :: bit_set[enum {
    _unused1,
    status_time,
    split,
    tandy,          // Appendix B of standard 1.1 defines this
    status_unavail,
    screen_split,
    variable_font,
    _unused2,
}; u8]

Flag1_V4 :: bit_set[enum {
    colors,     // V5
    pictures,   // V6
    boldface,
    italics,
    monospace,
    sounds,     // V6
    _unused,
    timed,
}; u8]

Flag2 :: bit_set[enum {
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

Flag3 :: bit_set[enum {
    transparency,   // V6
}; u16be]

@(private="file")
header_flags1_print :: proc(header: ^Header) {
    switch (header.version) {
    case 1, 2:
        // No flags in these versions. Implicit break in Odin
    case 3:
        flags := header.flags1.v3
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

    case 4, 5, 6, 7, 8:
        fmt.printf("None")

    case: unreachable("Error printing flags of header, invalid version %d", header.version)
    }
    fmt.println()
}

@(private="file")
header_flags2_print :: proc(header: ^Header) {
    print_comma := false
    flags := header.flags2
    switch (header.version) {
        // Go from highest to lowest, add new bit in that version, then *fallthrough*
    case 6, 7, 8:
        if .menus in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Supports menus")
        }
        fallthrough
    case 5:
        if .pictures in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Supports pictures")
        }
        if .undo in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Supports undo")
        }
        if .mouse in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Supports mouse")
        }
        if .colour in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Supports colour")
        }
        if .sounds in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Supports sounds")
        }
        fallthrough
    case 3, 4:
        if .forced_mono in flags {
            if print_comma do fmt.print(", ")
            else do print_comma = true
            fmt.print("Forced monospace")
        }
        // TODO, check if game is lurking horror
        //          if so, then check .undo and print about sounds
        //          Appendix B
        fallthrough
    case 1, 2:
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

@(private="file")
header_flags3_print :: proc(header: ^Header, extension: ^HeaderExtension) {
    if header.version >= 6 && extension.size >= 4 && .transparency in extension.flags3 {
        fmt.print("Supports transparency")
    } else do fmt.print("None")
    fmt.println()
}

header_file_length :: proc(header: ^Header) -> int {
    file_length := int(header.length)
    switch {
        case header.version <= 3: file_length *= 2
        case header.version <= 5: file_length *= 4
        case: file_length *= 8
    }
    return file_length
}

machine_checksum :: proc(machine: ^Machine) -> u16be {
    header := machine_header(machine)
    file_length := header_file_length(header)
    actual_checksum : u16be = 0
    if file_length > len(machine.memory) do file_length = len(machine.memory)
    for num in machine.memory[0x40:file_length] do actual_checksum += u16be(num)
    return actual_checksum
}

header_dump :: proc(machine: ^Machine) {
    header := machine_header(machine)

    raw_header := machine.memory[0:0x40]

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

    file_length := header_file_length(header)
    if len(machine.memory) != file_length {
        fmt.printfln("%-26s%04x (%04x)", "File size (actual):", file_length, len(machine.memory))
    } else {
        fmt.printfln("%-26s%04x", "File size:", file_length)
    }

    actual_checksum := machine_checksum(machine)
    if actual_checksum != header.checksum {
        fmt.printfln("%-26s%04x (%04x)", "Checksum (actual):", header.checksum, actual_checksum)
    } else {
        fmt.printfln("%-26s%04x", "Checksum (matches):", header.checksum)
    }

    if header.version >= 6 {
        fmt.printfln("%-26s%04x", "Routines offset:", header.routines)
        fmt.printfln("%-26s%04x", "Strings offset:", header.strings)
    }
    if header.version >= 5 {
        fmt.printfln("%-26s%04x", "Terminating address:", header.terminating)
        if header.terminating != 0 {
            unimplemented("%-26s", "    Keys Used:")
        }
        fmt.printfln("%-26s%04x", "Alphabet address:", header.alphabet)
        fmt.printfln("%-26s%04x", "Header extension address", header.extension)
        if header.extension != 0 {
            extension := machine_header_extension(machine)
            fmt.printfln("%-26s%04x", "Header extension size", extension.size)
            if extension.size >= 3 do fmt.printfln("%-26s%04x", "Unicode address", extension.unicode)
            if extension.size >= 4 {
                fmt.printfln("%-26s", "Extension flags:")
                header_flags3_print(header, extension)
            }
        }
    }

    if header.extra.inform.version[0] != 0 {
        fmt.printfln("%-26s%s", "Inform version:", header.extra.inform.version)
    }
}


