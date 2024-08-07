package odinz

import "core:slice"
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
    input: bool,
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
                    if header.version >= 2 {
                        zstring.char = zchar
                        zstring.mode = .ABBREV
                    } else do fmt.sbprintln(zstring.sb)
                case 2, 3:
                    if header.version >= 3 {
                        zstring.char = zchar
                        zstring.mode = .ABBREV
                    } else do unimplemented("shift lock")
                case 4:
                    if header.version >= 3 do zstring.mode = .A1
                    else do unimplemented("shift lock")
                case 5:
                    if header.version >= 3 do zstring.mode = .A2
                    else do unimplemented("shift lock")
                case 6..=31:
                    switch zstring.mode {
                        case .A0: fmt.sbprint(zstring.sb, zstring_alphabet_0[zchar - 6])
                        case .A1:
                            fmt.sbprint(zstring.sb, zstring_alphabet_1[zchar - 6])
                            if header.version >= 3 do zstring.mode = .A0
                        case .A2:
                            if zchar == 6 do zstring.mode = .ZSCII_1
                            else {
                                fmt.sbprint(zstring.sb, zstring_alphabet_2[zchar - 6])
                                if header.version >= 3 do zstring.mode = .A0
                            }

                        case .ZSCII_1, .ZSCII_2, .ABBREV:
                            fallthrough
                        case:
                            unreachable("Parsing zstring failed. Invalid mode");
                    }
                case:
                    unreachable("Parsing zstring failed. Invalid zchar %d", zchar)
            }

        case .ZSCII_1:
            zstring.char = zchar
            zstring.mode = .ZSCII_2

        case .ZSCII_2:
            mask := u8(0b11111)
            code := (u16(zstring.char & mask) << 5) | u16(zchar & mask)
            if zstring.input do unimplemented()
            else do fmt.sbprint(zstring.sb, zstring_output_zscii(machine, code))
            zstring.mode = .A0

        case .ABBREV:
            index := 32 * u32(zstring.char - 1) + u32(zchar)
            addr := u32(machine_read_word(machine, u32(header.abbreviations) + 2 * index))
            // addr is a "word address" which is only used by abbreviations. S1.1.2 in spec
            fmt.sbprint(zstring.sb, zstring_read(machine, addr * 2, nil))
            zstring.mode = .A0

        case:
            unreachable("Parsing zstring failed. Invalid mode")
    }
}

delete_zstring :: proc(zstring: ZString) {
    strings.builder_destroy(zstring.sb)
}

zstring_read :: proc(machine: ^Machine, address: u32, length: ^u16 = nil) -> string {
    sb, err := strings.builder_make_none()
    if err != nil do unreachable("Buy more RAM: %v", err)
    zstring := ZString{sb = &sb}
    defer delete_zstring(zstring)
    if length != nil && length^ > 0 {
        for i: u16 = 0; i < length^; i = i + 1 {
            word := machine_read_word(machine, address + u32(i) * 2)

            zstring_process_zchar(machine, &zstring, u8((word >> 10) & 0b11111))
            zstring_process_zchar(machine, &zstring, u8((word >> 5) & 0b11111))
            zstring_process_zchar(machine, &zstring, u8((word >> 0) & 0b11111))
            if i < length^ - 1 && bit(u8(word >> 8), 7) {
                unreachable("Not the last word of a %d length zstring @ 0x%16x, but bit 7 of first byte is set\n" +
                        "Processed %d words, zstring so far is \"%s\", and this word just processed is 0b%16b",
                        length^, address, i, strings.to_string(zstring.sb^), word)
            }
            if i == length^ - 1 && !bit(u8(word >> 8), 7) {
                unreachable("On the last word of a %d length zstring @ 0x%16x, but bit 7 of first byte is NOT set\n" +
                            "Zstring is \"%s\", and this word just processed is 0b%16b",
                            length^, address, strings.to_string(zstring.sb^), word)
            }
        }
    } else {
        i := 0
        for ; ; i += 2 {
            word := machine_read_word(machine, address + u32(i))

            zstring_process_zchar(machine, &zstring, u8((word >> 10) & 0b11111))
            zstring_process_zchar(machine, &zstring, u8((word >> 5) & 0b11111))
            zstring_process_zchar(machine, &zstring, u8((word >> 0) & 0b11111))
            if bit(u8(word >> 8), 7) do break
        }
        if length != nil do length^ = u16(i + 2)
    }
    ret, err2 := strings.clone(strings.to_string(zstring.sb^))
    if err2 != nil do unreachable("Buy more RAM: %v", err2)
    return ret
}

