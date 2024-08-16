package odinz

import "core:encoding/endian"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"

@(private="file")
IFF_Chunk_Type :: enum {
    UNKNOWN,
    FORM,
    IFHD,
    CMEM,
    UMEM,
    STKS,
}

@(private="file")
IFF_Form_Type :: enum {
    UNKNOWN,
    IFZS,
}

@(private="file")
IFF_Chunk :: struct {
    type: IFF_Chunk_Type,
    data: []u8 `fmt:"02x"`,
}

@(private="file")
IFF_Form :: struct {
    type: IFF_Form_Type,
    offset: int,
    data: []u8 `fmt:"02x"`,
}

quetzal_read_chunk :: proc(data: []u8) -> (chunk: IFF_Chunk, ok: bool) {
    // https://en.wikipedia.org/wiki/Interchange_File_Format
    // http://www.martinreddy.net/gfx/2d/IFF.txt
    if len(data) < 8 do return chunk, false
    #assert(len(IFF_Chunk_Type) == 6, "Unexpected number of chunk types")
    if slice.equal(data[:4], transmute([]u8)string("FORM")) do chunk.type = .FORM
    else if slice.equal(data[:4], transmute([]u8)string("IFhd")) do chunk.type = .IFHD
    else if slice.equal(data[:4], transmute([]u8)string("CMem")) do chunk.type = .CMEM
    else if slice.equal(data[:4], transmute([]u8)string("UMem")) do chunk.type = .UMEM
    else if slice.equal(data[:4], transmute([]u8)string("Stks")) do chunk.type = .STKS
    else {
        debug("Invalid chunk type: %s (%v)", data[:4], data[:4])
        return chunk, false
    }
    length, len_ok := endian.get_u32(data[4:][:4], .Big)
    if !len_ok do return chunk, false
    if len(data) < int(length) + 8 do return chunk, false
    chunk.data = data[8:][:length]
    return chunk, true
}

quetzal_read_form :: proc(data: []u8) -> (ret: IFF_Form, ok: bool) {
    // https://inform-fiction.org/zmachine/standards/quetzal/index.html#eight
    form, form_ok := quetzal_read_chunk(data)
    if !form_ok do return ret, false
    if form.type != .FORM do return ret, false
    if len(form.data) < 4 do return ret, false

    if slice.equal(form.data[:4], transmute([]u8)string("IFZS")) do ret.type = .IFZS
    else {
        debug("Invalid form type: %s", form.data[:4])
        return ret, false
    }

    ret.data = form.data[4:]
    return ret, true
}

quetzal_next_chunk :: proc(form: ^IFF_Form) -> (chunk: IFF_Chunk, ok: bool) {
    if form.offset >= len(form.data) do return chunk, false
    chunk, ok = quetzal_read_chunk(form.data[form.offset:])
    if !ok do return chunk, false
    form.offset += len(chunk.data) + 8
    if len(chunk.data) % 2 != 0 do form.offset += 1
    return chunk, true
}

quetzal_check_header :: proc(machine: ^Machine, chunk: IFF_Chunk) -> bool {
    if chunk.type != .IFHD do return false
    if len(chunk.data) < 13 do return false
    // FIXME Should re-read the romfile, just in case it has changed
    //       Will need to read the romfile eventually to do CMem and UMem
    //       Although, these fields are read-only
    // https://inform-fiction.org/zmachine/standards/quetzal/index.html#five
    header := machine_header(machine)
    release := endian.get_u16(chunk.data[:2], .Big) or_return
    if release != u16(header.release) {
        debug("Invalid release %x, expected %x", release, header.release)
        return false
    }
    if !slice.equal(chunk.data[2:][:6], header.serial[:]) {
        debug("Invalid serial %s, expected %s", chunk.data[2:][:6], header.serial)
        return false
    }
    checksum := endian.get_u16(chunk.data[8:][:2], .Big) or_return
    if checksum != u16(header.checksum) {
        debug("Invalid checksum %x, expected %x", checksum, header.checksum)
        return false
    }
    return true
}

quetzal_read_header :: proc(form: ^IFF_Form) -> (chunk: IFF_Chunk, ok: bool) {
    for chunk, ok = quetzal_next_chunk(form);
            ok;
            chunk, ok = quetzal_next_chunk(form) {

        switch chunk.type {
            case .IFHD: return chunk, ok

            // Should not encounter these before header
            // FIXME Could we?
            case .CMEM: unreachable()
            case .UMEM: unreachable()
            case .STKS: unreachable()

            // Don't support recursive forms
            case .FORM: unreachable()

            case .UNKNOWN: unreachable()
            case: unreachable()
        }
    }
    return chunk, false
}

