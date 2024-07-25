package odinz

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

lexer_read :: proc(machine: ^Machine, text: u32) -> string {
    // https://zspec.jaredreisinger.com/15-opcodes#read
    header := machine_header(machine)
    length := machine_read_byte(machine, text)
    data: []u8 = { 0 }
    done := u32(0)
    if header.version >= 5 {
        done = u32(machine_read_byte(machine, text + 1))
        if done != 0 do unimplemented("Reading left over text")
        done += 1
    }
    defer if header.version >= 5 do machine_write_byte(machine, text + 1, u8(done) - 1)
    for {
        if done == u32(length) {
            if header.version < 5 do machine_write_byte(machine, text + done + 1, 0)
            break
        }

        read, err := os.read(os.stdin, data)
        if err != os.ERROR_NONE {
            fmt.println(err)
            unimplemented("Error handling")
        }

        if data[0] == '\n' {
            if header.version < 5 do machine_write_byte(machine, text + done + 1, 0)
            break
        } else {
            c := data[0]
            switch c {
                case '\n', 32..=126, 155..=251:
                case: continue
            }
            if c >= 'A' && c <= 'Z' do c += 32
            machine_write_byte(machine, text + done + 1, c)
        }
        done += 1
    }

    if header.version >= 5 {
        return strings.clone_from(machine.memory[text+2:][:done])
    } else {
        return strings.clone_from(machine.memory[text+1:][:done])
    }
}

lexer_split :: proc(machine: ^Machine, input: string) -> [dynamic]string {
    header := machine_header(machine)
    dictionary := u32(header.dictionary)
    n := machine_read_byte(machine, dictionary)
    ret: [dynamic]string
    separators := make([]u8, n)
    defer delete(separators)
    for i := u8(0); i < n; i += 1 {
        separators[i] = machine_read_byte(machine, dictionary + u32(i) + 1)
    }
    offset := 0
    for index := 0; index < len(input); index += 1 {
        c := u8(input[index])
        if c == ' ' {
            word := input[offset:index]
            offset = index + 1
            if len(word) > 0 do append(&ret, word)
            continue
        }
        if slice.contains(separators, c) {
            word := input[offset:index]
            if len(word) > 0 do append(&ret, word)
            append(&ret, input[index:][:1])
            offset = index + 1
        }
    }
    word := input[offset:]
    if len(word) > 0 do append(&ret, word)
    return ret
}

lexer_analyse :: proc(machine: ^Machine, text: u32, parse: u32) {
    // https://zspec.jaredreisinger.com/13-dictionary#13_6
    header := machine_header(machine)
    if header.version >= 5 && parse == 0 do return

    input := lexer_read(machine, text)
    defer delete(input)
    words := lexer_split(machine, input)
    defer delete(words)
    fmt.println("words:", words)

    // For each word
    // - Encode zstring
    //  - dictionary form
    //  - no abbrevs
    //  - input zscii (if needed)
    //  - truncated to size of supplied byte
    // - Find dict entry
    //  - Binary search
    // - Write parse table entry
    // Write parse table length

    if true do unimplemented()
}
