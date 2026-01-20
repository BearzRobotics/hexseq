const std = @import("std");
const Io = std.Io;

// RollOver Enum
pub const RO = enum(u8) {
    delete,
    move,
    none, // default value
};

pub const Config = struct {
    debug: bool = false,
    log_dir_set: bool = false,
    log_dir: []const u8 = &.{},
    ro: RO = RO.none,
    ro_dir: []const u8 = &.{},
    byte_cmp: bool = false,
};

pub fn main(init: std.process.Init) !void {

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

    var cfg = Config{};

    if (cfg.log_dir.len > 0 and cfg.log_dir[cfg.log_dir.len - 1] == '/') {
        cfg.log_dir = cfg.log_dir[0 .. cfg.log_dir.len - 1];
    }

    // Accessing command line arguments:
    var args = try init.minimal.args.iterateAllocator(arena);
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            cfg.debug = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            try version(stdout);
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try help(stdout);
        } else if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--logdir")) {
            cfg.log_dir = args.next() orelse {
                std.debug.print("Failed to pass in <path> for --logdir\n", .{});
                std.process.exit(1);
            };

            if (cfg.log_dir.len > 0 and cfg.log_dir[cfg.log_dir.len - 1] == '/') {
                cfg.log_dir = cfg.log_dir[0 .. cfg.log_dir.len - 1];
            }
            if (cfg.debug) {
                std.debug.print("[debug] main() log_dir: {s}\n", .{cfg.log_dir});
            }

            cfg.log_dir_set = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--rollover")) {
            const temp = args.next() orelse {
                std.debug.print("Could not set RO value\n", .{});
                std.process.exit(1);
            };
            if (std.mem.eql(u8, temp, "delete")) {
                cfg.ro = RO.delete;
            } else if (std.mem.eql(u8, temp, "move")) {
                cfg.ro_dir = args.next() orelse {
                    std.debug.print("Was able to set the move flag but not set the path var\n", .{});
                    std.process.exit(1);
                };

                if (cfg.ro_dir.len > 0 and cfg.ro_dir[cfg.ro_dir.len - 1] == '/') {
                    cfg.ro_dir = cfg.ro_dir[0 .. cfg.ro_dir.len - 1];
                }

                if (cfg.debug) {
                    std.debug.print("[debug] main() ro_dir: {s}\n", .{cfg.ro_dir});
                }
                cfg.ro = RO.move;
            }
        } else if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--byte_cmp")) {
            cfg.byte_cmp = true;
        }
    }

    // This is so important that we must kill the program if we don't have anything.
    if (!cfg.log_dir_set) {
        std.debug.print("-l <path> --logdir <path> Must be set!\n", .{});
        std.process.exit(1);
    }

    var oldlogs = try getlogs(arena, cfg, io);
    defer oldlogs.deinit(arena);

    const currentlogs = try findCurrentLogs(arena, oldlogs, cfg, io, stdout);

    try writelogs(arena, cfg, oldlogs, currentlogs, io);

    try stdout.flush(); // Don't forget to flush!
}

fn getlogs(ally: std.mem.Allocator, cfg: Config, io: Io) !std.ArrayList([]const u8) {
    var logs = std.ArrayList([]const u8).empty;

    if (cfg.debug) {
        std.debug.print("[Debug] getlogs() cfg.log_dir: {s}\n", .{cfg.log_dir});
    }

    // Opening this every time is wasteful
    const dirfd = Io.Dir.cwd();
    var dir = try Io.Dir.openDir(dirfd, io, cfg.log_dir, .{ .access_sub_paths = true, .follow_symlinks = false, .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(ally);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        // We only want files not dirs
        if (entry.kind != .file) continue;
        // base + entry.path
        //const fPath = try std.fs.path.join(ally, &.{ cfg.log_dir, entry.path });

        const path_copy = try ally.dupe(u8, entry.path);

        if (cfg.debug) {
            std.debug.print("[debug] getlogs() - Old Logs: {s}\n", .{path_copy});
        }

        try logs.append(ally, path_copy);
    }

    return logs;
}

fn findCurrentLogs(ally: std.mem.Allocator, oldlogs: std.ArrayList([]const u8), cfg: Config, io: Io, stdout: *std.Io.Writer) !std.ArrayList([]const u8) {
    var currentlogs = std.ArrayList([]const u8).empty;
    var is_old = false;

    for (oldlogs.items) |ol| {
        if (std.mem.lastIndexOf(u8, ol, ".")) |dot_index| {
            const suffix = ol[dot_index + 1 ..];

            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and std.ascii.isHex(suffix[1]) and std.ascii.isHex(suffix[2]))
            {
                // This is the old log file
            } // Old log if ".old" suffix
            else if (std.mem.eql(u8, suffix, "old")) {
                is_old = true;
            } else {
                // no dot hex extention = current log file
                if (cfg.debug) {
                    std.debug.print("[debug] findCurrentLogs(): {s}\n", .{ol});
                }

                if (cfg.byte_cmp) {
                    // Here I will need to call a function that cmpares the logs files.
                    // If they are different or the other one doesn't exist, I'll have
                    // to backup the main one.
                } else {
                    try currentlogs.append(ally, ol);
                }
            }
        } else if (ol.len > 0 and ol[ol.len - 1] != '.') {
            if (cfg.debug) {
                std.debug.print("[debug] findCurrentLogs(): {s}\n", .{ol});
            }

            if (cfg.byte_cmp) {
                // Here I will need to call a function that cmpares the logs files.
                // If they are different or the other one doesn't exist, I'll have
                // to backup the main one.
            } else {
                try currentlogs.append(ally, ol);
            }
        }
    }
    for (currentlogs.items) |c| {
        const count = try countlogs(oldlogs, c);
        // need to be changed to max size 4095
        if (cfg.ro == RO.delete and count >= 4095) {
            try rocleanup(ally, cfg, io, RO.delete);
            try stdout.print("Old logs seccufally deleted!\n", .{});
            std.process.exit(0);
        } else if (cfg.ro == RO.move and count >= 4095) {
            try rocleanup(ally, cfg, io, RO.move);
            try stdout.print("Old logs seccufally backedup!\n", .{});
            std.process.exit(0);
        }
    }
    return currentlogs;
}

