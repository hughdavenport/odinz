package odinz

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

@(private="file")
LexedBlock :: struct {
    word: string,
    index: u8,
}

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

lexer_split :: proc(machine: ^Machine, input: string, limit: u8) -> [dynamic]LexedBlock {
    // https://zspec.jaredreisinger.com/13-dictionary#13_6
    header := machine_header(machine)
    dictionary := u32(header.dictionary)
    n := machine_read_byte(machine, dictionary)
    ret: [dynamic]LexedBlock
    separators := make([]u8, n)
    defer delete(separators)
    for i := u8(0); i < n; i += 1 {
        separators[i] = machine_read_byte(machine, dictionary + u32(i) + 1)
    }
    offset := 0
    for index := 0; index < len(input); index += 1 {
        if len(ret) > int(limit) do return ret
        c := u8(input[index])
        if c == ' ' {
            word := input[offset:index]
            if len(word) > 0 do append(&ret, LexedBlock{word=word, index=u8(offset)})
            offset = index + 1
            continue
        }
        if slice.contains(separators, c) {
            word := input[offset:index]
            if len(word) > 0 {
                append(&ret, LexedBlock{word=word, index=u8(offset)})
                if len(ret) > int(limit) do return ret
            }
            append(&ret, LexedBlock{word=input[index:][:1], index=u8(index)})
            offset = index + 1
        }
    }
    if len(ret) > int(limit) do return ret
    word := input[offset:]
    if len(word) > 0 do append(&ret, LexedBlock{word=word, index=u8(offset)})
    return ret
}

lexer_analyse :: proc(machine: ^Machine, text: u32, parse: u32) {
    // https://zspec.jaredreisinger.com/15-opcodes#read
    // https://zspec.jaredreisinger.com/13-dictionary#13_6
    // https://zspec.jaredreisinger.com/03-text#3_7
    header := machine_header(machine)
    if header.version >= 5 && parse == 0 do return

    input := lexer_read(machine, text)
    defer delete(input)
    limit := machine_read_byte(machine, parse)
    blocks := lexer_split(machine, input, limit)
    defer delete(blocks)
    machine_write_byte(machine, parse + 1, u8(len(blocks)))

    data: []u16
    if header.version >= 4 do data = make([]u16, 3)
    else do data = make([]u16, 2)
    parse_entry := parse + 2
    for block in blocks {
        zstring_encode(machine, block.word, &data)
        addr := dictionary_search(machine, data)
        machine_write_word(machine, parse_entry, u16(addr))
        machine_write_byte(machine, parse_entry + 2, u8(len(block.word)))
        machine_write_byte(machine, parse_entry + 3, block.index + 1)
        parse_entry += 4
    }
}