quetzal_process_stks_frame :: proc(data: []u8, length: ^int) -> (frame: Frame, ok: bool) {
    if len(data) < 8 do return frame, false
    data := data
    pc := u32(0)
    for b in data[:3] do pc = (pc << 8) | u32(b)
    frame.pc = pc
    flags := data[3]
    if !bit(flags, 4) do frame.has_store = true
    v := flags & 0xf
    frame.store = data[4]
    args := data[5]
    for i in 0..=6 {
        frame.arg_count += args % 2
        args >>= 1
    }
    n := endian.get_u16(data[6:][:2], .Big) or_return
    data = data[8:]
    if len(data) < 2 * int(u16(v) + n) do return frame, false

    frame.variables = make([]u16, v)
    for i := 0; i < int(v); i += 1 {
        frame.variables[i] = endian.get_u16(data[(2 * i):][:2], .Big) or_return
    }
    data = data[(2 * v):]

    for i := 0; i < int(n); i += 1 {
        value := endian.get_u16(data[(2 * i):][:2], .Big) or_return
        append(&frame.stack, value)
    }
    length^ = 8 + 2 * int(n + u16(v))
    return frame, true
}

quetzal_process_stks_chunk :: proc(machine: ^Machine, chunk: IFF_Chunk) -> (frames: [dynamic]Frame, ok: bool) {
    if chunk.type != .STKS do return nil, false
    header := machine_header(machine)
    if header.version == 6 do unimplemented("Initial frame in V6")

    data := chunk.data
    length: int
    for {
        frame, ok := quetzal_process_stks_frame(data, &length)
        if !ok do break
        if len(frames) > 0 do frames[len(frames)-1].pc = frame.pc
        append(&frames, frame)
        data = data[length:]
    }
    if len(data) > 0 do return nil, false
    return frames, true
}

quetzal_process_cmem_chunk :: proc(machine: ^Machine, chunk: IFF_Chunk) -> (data: []u8, ok: bool) {
    if chunk.type != .CMEM do return nil, false
    memory := os.read_entire_file(machine.romfile) or_return
    mem_idx := 0
    for data_idx := 0; data_idx < len(chunk.data); data_idx += 1 {
        if chunk.data[data_idx] == 0 {
            if data_idx + 1 >= len(chunk.data) do return nil, false
            length := int(chunk.data[data_idx + 1])
            data_idx += 1
            mem_idx += length + 1
        } else {
            memory[mem_idx] ~= chunk.data[data_idx]
            mem_idx += 1
        }
    }
    return memory, true
}

quetzal_filepath :: proc(machine: ^Machine, writable: bool = false) -> string {
    base := filepath.base(machine.romfile)
    stem := filepath.short_stem(base)
    file := fmt.tprintf("%s.qzl", stem)

    if writable {
        if os.exists(file) {
            unimplemented("Overwrite")
        }
    } else {
        if !os.exists(file) {
            unimplemented("Choose another file")
        }
    }
    return file
}

quetzal_restore :: proc(machine: ^Machine) -> bool {
    file := quetzal_filepath(machine)
    debug("RESTORE: Starting restore process for %s", file)

    // https://zspec.jaredreisinger.com/06-game-state#6_1_2
    header := machine_header(machine)
    flags2 := header.flags2

    // FIXME We could just get a file handle and use seek and read for better efficiency
    data := os.read_entire_file(file) or_return
    debug("RESTORE: Read file contents")

    form := quetzal_read_form(data) or_return
    debug("RESTORE: Found IFF form of type %s", form.type)
    if form.type != .IFZS do return false

    chunk := quetzal_read_header(&form) or_return
    debug("RESTORE: Found chunk type %s", chunk.type)
    if chunk.type != .IFHD do return false
    quetzal_check_header(machine, chunk) or_return
    debug("RESTORE: Header is valid")

    pc := u32(0)
    for b in chunk.data[10:][:3] do pc = (pc << 8) | u32(b)

    memory: []u8
    frames: [dynamic]Frame
    ok: bool
    for chunk, ok = quetzal_next_chunk(&form);
            ok;
            chunk, ok = quetzal_next_chunk(&form) {
        if !ok do return false
        switch chunk.type {
            case .STKS: frames = quetzal_process_stks_chunk(machine, chunk) or_return
            case .CMEM: memory = quetzal_process_cmem_chunk(machine, chunk) or_return
            case .UMEM: memory = chunk.data

            case .UNKNOWN: unreachable()
            case .IFHD: unreachable()
            case .FORM: unreachable()
            case: unreachable()
        }
        debug("RESTORE: Processed %s", chunk.type)
    }

    if len(memory) == 0 || len(machine.frames) == 0 do return false
    debug("RESTORE: Restoring Z-Machine")

    // Update current frame pc
    if header.version <= 3 {
        // V3 pc points to the branch byte(s) of the SAVE instruction
        // https://zspec.jaredreisinger.com/04-instructions#4_7
        if bit(memory[pc], 6) do frames[len(frames) - 1].pc = pc + 1
        else do frames[len(frames) - 1].pc = pc + 2
        // FIXME actually branch?
    } else {
        // V4+ pc points to the store byte of the SAVE instruction
        // https://zspec.jaredreisinger.com/04-instructions#4_6
        frames[len(frames) - 1].pc = pc + 1
        // FIXME actually store?
    }

    delete(machine.memory)
    machine.memory = memory

    for &frame in machine.frames do delete_frame(&frame)
    delete(machine.frames)
    machine.frames = frames

    // https://zspec.jaredreisinger.com/06-game-state#6_1_2
    header = machine_header(machine)
    header.flags2 = flags2

    debug("RESTORE: Finished")
    return true
}

