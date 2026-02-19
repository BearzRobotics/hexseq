const std = @import("std");
const Io = std.Io;

const dklib = @import("dklib.zig");

// Constants go here
const version = "0.0.9";
const hex = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };

const RolloverEnum = enum(u8) {
    none,
    delete,
    move,
};

// Runtime configs should be placed here
const Config = struct {
    debug: bool = false,
    log_dir_set: bool = false,
    log_dir: []const u8 = &.{},
    rollover: RolloverEnum = RolloverEnum.none,
    rollover_path_provided: bool = false,
    rollover_target: []const u8 = &.{},
    rollover_need: bool = false,
    version: bool = false,
    preserve_timestamps: bool = true,
};

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);

    const cfg = try parse_args(args, stdout);

    var old_logs = try get_logs(io, arena, cfg, stdout);
    defer {
        for (old_logs.items) |f| {
            arena.free(f);
        }
        old_logs.deinit(arena);
    }

    var current_logs = try find_current_log(arena, old_logs);
    defer current_logs.deinit(arena);

    try stdout.flush(); // Don't forget to flush!
}

fn parse_args(args: []const [:0]const u8, stdout: *Io.Writer) !Config {
    // lets create our Config Struct
    var cfg = Config{};

    var i: usize = 1; // skip program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) {
                try help(stdout);
            } else if (std.mem.eql(u8, arg, "--debug")) {
                cfg.debug = true;
            } else if (std.mem.eql(u8, arg, "--version")) {
                cfg.version = true;
                std.debug.print("hexsql version: {s}\n", .{version});
                dklib.exit_with(dklib.ExitCode.ok);
            } else if (std.mem.eql(u8, arg, "--logdir")) {
                i += 1;
                if (i >= args.len) {
                    std.debug.print("Failed to pass in <path> for --logdir\n", .{});
                    dklib.exit_with(dklib.ExitCode.usage);
                }

                cfg.log_dir = args[i];
                cfg.log_dir_set = true;
            } else if (std.mem.eql(u8, arg, "--rollover=delete")) {
                cfg.rollover = RolloverEnum.delete;
            } else if (std.mem.eql(u8, arg, "--rollover=move")) {
                cfg.rollover = RolloverEnum.move;

                i += 1;
                if (i >= args.len) {
                    std.debug.print("Failed to pass in <path> for --rollover=move \n", .{});
                    dklib.exit_with(dklib.ExitCode.usage);
                }

                cfg.rollover_target = args[i];
            } else if (std.mem.eql(u8, arg, "--preserve")) {
                cfg.preserve_timestamps = true;
            }
        } else {
            for (arg[1..]) |opt| {
                if (opt == 'd') {
                    cfg.debug = true;
                } else if (opt == 'v') {
                    cfg.version = true;
                } else if (opt == 'p') {
                    cfg.preserve_timestamps = true;
                }
            }
        }
    }

    if (cfg.version == true) {
        std.debug.print("hexsql version: {s}\n", .{version});
        dklib.exit_with(dklib.ExitCode.ok);
    } else if (cfg.log_dir_set == false) {
        std.debug.print("--logdir is required!\n", .{});
        dklib.exit_with(dklib.ExitCode.usage);
    }

    return cfg;
}

fn help(stdout: *Io.Writer) !void {
    try stdout.print("hexseq - hexadecimal log rotator\n\n", .{});
    try stdout.print("Usage: hexseq [options] --logdir <path>\n\n", .{});
    try stdout.print("-h    --help                       Prints help menu\n", .{});
    try stdout.print("-d    --debug                      Enable printing internal debug statements to std::err\n", .{});
    try stdout.print("-v    --version                    Prints the programs version\n", .{});
    try stdout.print("--logdir <path>                    Takes a path to the root of your log dir\n", .{});
    try stdout.print("--rollover=[delete|move] <path>    When you reach .FFF it deletes all old logs and starts fresh at .000\n", .{});
    try stdout.print("                                   Moves all old logs once you reach .FFF to a dir of your choice\n", .{});
    try stdout.print("-p  --preserve                     Perserve timestamps on files\n", .{});

    try stdout.flush(); // Don't forget to flush!
    dklib.exit_with(dklib.ExitCode.ok);
}

fn dec2hex(input: u16) []const u8 {
    var index: usize = 3;
    var value = input;
    var buffer = [_]u8{ '0', '0', '0' };

    while (index > 0) {
        index -= 1;
        buffer[index] = hex[value % 16];
        value = value / 16;
        if (value == 0) break;
    }

    const rt: []const u8 = &buffer;
    return rt;
}

fn count_logs(current_logs: []const u8, old_logs: std.ArrayList([]const u8)) u16 {
    var oLC: u16 = 0;

    for (old_logs.items) |f| {
        if (std.mem.lastIndexOf(u8, f, ".")) |dot_index| {
            const suffix = f[dot_index + 1 ..];
            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and
                std.ascii.isHex(suffix[1]) and
                std.ascii.isHex(suffix[2]) and
                std.mem.eql(u8, current_logs, f[0..dot_index]))
            {
                oLC += 1;
            }
        }
    }

    return oLC;
}

fn get_logs(io: Io, ally: std.mem.Allocator, cfg: Config, stdout: *Io.Writer) !std.ArrayList([]const u8) {
    var logs = std.ArrayList([]const u8).empty;

    try stdout.print("cfg.log_dir: {s}\n", .{cfg.log_dir});

    var dir = try Io.Dir.openDirAbsolute(io, cfg.log_dir, .{ .iterate = true });

    defer dir.close(io);

    var walker = try dir.walk(ally);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        // only grab files
        if (entry.kind == .file) {
            // base + entry.path (relative path.
            const fPath = try std.fs.path.join(ally, &.{ cfg.log_dir, entry.path });

            // Allocate a duplicate string since walk() gives temporary memory
            // we need to use dupe to keep the data alive past the defer of std.fs.cwd().openDir
            const path_copy = try ally.dupe(u8, fPath);

            if (cfg.debug == true) {
                std.debug.print("get_logs() - Old logs: {s}\n", .{path_copy});
            }

            try logs.append(ally, path_copy);

            ally.free(fPath);
        }
    }

    return logs;
}

fn find_current_log(ally: std.mem.Allocator, old_logs: std.ArrayList([]const u8)) !std.ArrayList([]const u8) {
    var current_logs = std.ArrayList([]const u8).empty;
    // because we are returning this the defer should be where the function is called.

    for (old_logs.items) |f| {
        // https://ziglang.org/documentation/0.14.0/std/#std.mem.lastIndexOf
        if (std.mem.lastIndexOf(u8, f, ".")) |dot_index| {
            const suffix = f[dot_index + 1 ..];
            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and
                std.ascii.isHex(suffix[1]) and
                std.ascii.isHex(suffix[2]))
            {
                // This is an old log file
            } else {
                try current_logs.append(ally, f);
            }
        } else {
            // no dot = current log file
            try current_logs.append(ally, f);
        }
    }
    return current_logs;
}
