const std = @import("std");

const OperationType = enum {
    push,
    plus,
    minus,
    dump,
};

const Operation = union(OperationType) {
    push: i64,
    plus,
    minus,
    dump,
};

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

pub fn simulate(operations: []const Operation) !void {
    var stack = std.ArrayList(i64).init(std.heap.page_allocator);
    defer stack.deinit();

    for (operations) |operation| {
        switch (operation) {
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

const print_call = @embedFile("./dump.asm");

pub fn compile(operations: []const Operation, output_path: []const u8) !void {
    const f = try std.fs.cwd().createFile(output_path, .{});
    defer f.close();
    const writer = f.writer();

    try writer.writeAll("segment .text\n");
    try writer.writeAll("\n ; code inserted from dump.asm\n");
    try writer.writeAll(print_call);
    try writer.writeAll("\n ; end of code inserted from dump.asm\n");
    try writer.writeAll(
        \\global _start
        \\_start:
    );

    for (operations) |operation| {
        switch (operation) {
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
}

const program = [_]Operation{
    .{ .push = 34 },
    .{ .push = 35 },
    .plus,
    .dump,
    .{ .push = 420 },
    .{ .push = 20 },
    .minus,
    .dump,
};

fn print_usage() !void {
    try stdout_writer.writeAll(
        \\Usage: zorth <SUBCOMMAND> [ARGS]
        \\SUBCOMMANDS:
        \\      sim     Simulate the program
        \\      com     Compile the program
    );
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

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        try print_usage();
        return Error.cli_error;
    }

    const subcommand = args[1];
    if (std.mem.eql(u8, subcommand, "sim")) {
        try simulate(&program);
    } else if (std.mem.eql(u8, subcommand, "com")) {
        try compile(&program, "output.asm");
        const allocator = std.heap.page_allocator;
        try run(&.{ "nasm", "-felf64", "output.asm", "-o", "output.o" }, allocator);
        try run(&.{ "ld", "output.o", "-o", "output" }, allocator);
    } else {
        try stderr_writer.print("unknown subcommand: \"{s}\"\n", .{subcommand});
        return Error.cli_error;
    }
}