quetzal_form_write_data :: proc(fd: os.Handle, data: []u8, length: ^u32) {
    os.write(fd, data)
    length^ += u32(len(data))
}

quetzal_form_write_u32 :: proc(fd: os.Handle, value: u32, length: ^u32) {
    data: [4]u8
    endian.put_u32(data[:], .Big, value)
    quetzal_form_write_data(fd, data[:], length)
}

quetzal_form_write_u16 :: proc(fd: os.Handle, value: u16, length: ^u32) {
    data: [2]u8
    endian.put_u16(data[:], .Big, value)
    quetzal_form_write_data(fd, data[:], length)
}

quetzal_form_write_string :: proc(fd: os.Handle, value: string, length: ^u32) {
    quetzal_form_write_data(fd, transmute([]u8)value, length)
}

quetzal_form_write :: proc{
    quetzal_form_write_u32,
    quetzal_form_write_u16,
    quetzal_form_write_string,
    quetzal_form_write_data,
}

quetzal_write_ifhd :: proc(machine: ^Machine, fd: os.Handle, length: ^u32) -> bool {
    // https://inform-fiction.org/zmachine/standards/quetzal/index.html#five
    header := machine_header(machine)
    if len(machine.frames) == 0 do return false
    current_frame := machine.frames[len(machine.frames) - 1]

    quetzal_form_write(fd, "IFhd", length)
    quetzal_form_write(fd, u32(13), length)
    quetzal_form_write(fd, u16(header.release), length)
    quetzal_form_write(fd, header.serial[:], length)
    quetzal_form_write(fd, u16(header.checksum), length)
    pc := current_frame.pc
    if header.version <= 3 {
        // V3 pc points to the branch byte(s) of the SAVE instruction
        // https://zspec.jaredreisinger.com/04-instructions#4_7
        if bit(machine.memory[pc], 6) do pc -= 1
        else do pc -= 2
    } else {
        // V4+ pc points to the store byte of the SAVE instruction
        // https://zspec.jaredreisinger.com/04-instructions#4_6
        pc -= pc + 1
    }
    // PC is only 3 bytes, with 0 byte pad
    pc_data: [4]u8
    endian.put_u32(pc_data[:], .Big, pc)
    quetzal_form_write(fd, pc_data[1:], length)
    quetzal_form_write(fd, []u8{0}, length)
    return true
}

quetzal_write_cmem :: proc(machine: ^Machine, fd: os.Handle, length: ^u32) -> bool {
    if true do unimplemented()
    return true
}

quetzal_write_stks :: proc(machine: ^Machine, fd: os.Handle, length: ^u32) -> bool {
    stks_length := u32(0)
    defer length^ += 8 + stks_length
    quetzal_form_write(fd, "Stks", length)
    stks_offset, err := os.seek(fd, 0, os.SEEK_CUR)
    if err != os.ERROR_NONE do return false
    defer {
        end, err := os.seek(fd, stks_offset, os.SEEK_SET)
        if err == os.ERROR_NONE do quetzal_form_write(fd, stks_length, length)
        os.seek(fd, end, os.SEEK_SET)
    }
    quetzal_form_write(fd, "THEntHE", &stks_length)

    if true do unimplemented()
    return true
}

quetzal_save :: proc(machine: ^Machine) -> bool {
    header := machine_header(machine)
    file := quetzal_filepath(machine, true)

    fd, err := os.open(file, os.O_WRONLY | os.O_CREATE)
    if err != os.ERROR_NONE do return false
    defer os.close(fd)

    form_length := u32(0)
    os.write(fd, transmute([]u8)string("FORM"))
    _, err = os.seek(fd, 4, os.SEEK_CUR)
    if err != os.ERROR_NONE do return false
    defer {
        data: [4]u8
        os.seek(fd, 4, os.SEEK_SET) // Just after "FORM"
        endian.put_u32(data[:], .Big, form_length)
        os.write(fd, data[:])
    }
    quetzal_form_write(fd, "IFZS", &form_length)

    quetzal_write_ifhd(machine, fd, &form_length)
    quetzal_write_cmem(machine, fd, &form_length)
    quetzal_write_stks(machine, fd, &form_length)

    if true do unimplemented()
    return true
}
