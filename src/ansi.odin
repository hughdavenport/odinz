package odinz

import "core:fmt"

get_cursor :: proc() -> (x: uint, y: uint) {
    assert(is_tty())
    fmt.print("\e[6n")
    assert(getch() == '\e')
    assert(getch() == '[')
    for b := getch(); b != ';'; b = getch() {
        y *= 10
        y += uint(b - '0')
    }
    if y == 0 do y = 1
    for b := getch(); b != 'R'; b = getch() {
        x *= 10
        x += uint(b - '0')
    }
    if x == 0 do x = 1
    return x, y
}

set_cursor :: proc(x: uint, y: uint) {
    assert(is_tty())
    fmt.printf("\e[%d;%dH", y, x)
}

clear_line :: proc() {
    assert(is_tty())
    fmt.print("\e[2K")
}

clear_screen :: proc() {
    assert(is_tty())
    fmt.print("\e[2J")
}

reverse_graphics :: proc() {
    assert(is_tty())
    fmt.print("\e[0;7m")
}

reset_graphics :: proc() {
    assert(is_tty())
    fmt.print("\e[m")
}
