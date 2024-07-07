package odinz

import "core:strings"
import "core:fmt"

@(private="file")
ZString_Mode :: enum {
    A0,
    A1,
    A2,
    ZSCII_1,
    ZSCII_2,
    ABBREV,
}

ZString :: struct {
    sb: ^strings.Builder,
    mode: ZString_Mode,
    char: u8,
}

@(private="file")
zstring_alphabet_0 := [26]rune{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' }
@(private="file")
zstring_alphabet_1 := [26]rune{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' }
@(private="file")
zstring_alphabet_2 := [26]rune{ 0, '\n', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', ',', '!', '?', '_', '#', '\'', '"', '/', '\\', '-', ':', '(', ')' }

@(private="file")
zstring_initialized := false
@(private="file")
zstring_initialize :: proc(machine: ^Machine) {
    header := machine_header(machine)
    if header.version == 1 do unimplemented("diff A2 table")
    if header.version >= 5 do unimplemented("alphabet tables")
    zstring_initialized = true
}

@(private="file")
zstring_process_zchar :: proc(machine: ^Machine, zstring: ^ZString, zchar: u8) {
    if !zstring_initialized do zstring_initialize(machine)
    header := machine_header(machine)
    if header.version != 3 do unimplemented()
    switch zstring.mode {
        case .A0, .A1, .A2:
            switch zchar {
                case 0: fmt.sbprint(zstring.sb, " ")
                case 1:
                    if header.version >= 2 do unimplemented("abbrevs")
                    else do fmt.sbprintln(zstring.sb)
                case 2, 3:
                    if header.version >= 3 do unimplemented("abbrevs")
                    else do unimplemented("shift lock")
                case 4:
                    if header.version >= 3 do zstring.mode = .A1
                    else do unimplemented("shift lock")
                case 5:
                    if header.version >= 3 do zstring.mode = .A2
                    else do unimplemented("shift lock")
                case 6..=31:
                    switch zstring.mode {
                        case .A0: fmt.sbprint(zstring.sb, zstring_alphabet_0[zchar - 6])
                        case .A1: fmt.sbprint(zstring.sb, zstring_alphabet_1[zchar - 6])
                        case .A2:
                            if zchar == 6 do zstring.mode = .ZSCII_1
                            else do fmt.sbprint(zstring.sb, zstring_alphabet_2[zchar - 6])

                        case .ZSCII_1, .ZSCII_2, .ABBREV:
                            fallthrough
                        case:
                            unreach("Parsing zstring failed. Invalid mode");
                    }
                case:
                    unreach("Parsing zstring failed. Invalid zchar %d", zchar, machine=machine);
            }

        case .ZSCII_1: unimplemented()
        case .ZSCII_2: unimplemented()
        case .ABBREV: unimplemented()

        case:
            unreach("Parsing zstring failed. Invalid mode", machine=machine);
    }
}

delete_zstring :: proc(zstring: ZString) {
    strings.builder_destroy(zstring.sb)
}

zstring_dump :: proc(machine: ^Machine, address: u16, length: u8 = 0) {
    sb, err := strings.builder_make_none()
    if err != nil do unreach("Buy more RAM: %v", err, machine=machine);
    zstring := ZString{sb = &sb}
    defer delete_zstring(zstring)
    if length > 0 {
        for i: u8 = 0; i < length; i = i + 1 {
            word := machine_read_word(machine, u32(address + u16(i * 2)))

            zstring_process_zchar(machine, &zstring, u8((word >> 10) & 0b11111))
            zstring_process_zchar(machine, &zstring, u8((word >> 5) & 0b11111))
            zstring_process_zchar(machine, &zstring, u8((word >> 0) & 0b11111))
            if i < length - 1 && bit(u8(word >> 8), 7) {
                unreach("Not the last word of a %d length zstring @ 0x%16x, but bit 7 of first byte is set\n" +
                        "Processed %d words, zstring so far is \"%s\", and this word just processed is 0b%16b",
                        length, address, i, strings.to_string(zstring.sb^), word)
            }
            if i == length - 1 && !bit(u8(word >> 8), 7) {
                unreach("On the last word of a %d length zstring @ 0x%16x, but bit 7 of first byte is NOT set\n" +
                        "Zstring is \"%s\", and this word just processed is 0b%16b",
                        length, address, strings.to_string(zstring.sb^), word)
            }
        }
        fmt.print(strings.to_string(zstring.sb^))
    } else {
        fmt.println(); unimplemented()
    }
}