// This function was called because move/delete was passed
fn rocleanup(ally: std.mem.Allocator, cfg: Config, io: Io, mode: RO) !void {
    if (cfg.debug) {
        std.debug.print("[debug] rocleanup(): {any}\n", .{mode});
    }

    const dirfd = Io.Dir.cwd();

    var buff: [4096]u8 = undefined;
    const cwd = try std.process.getCwd(&buff);
    if (cfg.debug) {
        std.debug.print("[debug] rocleanup() cwd: {s}\n", .{cwd});
    }

    var dir = try Io.Dir.openDir(dirfd, io, cfg.log_dir, .{ .access_sub_paths = true, .follow_symlinks = false, .iterate = true });
    defer dir.close(io);

    const nldir = try std.fmt.allocPrint(ally, "{s}/{s}", .{ cwd, cfg.log_dir });
    const nrdir = try std.fmt.allocPrint(ally, "{s}/{s}", .{ cwd, cfg.ro_dir });
    if (mode == RO.delete) {
        if (cfg.debug) {
            std.debug.print("[debug] rocleanup() Deleting: {s}\n", .{nldir});
        }

        // I don't know if x is going to be the right value
        std.Io.Dir.deleteTree(dir, io, nldir) catch |d| {
            std.debug.print("[debug] rocleanup() Logdir Not Found: {any}\n", .{d});
        };

        // If you want custom dir permisions you have to do the following
        // const customMode: std.posix.mode_t = 0o700; // rwx------ for owner only
        // const perms = std.Io.File.Permissions.fromMode(customMode);
        //try dir.createDir(io, "test/logs", perms);
        try dir.createDir(io, nldir, .default_dir);
    } else {
        if (cfg.debug) {
            std.debug.print("[debug] rocleanup() Mv oldlog dir to: {s} Recreating old log dir: {s}\n", .{ cfg.ro_dir, cfg.log_dir });
        }
        try dir.renamePreserve(nldir, dir, nrdir, io);
        try dir.createDir(io, nldir, .default_dir);
    }
}

fn countlogs(oldlogs: std.ArrayList([]const u8), currentlog: []const u8) !u16 {
    var oLC: u16 = 0;

    for (oldlogs.items) |i| {
        if (std.mem.lastIndexOf(u8, i, ".")) |dot_index| {
            const suffix = i[dot_index + 1 ..];

            if (suffix.len == 3 and
                std.ascii.isHex(suffix[0]) and
                std.ascii.isHex(suffix[1]) and
                std.ascii.isHex(suffix[2]) and
                std.mem.eql(u8, currentlog, i[0..dot_index]))
            {
                oLC += 1;
            }
        }
    }
    return oLC;
}
fn writelogs(ally: std.mem.Allocator, cfg: Config, oldlogs: std.ArrayList([]const u8), currentlogs: std.ArrayList([]const u8), io: Io) !void {
    const dirfd = Io.Dir.cwd();
    var dir = try Io.Dir.openDir(dirfd, io, cfg.log_dir, .{ .access_sub_paths = true, .follow_symlinks = false, .iterate = true });
    defer dir.close(io);

    for (currentlogs.items) |c| {
        const count = try countlogs(oldlogs, c);
        const nhex = dec2hex(count);

        const nname = try std.mem.concat(ally, u8, &.{ c, "."[0..], nhex[0..] });
        defer ally.free(nname);

        if (cfg.debug) {
            std.debug.print("[debug] writelogs() Old Log: {s} renamed as: {s}\n", .{ c, nname });
        }

        try std.Io.Dir.renamePreserve(dir, c, dir, nname, io);
    }
}

fn dec2hex(input: u16) []const u8 {
    const hex = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F' };
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

fn help(stdout: *Io.Writer) !void {
    const help_txt =
        \\ hexseq - hexadecimal log rotator
        \\ 
        \\ Usage: hexseq [options] --logdir <path>
        \\ 
        \\ -h   --help                       Prints help menu.
        \\ -d   --debug                      Enable printing internal debug statements to std::err.
        \\ -v   --version                    Prints the programs version.
        \\ -l   --logdir <path>              Takes a path to the root of your log dir.
        \\ -r   --rollover  <delete|move> <Path>   
        \\                                    
        \\                                   When your backups execed .FFF delete will remove all the old files.
        \\                                   Whereas move when given a path will backup all old logs to the specified dir.
        \\ -b   --byte_cmp                   This enables comparing the file by byte to see if the current and old logs are 
        \\                                   different and only back them up if they are. 
        \\
        \\ By:
        \\ Dakota James Owen Keeler
        \\ DakotaJKeeler@protonmail.com
        \\ Licencse: 
    ;

    try stdout.print("{s}\n", .{help_txt});
    try stdout.flush();
    std.process.exit(0);
}

fn version(stdout: *Io.Writer) !void {
    try stdout.print("0.0.9\n", .{});
    try stdout.flush();
    std.process.exit(0);
}
