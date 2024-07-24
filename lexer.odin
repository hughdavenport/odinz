package odinz

import "core:fmt"
import "core:os"

lexer_read :: proc(machine: ^Machine, text: u32, parse: u32) {
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
            if c >= 'A' && c <= 'Z' do c += 32
            machine_write_byte(machine, text + done + 1, c)
        }
        done += 1
    }

    fmt.printfln("text = %x (%s)", machine.memory[text+1:][:done], machine.memory[text+1:][:done])
}

lexer_analyse :: proc(machine: ^Machine, text: u32, parse: u32) {
    header := machine_header(machine)
    if header.version >= 5 && parse == 0 do return

    unimplemented()
}
