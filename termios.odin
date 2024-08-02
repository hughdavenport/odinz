package odinz

// Adapted from https://github.com/krixano/ncure, BSD licence
// Copyright 2021 Christian Lee Seibold, 2024 Hugh Davenport
//
// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import "core:c"
import "core:fmt"
import "core:os"
foreign import libc "system:c"

cc_t :: distinct c.uchar
speed_t :: distinct c.uint
tcflag_t :: distinct c.uint
NCCS :: 32
termios :: struct {
	c_iflag: tcflag_t,  // Input modes
	c_oflag: tcflag_t,  // Output modes
	c_cflag: tcflag_t,  // Control modes
	c_lflag: tcflag_t,  // Local modes
	c_line: cc_t,
	c_cc: [NCCS]cc_t,    // Special characters
	c_ispeed: speed_t,  // Input speed
	c_ospeed: speed_t,   // Output speed
}

VTIME :: 5
VMIN :: 6

ICANON: tcflag_t : 0000002
ECHO: tcflag_t : 0000010

TCSANOW :: 0

foreign libc {
    @(link_name="tcgetattr") _unix_tcgetattr :: proc(fd: os.Handle, termios_p: ^termios) -> c.int ---;
    @(link_name="tcsetattr") _unix_tcsetattr :: proc(fd: os.Handle, optional_actions: c.int, termios_p: ^termios) -> c.int ---;
    @(link_name="ioctl") _unix_ioctl :: proc(fd: os.Handle, request: c.ulong, argp: rawptr) -> c.int ---;
}

tcgetattr :: proc(fd: os.Handle, termios_p: ^termios) -> os.Errno {
	result := _unix_tcgetattr(fd, termios_p)
	if result == -1 {
		return os.Errno(os.get_last_error())
	}

	return os.ERROR_NONE
}

tcsetattr :: proc(fd: os.Handle, optional_actions: int, termios_p: ^termios) -> os.Errno {
	result := _unix_tcsetattr(fd, c.int(optional_actions), termios_p)
	if result == -1 {
		return os.Errno(os.get_last_error())
	}

	return os.ERROR_NONE
}

is_tty :: proc() -> bool {
	term: termios
	if get_error := tcgetattr(os.stdin, &term); get_error != os.ERROR_NONE {
        return false
	}
    return true
}

getch :: proc() -> u8 {
    data: [1]byte
	prev: termios
	if get_error := tcgetattr(os.stdin, &prev); get_error != os.ERROR_NONE {
		unreachable("Error getting terminal info: %s\n", get_error)
	}

    new := prev

	new.c_lflag &= ~ICANON
	new.c_lflag &= ~ECHO
	new.c_cc[VMIN] = 1
	new.c_cc[VTIME] = 0

	if set_error := tcsetattr(os.stdin, TCSANOW, &new); set_error != os.ERROR_NONE {
		unreachable("Error setting terminal info: %s\n", set_error)
	}

	if bytes_read, _ := os.read(os.stdin, data[:]); bytes_read < 0 {
		unreachable("Error reading Input")
	}

	if set_error := tcsetattr(os.stdin, TCSANOW, &prev); set_error != os.ERROR_NONE {
		unreachable("Error setting terminal info: %s\n", set_error)
	}

	return data[0]
}

get_cursor :: proc() -> (x: uint, y: uint) {
    assert(is_tty())
    fmt.print("\e[6n")
    assert(getch() == '\e')
    assert(getch() == '[')
    for b := getch(); b != ';'; b = getch() {
        x *= 10
        x += uint(b - '0')
    }
    if x == 0 do x = 1
    for b := getch(); b != 'R'; b = getch() {
        y *= 10
        y += uint(b - '0')
    }
    if y == 0 do y = 1
    return x, y
}

set_cursor :: proc(x: uint, y: uint) {
    assert(is_tty())
    fmt.printf("\e[%d;%dH", x, y)
}

clear_line :: proc() {
    assert(is_tty())
    fmt.print("\e[2K")
}

clear_screen :: proc() {
    assert(is_tty())
    fmt.print("\e[2J")
}
