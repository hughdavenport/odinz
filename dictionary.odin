package odinz

import "core:fmt"

@(private="file")
dictionary_search_chop :: proc(machine: ^Machine, entries: u32, length: u32, search: []u16, low: u32, high: u32) -> u32 {
    if low == high do return 0

    mid := low + (high - low) / 2
    for i := 0; i < len(search); i += 1 {
        word := machine_read_word(machine, entries + length * mid + u32(i) * 2)
        if search[i] < word {
            return dictionary_search_chop(machine, entries, length, search, low, mid)
        } else if search[i] > word {
            return dictionary_search_chop(machine, entries, length, search, mid + 1, high)
        }
    }

    return mid + 1
}

dictionary_search :: proc(machine: ^Machine, search: []u16) -> u32 {
    header := machine_header(machine)
    dictionary := u32(header.dictionary)
    n := u32(machine_read_byte(machine, dictionary))
    length := u32(machine_read_byte(machine, dictionary + n + 1))
    count := u32(machine_read_word(machine, dictionary + n + 2))
    assert(int(count) > len(search) * 2)
    entries := dictionary + n + 4

    index := dictionary_search_chop(machine, entries, length, search, 0, count)
    if index == 0 do return 0
    return entries + length * index
}
