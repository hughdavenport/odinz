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

object_has_name :: proc(machine: ^Machine, object_number: u16) -> bool {
    properties := object_properties(machine, object_number)
    length := machine_read_byte(machine, u32(properties))
    return length != 0
}

object_dump :: proc(machine: ^Machine, object_number: u16) {
    if object_number == 0 do return
    properties := object_properties(machine, object_number)
    length := machine_read_byte(machine, u32(properties))

    if length == 0 do return
    zstring_dump(machine, u32(properties) + 1, length)
}

object_clear_attr :: proc(machine: ^Machine, object_number: u16, attribute: u16) {
    header := machine_header(machine)
    addr := object_addr(machine, object_number)
    if header.version <= 3 do assert(attribute <= 32)
    else do assert(attribute <= 48)

    attribute_addr := u32(addr + (attribute / 8))
    mask := u8(1 << (7 - (attribute % 8)))
    orig := machine_read_byte(machine, attribute_addr)
    machine_write_byte(machine, attribute_addr, orig & ~mask)
}

object_set_attr :: proc(machine: ^Machine, object_number: u16, attribute: u16) {
    header := machine_header(machine)
    addr := object_addr(machine, object_number)
    if header.version <= 3 do assert(attribute <= 32)
    else do assert(attribute <= 48)

    attribute_addr := u32(addr + (attribute / 8))
    mask := u8(1 << (7 - (attribute % 8)))
    orig := machine_read_byte(machine, attribute_addr)
    machine_write_byte(machine, attribute_addr, orig | mask)
}

object_test_attr :: proc(machine: ^Machine, object_number: u16, attribute: u16) -> bool {
    header := machine_header(machine)
    addr := object_addr(machine, object_number)
    if header.version <= 3 do assert(attribute <= 32)
    else do assert(attribute <= 48)

    mask := u8(1 << (7 - (attribute % 8)))
    return machine_read_byte(machine, u32(addr + (attribute / 8))) & mask == mask
}

object_get_property_addr :: proc(machine: ^Machine, object_number: u16, property_number: u16) -> u16 {
    header := machine_header(machine)
    properties := object_properties(machine, object_number)
    text_length := machine_read_byte(machine, u32(properties))
    property := properties + u16(text_length) * 2 + 1;
    if header.version <= 3 {
        assert(property_number <= 31)
        for {
            size := machine_read_byte(machine, u32(property))
            length := size >> 5 + 1
            prop_num := size & 0b11111
            if u16(prop_num) < property_number do return 0
            if u16(prop_num) == property_number do return property + 1
            property += u16(length) + 1
        }
        unreachable()
    } else {
        unimplemented("V4+ property tables")
    }
}

object_get_property_len :: proc(machine: ^Machine, property_address: u16) -> u16 {
    header := machine_header(machine)
    if header.version <= 3 {
        if property_address == 0 do return 0
        size := machine_read_byte(machine, u32(property_address) - 1)
        length := size >> 5 + 1
        return u16(length)
    } else {
        unimplemented("V4+ property tables")
    }
}

object_get_property :: proc(machine: ^Machine, object_number: u16, property_number: u16) -> u16 {
    header := machine_header(machine)
    addr := object_get_property_addr(machine, object_number, property_number)
    if addr == 0 {
        if header.version <= 3 do return machine_read_word(machine, u32(2 * (property_number - 1) + u16(header.objects)))
        else do unimplemented("V4+ property tables")
    }
    length := object_get_property_len(machine, addr)
    switch length {
        case 1: return u16(machine_read_byte(machine, u32(addr)))
        case 2: return machine_read_word(machine, u32(addr))
        case:
            unreach("Reading value of object %d property %d failed: Expected length of 1 or 2. Got %d",
                    object_number, property_number, length, machine=machine)
    }
    unreachable()
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

object_child :: proc(machine: ^Machine, object_number: u16) -> u16 {
    assert(object_number != 0)
    header := machine_header(machine)
    obj := object_addr(machine, object_number)
    if header.version <= 3 {
        assert(object_number <= 255)
        return u16(machine_read_byte(machine, u32(obj + 6)))
    } else {
        return machine_read_word(machine, u32(obj + 10))
    }
    unreach()
}

object_sibling :: proc(machine: ^Machine, object_number: u16) -> u16 {
    assert(object_number != 0)
    header := machine_header(machine)
    obj := object_addr(machine, object_number)
    if header.version <= 3 {
        assert(object_number <= 255)
        return u16(machine_read_byte(machine, u32(obj + 5)))
    } else {
        return machine_read_word(machine, u32(obj + 8))
    }
    unreach()
}

object_parent :: proc(machine: ^Machine, object_number: u16) -> u16 {
    assert(object_number != 0)
    header := machine_header(machine)
    obj := object_addr(machine, object_number)
    if header.version <= 3 {
        assert(object_number <= 255)
        return u16(machine_read_byte(machine, u32(obj + 4)))
    } else {
        return machine_read_word(machine, u32(obj + 6))
    }
    unreach()
}

object_insert_object :: proc(machine: ^Machine, object_number: u16, destination_number: u16) {
    assert(object_number != 0)
    assert(destination_number != 0)
    header := machine_header(machine)
    obj := object_addr(machine, object_number)
    dest := object_addr(machine, destination_number)
    if header.version <= 3 {
        assert(object_number <= 255)
        assert(destination_number <= 255)
        parent: u16 = 4
        sibling: u16 = 5
        child: u16 = 6
        // move obj to be dest's child

        //  update obj's sibling's parent to be obj's parent
        obj_sibling_number := machine_read_byte(machine, u32(obj + sibling))
        if obj_sibling_number != 0 {
            obj_parent_number := machine_read_byte(machine, u32(obj + parent))
            obj_sibling := object_addr(machine, u16(obj_sibling_number))
            machine_write_byte(machine, u32(obj_sibling + parent), obj_parent_number)
        }

        //  update obj's sibling to be dest's child
        dest_child_number := machine_read_byte(machine, u32(dest + child))
        machine_write_byte(machine, u32(obj + sibling), dest_child_number)

        //  update dest's child to be obj
        machine_write_byte(machine, u32(dest + child), u8(object_number))

        //  update obj's parent to be dest
        machine_write_byte(machine, u32(obj + parent), u8(destination_number))
    } else {
        parent: u16 = 6
        sibling: u16 = 8
        child: u16 = 10
        // move obj to be dest's child

        //  update obj's sibling's parent to be obj's parent
        obj_sibling_number := machine_read_word(machine, u32(obj + sibling))
        if obj_sibling_number != 0 {
            obj_parent_number := machine_read_word(machine, u32(obj + parent))
            obj_sibling := object_addr(machine, obj_sibling_number)
            machine_write_word(machine, u32(obj_sibling + parent), obj_parent_number)
        }

        //  update obj's sibling to be dest's child
        dest_child_number := machine_read_word(machine, u32(dest + child))
        machine_write_word(machine, u32(obj + sibling), dest_child_number)

        //  update dest's child to be obj
        machine_write_word(machine, u32(dest + child), object_number)

        //  update obj's parent to be dest
        machine_write_word(machine, u32(obj + parent), destination_number)
    }
}
