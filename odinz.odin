package odinz

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:strconv"
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
    fmt.eprintfln("Usage: %s [OPTIONS] [--] romfile [OPTIONS]", progname)
    fmt.eprintln("OPTIONS:")
    fmt.eprintln("    -t|--trace[=all]               Enable all traces listed below")
    fmt.eprintln("    -tf|--trace=frame              Enable tracing of frame before each instruction")
    fmt.eprintln("    -tb|--trace=backtrace          Enable tracing of machine backtrace before each instruction")
    fmt.eprintln("    -ti|--trace=instruction        Enable tracing of each instruction")
    fmt.eprintln("    -tr|--trace=read               Enable tracing of all reads")
    fmt.eprintln("    -tw|--trace=write              Enable tracing of all writes")
    fmt.eprintln("    -sl|--status-line              Enable status line (V1-3)")
    fmt.eprintln("    -ss|--screen-split             Enable screen splitting (V1-3)")
    fmt.eprintln("    -as|--alternate-screen         Enable alternate screen")
    fmt.eprintln("    -s[=num]|--seed[=num] [num]    Set random number initial seed")
    os.exit(int(EXIT_CODE.usage))
}

@(private="file")
error :: proc(message: string, code: EXIT_CODE = EXIT_CODE.software) -> ! {
    fmt.eprintln("ERROR:", message)
    os.exit(int(code))
}

debug :: proc(format: string = "", args: ..any, loc := #caller_location) {
    loc_format := "\n%s(%d:%d) %s: DEBUG "
    fmt.eprintf(loc_format, loc.file_path, loc.line, loc.column, loc.procedure)
    fmt.eprintfln(format, ..args)
}

unreachable :: proc(format: string = "", args: ..any, loc := #caller_location) -> ! {
    loc_format := "\n%s(%d:%d) %s: UNREACHABLE"
    fmt.eprintfln(loc_format, loc.file_path, loc.line, loc.column, loc.procedure)
    fmt.eprintfln(format, ..args)
    os.exit(int(EXIT_CODE.software))
}

unimplemented :: proc(format: string = "", args: ..any, loc := #caller_location) -> ! {
    loc_format := "\n%s(%d:%d) %s: UNIMPLEMENTED"
    fmt.eprintfln(loc_format, loc.file_path, loc.line, loc.column, loc.procedure)
    fmt.eprintfln(format, ..args)
    os.exit(int(EXIT_CODE.software))
}

check_args :: proc(progname: string, args: ^[]string) -> (config: Config) {
    for len(args^) > 0 && strings.has_prefix(args^[0], "-") {
        if args^[0] == "--" {
            args^ = args^[1:]
            break
        }
        if strings.has_prefix(args^[0], "--seed") || strings.has_prefix(args^[0], "-s") {
            num: u64
            ok: bool
            if _, _, num_s := strings.partition(args^[0], "="); num_s != "" {
                num, ok = strconv.parse_u64(num_s)
            } else {
                assert(len(args^) > 1)
                num, ok = strconv.parse_u64(args^[1])
                args^ = args^[2:]
            }
            assert(ok)
            fmt.printfln("Setting random seed to %d", num)
            rand.reset(num)
            continue
        }
        switch args^[0] {
            case "-t", "--trace", "--trace=all": config.trace = ~{}
            case "-tb", "--trace=backtrace": config.trace |= {.backtrace}
            case "-tf", "--trace=frame": config.trace |= {.frame}
            case "-ti", "--trace=instruction": config.trace |= {.instruction}
            case "-tr", "--trace=read": config.trace |= {.read}
            case "-tw", "--trace=write": config.trace |= {.write}
            case "-sl", "--status-line": config.status = true
            case "-ss", "--screen-split": config.screen_split = true
            case "-as", "--alternative-screen": config.alternate_screen = true
            case: usage_and_exit(progname)
        }
        args^ = args^[1:]
    }
    return config
}

main :: proc() {
    config: Config

    args := os.args
    progname := args[0]
    args = args[1:]

    config = check_args(progname, &args)

    if len(args) == 0 do usage_and_exit(progname)
    romfile := args[0]
    args = args[1:]
    if !os.exists(romfile) do error(fmt.tprintf("File '%s' does not exist", romfile), EXIT_CODE.no_input)

    config = check_args(progname, &args)

    data, ok := os.read_entire_file(romfile)
    if !ok do error(fmt.tprintf("Could not read '%s'", romfile), EXIT_CODE.io_error)
    defer delete(data)
    machine := &Machine{romfile=romfile, memory=data, config=config}
    initialise_machine(machine)
    execute(machine)
}