zstring_output_zscii :: proc(machine: ^Machine, char: u16) -> string {
    header := machine_header(machine)
    assert(char <= 1023)
    // Must be defined for output in ZSCII (S3.8 in specs)
    switch char {
        case 0: return "" // null, no-op for output
        case 1..=7: unreachable()
        case 8: unreachable() // delete, undefined for output
        case 9:
            if header.version != 6 do unreachable() // undefined
            return "\t"
        case 10: unreachable()
        case 11:
            if header.version != 6 do unreachable() // undefined
            return "  "
        case 12: unreachable()
        case 13: return fmt.tprintln()
        case 14..=26: unreachable()
        case 27:
            // ESC. Need to be careful about dodgy escape codes
            unimplemented()
        case 28..=31: unreachable()
        case 32..=126: return fmt.tprintf("%c", char)
        case 127, 128: unreachable()
        case 129..=154: unreachable() // undefined for output
        case 155..=251:
            unimplemented("Extra characters")
        case: unreachable()
    }
    unreachable()
}

@(private="file")
zstring_encode_zchars :: proc(machine: ^Machine, word: string, zchars_ptr: ^[]u8) {
    header := machine_header(machine)
    if header.version <= 2 do unimplemented()
    if header.version >= 5 do unimplemented("alphabet tables")

    assert(zchars_ptr != nil)
    length := len(zchars_ptr^)
    slice.fill(zchars_ptr^, 5)
    // Encode zchars
    index := 0
    for c in word {
        if index >= length do return

        if slice.contains(zstring_alphabet_0[:], c) {
            entry, found := slice.linear_search(zstring_alphabet_0[:], c)
            assert(found)
            zchars_ptr^[index] = 6 + u8(entry)
            index += 1
        } else if slice.contains(zstring_alphabet_1[:], c) {
            entry, found := slice.linear_search(zstring_alphabet_1[:], c)
            assert(found)
            zchars_ptr^[index] = 4
            if index + 1 >= length do return
            zchars_ptr^[index + 1] = 6 + u8(entry)
            index += 2
        } else if slice.contains(zstring_alphabet_2[:], c) {
            entry, found := slice.linear_search(zstring_alphabet_2[:], c)
            assert(found)
            zchars_ptr^[index] = 5
            if index + 1 >= length do return
            zchars_ptr^[index + 1] = 6 + u8(entry)
            index += 2
        } else {
            // zcsii escape
            zchars_ptr^[index] = 5
            if index + 1 >= length do return
            zchars_ptr^[index + 1] = 6
            if index + 2 >= length do return
            switch c {
                case 32..=126:
                    code := u16(c)
                    zchars_ptr^[index + 2] = u8(code >> 5) & 0b11111
                    if index + 2 >= length do return
                    zchars_ptr^[index + 3] = u8(code) & 0b11111
                case: unimplemented("extra characters")
            }
            index += 4
        }
    }
}

zstring_encode :: proc(machine: ^Machine, word: string, data_ptr: ^[]u16) {
    // https://zspec.jaredreisinger.com/03-text#3_7
    assert(data_ptr != nil)
    length := len(data_ptr^)
    zchars := make([]u8, length * 3)
    defer delete(zchars)

    zstring_encode_zchars(machine, word, &zchars)

    // Assemble zchars into zwords
    for index := 0; index + 2 < len(zchars); index += 3 {
        mask := u16(0b11111)
        word := ((u16(zchars[index]) & mask) << 10) | ((u16(zchars[index+1]) & mask) << 5) | ((u16(zchars[index+2])) & mask)
        data_ptr^[index / 3] = word
    }
    // Set top bit of last word to signal stop
    data_ptr^[length-1] = 0x8000 | data_ptr^[length-1]
}
