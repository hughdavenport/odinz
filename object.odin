package odinz

object_dump :: proc(machine: ^Machine, object_number: u16) {
    assert(object_number != 0)
    header := machine_header(machine)
    if header.version <= 3 do assert(object_number < 256)
    objects_table := u16(header.objects)
    offset: u32
    if header.version <= 3 do offset = 2 * 31 + 9 * (u32(object_number) - 1) + 7
    else do offset = 2 * 63 + 14 * (u32(object_number) - 1) + 12
    properties := machine_read_word(machine, u32(objects_table) + offset)
    length := machine_read_byte(machine, u32(properties))

    if length == 0 {
        machine_dump(machine)
        fmt.eprintfln("Dumping object %d failed. String of length 0", object_number);
        unreachable()
    }
    zstring_dump(machine, properties + 1, length)
}

object_put_property :: proc(machine: ^Machine, object_number: u16, property_number: u16, value: u16) {
    unimplemented()
}
