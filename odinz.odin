package odinz

import "core:fmt"
import "core:os"

EXIT_CODE :: enum int {
    usage      = 64,
    data_error = 65,
    no_input   = 66,
    software   = 70,
    io_error   = 74,
}

@(private="file")
usage_and_exit :: proc(progname: string) -> ! {
    fmt.eprintfln("Usage: %s romfile", progname)
    os.exit(int(EXIT_CODE.usage))
}

error :: proc(message: string, code: EXIT_CODE = EXIT_CODE.software) -> ! {
    fmt.eprintln("ERROR:", message)
    os.exit(int(code))
}

main :: proc() {
    progname := os.args[0]
    if len(os.args) != 2 do usage_and_exit(progname)

    romfile := os.args[1]
    if !os.exists(romfile) do error(fmt.tprint("File '%s' does not exist", romfile), EXIT_CODE.no_input)

    data, ok := os.read_entire_file(romfile)
    if !ok do error(fmt.tprint("Could not read '%s'", romfile), EXIT_CODE.io_error)
    defer delete(data)
    machine := &Machine{romfile=romfile, memory=data}

    header_dump(machine)

    initialise_machine(machine)
    execute(machine)
}
