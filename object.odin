package odinz

import "core:fmt"

@(private="file")
object_addr :: proc(machine: ^Machine, object_number: u16) -> u16 {
    assert(object_number != 0)
    header := machine_header(machine)
    if header.version <= 3 do assert(object_number < 256)
    objects_table := u16(header.objects)
    if header.version <= 3 do return objects_table + 2 * 31 + 9 * (object_number - 1)
    else do return objects_table + 2 * 63 + 14 * (object_number - 1)
}
@(private="file")
object_properties :: proc(machine: ^Machine, object_number: u16) -> u16 {
    header := machine_header(machine)
    addr := object_addr(machine, object_number)
    if header.version <= 3 do return machine_read_word(machine, u32(addr) + 7)
    else do return machine_read_word(machine, u32(addr) + 12)
}

object_dump :: proc(machine: ^Machine, object_number: u16) {
    properties := object_properties(machine, object_number)
    length := machine_read_byte(machine, u32(properties))

    if length == 0 do unreach("Dumping object %d failed. String of length 0", object_number, machine=machine);
    zstring_dump(machine, properties + 1, length)
}

object_test_attr :: proc(machine: ^Machine, object_number: u16, attribute: u16) -> bool {
    header := machine_header(machine)
    addr := object_addr(machine, object_number)
    if header.version <= 3 do assert(attribute <= 32)
    else do assert(attribute <= 48)

    mask := u8(1 << (8 - (attribute % 8)))
    return machine_read_byte(machine, u32(addr + (attribute / 8))) & mask == mask
}

object_put_property :: proc(machine: ^Machine, object_number: u16, property_number: u16, value: u16) {
    header := machine_header(machine)
    properties := object_properties(machine, object_number)
    text_length := machine_read_byte(machine, u32(properties))
    property := properties + u16(text_length) * 2 + 1;
    if header.version <= 3 {
        for {
            size := machine_read_byte(machine, u32(property))
            if size == 0 do break
            length := size >> 5 + 1
            prop_num := size & 0b11111
            if u16(prop_num) < property_number {
                unreach("Writing value to object %d property %d failed: Could not find property before finding property %d",
                        object_number, property_number, prop_num, machine=machine)
            }
            if u16(prop_num) == property_number {
                switch length {
                    case 1: machine_write_byte(machine, u32(property) + 1, u8(value))
                    case 2: machine_write_word(machine, u32(property) + 1, value)
                    case:
                        unreach("Writing value to object %d property %d failed: Expected length of 1 or 2. Got %d",
                                object_number, property_number, length, machine=machine)
                }
            }
            property += u16(length) + 1
        }
    } else {
        unimplemented("V4+ property tables")
    }
}
