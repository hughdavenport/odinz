package odinz

import "core:fmt"
import "core:os"
import "core:strings"

@(private="file")
EXIT_CODE :: enum int {
    usage      = 64,
    data_error = 65,
    no_input   = 66,
    software   = 70,
    io_error   = 74,
}

@(private="file")
usage_and_exit :: proc(progname: string) -> ! {
    fmt.eprintfln("Usage: %s [OPTIONS] [--] romfile", progname)
    fmt.eprintln("OPTIONS:")
    fmt.eprintln("    -t|--trace    Enable tracing of instructions")
    os.exit(int(EXIT_CODE.usage))
}

@(private="file")
error :: proc(message: string, code: EXIT_CODE = EXIT_CODE.software) -> ! {
    fmt.eprintln("ERROR:", message)
    os.exit(int(code))
}

unreach :: proc(format: string = "", args: ..any, machine: ^Machine = nil, loc := #caller_location) -> ! {
    // if machine != nil do machine_dump(machine)
    loc_format := "\n%s(%d:%d) %s: UNREACHABLE"
    fmt.eprintfln(loc_format, loc.file_path, loc.line, loc.column, loc.procedure)
    fmt.eprintfln(format, ..args)
    unreachable()
}

main :: proc() {
    trace: bool

    args := os.args
    progname := args[0]
    args = args[1:]

    for len(args) > 0 && strings.has_prefix(args[0], "-") {
        if args[0] == "--" {
            args = args[1:]
            break
        }
        switch args[0] {
            case "-t", "--trace": trace = true
            case: usage_and_exit(progname)
        }
        args = args[1:]
    }

    if len(args) == 0 do usage_and_exit(progname)
    romfile := args[0]
    if !os.exists(romfile) do error(fmt.tprintf("File '%s' does not exist", romfile), EXIT_CODE.no_input)

    data, ok := os.read_entire_file(romfile)
    if !ok do error(fmt.tprintf("Could not read '%s'", romfile), EXIT_CODE.io_error)
    defer delete(data)
    machine := &Machine{romfile=romfile, memory=data, trace=trace}
    initialise_machine(machine)
    execute(machine)
}
