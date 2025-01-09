const std = @import("std");
const Token = @import("token.zig").Token;
const Lexer = @import("Lexer.zig");

const Error = error{
    unimplemented,
    empty_stack,
    cli_error,
};

const stdout_writer = std.io.getStdOut().writer();
const stderr_writer = std.io.getStdErr().writer();

fn popOrError(stack: *std.ArrayList(i64)) Error!i64 {
    return stack.popOrNull() orelse return Error.empty_stack;
}

pub fn emulate(lexer: *Lexer, alloc: std.mem.Allocator) !void {
    var stack = std.ArrayList(i64).init(alloc);
    defer stack.deinit();

    while (try lexer.next()) |token| {
        switch (token) {
            .push => |value| {
                try stack.append(value);
            },
            .plus => {
                const a = try popOrError(&stack);
                const b = try popOrError(&stack);
                try stack.append(a + b);
            },
            .minus => {
                const a = try popOrError(&stack);
                const b = try popOrError(&stack);
                try stack.append(b - a);
            },
            .dump => {
                const x = stack.pop();
                try stdout_writer.print("{}\n", .{x});
            },
        }
    }
}

pub fn compile(lexer: *Lexer, args: struct {
    output: ?[]const u8 = null,
}) ![]const u8 {
    const output_path = args.output orelse "output.asm";

    const f = try std.fs.cwd().createFile(output_path, .{});
    defer f.close();
    const writer = f.writer();

    try writer.writeAll("segment .text\n");
    try writer.writeAll("\n ; code inserted from dump.asm\n");
    try writer.writeAll(@embedFile("./dump.asm"));
    try writer.writeAll("\n ; end of code inserted from dump.asm\n");
    try writer.writeAll(
        \\global _start
        \\_start:
    );

    while (try lexer.next()) |token| {
        switch (token) {
            .push => |value| {
                try writer.print("push {}\n", .{value});
            },
            .plus => {
                try writer.writeAll(
                    \\pop rax
                    \\pop rbx
                    \\add rax, rbx
                    \\push rax
                    \\
                );
            },
            .minus => {
                try writer.writeAll(
                    \\pop rax
                    \\pop rbx
                    \\sub rbx, rax
                    \\push rbx
                    \\
                );
            },
            .dump => {
                try writer.writeAll(
                    \\pop rdi
                    \\call dump
                    \\
                );
            },
        }
    }

    try writer.writeAll(
        \\mov rax, 60
        \\mov rdi, 0
        \\syscall
        \\
    );

    return output_path;
}

fn show_usage(exe: []const u8) !void {
    try stdout_writer.print(
        \\Usage: {s} <SUBCOMMAND> [ARGS]
        \\SUBCOMMANDS:
        \\      emu     Emulate the program
        \\      com     Compile the program
    , .{exe});
    return Error.cli_error;
}

fn run(argv: []const []const u8, allocator: std.mem.Allocator) !void {
    var cmd = std.process.Child.init(argv, allocator);
    try stdout_writer.writeAll("CMD: ");
    for (0.., argv) |idx, arg| {
        try stdout_writer.print("{s}{s}", .{ arg, if (idx + 1 < argv.len) " " else "\n" });
    }
    if (try cmd.spawnAndWait() != .Exited) {
        return error.command_error;
    }
}

fn assemble(alloc: std.mem.Allocator, input: []const u8, args: struct {
    output: ?[]const u8 = null,
}) ![]const u8 {
    const output = args.output orelse value: {
        var parts = std.mem.split(u8, input, ".");
        const filepath_wo_ext = parts.first();
        //FIXME: fix the memory leak here
        break :value try std.mem.concat(alloc, u8, &.{ filepath_wo_ext, ".o" });
    };

    try run(&.{ "nasm", "-felf64", input, "-o", output }, alloc);

    return output;
}

fn link(alloc: std.mem.Allocator, input: []const u8, args: struct {
    output: ?[]const u8 = null,
}) ![]const u8 {
    const output = args.output orelse value: {
        var parts = std.mem.split(u8, input, ".");
        break :value parts.first();
    };

    try run(&.{ "ld", input, "-o", output }, alloc);

    return output;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("memory leak");
    const allocator = gpa.allocator();

    var args = std.process.args();
    const program = args.next() orelse unreachable;

    const subcommand = args.next() orelse return show_usage(program);
    const filepath = args.next() orelse return show_usage(program);

    var file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;
    const size = try file.readAll(&buffer);
    var lexer = try Lexer.init(buffer[0..size]);

    if (std.mem.eql(u8, subcommand, "emu")) {
        try emulate(&lexer, allocator);
    } else if (std.mem.eql(u8, subcommand, "com")) {
        var parts = std.mem.split(u8, filepath, ".");
        const first_part = parts.first();
        const assembly_output = try std.mem.concat(allocator, u8, &.{ first_part, ".asm" });
        defer allocator.free(assembly_output);
        const object = try std.mem.concat(allocator, u8, &.{ first_part, ".o" });
        defer allocator.free(object);
        _ = try compile(&lexer, .{ .output = assembly_output });
        _ = try assemble(allocator, assembly_output, .{ .output = object });
        _ = try link(allocator, object, .{});
    } else {
        try stderr_writer.print("unknown subcommand: \"{s}\"\n", .{subcommand});
        return Error.cli_error;
    }
}
