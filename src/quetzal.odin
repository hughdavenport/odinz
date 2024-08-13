package odinz

import "core:encoding/endian"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"

@(private="file")
IFF_Type :: enum {
    UNKNOWN,
    FORM,
    IFHD,
}

@(private="file")
IFF_Form_Type :: enum {
    UNKNOWN,
    IFZS,
}

@(private="file")
IFF_Chunk :: struct {
    type: IFF_Type,
    data: []u8,
}

@(private="file")
IFF_Form :: struct {
    type: IFF_Form_Type,
    data: []u8,
}

quetzal_read_chunk :: proc(data: []u8) -> (chunk: IFF_Chunk) {
    assert(len(data) >= 8)
    if slice.equal(data[0:][:4], transmute([]u8)string("FORM")) do chunk.type = .FORM
    if slice.equal(data[0:][:4], transmute([]u8)string("IFhd")) do chunk.type = .IFHD
    else do unreachable("Invalid chunk type: %s", data[0:][:4])
    length, ok := endian.get_u32(data[4:][:4], .Big)
    assert(len(data) >= int(length) + 8)
    chunk.data = data[8:][:length]
    return chunk
}

quetzal_read_form :: proc(data: []u8) -> (form: IFF_Form) {
    assert(len(data) >= 12)
    assert(slice.equal(data[0:][:4], transmute([]u8)string("FORM")))

    length, ok := endian.get_u32(data[4:][:4], .Big)
    assert(len(data) >= int(length) + 8)

    if slice.equal(data[8:][:4], transmute([]u8)string("IFZS")) do form.type = .IFZS
    else do unreachable()

    form.data = data[12:][:length - 4]
    return form
}

quetzal_restore :: proc(machine: ^Machine) -> bool {
    base := filepath.base(machine.romfile)
    stem := filepath.short_stem(base)
    file := fmt.tprintf("%s.qzl", stem)

    if !os.exists(file) {
        unimplemented()
    }

    data, ok := os.read_entire_file(file)
    if !ok do return false

    form := quetzal_read_form(data)
    assert(form.type == .IFZS)
    header := quetzal_read_chunk(form.data)
    debug("%v", form)
    debug("%v", header)

    if false do return false
    unimplemented()
}
