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

pub fn cross_reference(lexer: *Lexer, alloc: std.mem.Allocator) ![]Token {
    var tokens = std.ArrayList(Token).init(alloc);
    defer tokens.deinit();

    var stack = std.ArrayList(usize).init(alloc);
    defer stack.deinit();

    var idx: usize = 0;
    while (try lexer.next()) |token| : (idx += 1) {
        try tokens.append(token);
        switch (token) {
            .@"if" => try stack.append(idx),
            .@"else" => {
                const block_start = stack.popOrNull() orelse @panic("`else` should close an `if` block");
                std.debug.assert(tokens.items[block_start] == .@"if");

                tokens.items[block_start] = Token{ .@"if" = idx + 1 };
                try stack.append(idx);
            },
            .end => {
                const block_start = stack.popOrNull() orelse @panic("`end` should close and `if` or `else` block");
                const cond_token = tokens.items[block_start];
                std.debug.assert(cond_token == .@"if" or cond_token == .@"else");

                if (cond_token == .@"if") {
                    tokens.items[block_start] = Token{ .@"if" = idx };
                } else if (tokens.items[block_start] == .@"else") {
                    tokens.items[block_start] = Token{ .@"else" = idx };
                }
            },
            else => {},
        }
    }

    return try tokens.toOwnedSlice();
}

pub fn emulate(lexer: *Lexer, alloc: std.mem.Allocator) !void {
    var stack = std.ArrayList(i64).init(alloc);
    defer stack.deinit();

    const tokens = try cross_reference(lexer, alloc);
    defer alloc.free(tokens);

    var idx: usize = 0;
    while (idx < tokens.len) {
        const token = tokens[idx];
        idx += 1;

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
            .equal => {
                const a = try popOrError(&stack);
                const b = try popOrError(&stack);
                try stack.append(@intFromBool(a == b));
            },
            .dump => {
                const x = try popOrError(&stack);
                try stdout_writer.print("{}\n", .{x});
            },
            .@"if" => |next_block| {
                const x = try popOrError(&stack);
                if (x == 0) idx = next_block;
            },
            .@"else" => |next_block| {
                idx = next_block;
            },
            .end => {},
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

    const alloc = std.heap.page_allocator;
    const tokens = try cross_reference(lexer, alloc);
    defer alloc.free(tokens);

    var idx: usize = 0;
    while (idx < tokens.len) {
        const token = tokens[idx];
        defer idx += 1;

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
            .equal => {
                try writer.writeAll(
                    \\mov rcx, 0
                    \\mov rdx, 1
                    \\pop rax
                    \\pop rbx
                    \\cmp rax, rbx
                    \\cmove rcx, rdx
                    \\push rcx
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
            .@"if" => |block_end| {
                try writer.print(
                    \\pop rax
                    \\test rax, rax
                    \\je block_{}
                    \\
                , .{block_end});
            },
            .@"else" => |block_end| {
                try writer.print(
                    \\jmp block_{}
                    \\block_{}:
                    \\
                , .{ block_end, idx + 1 });
            },
            .end => {
                try writer.print("block_{}:\n", .{idx});
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

    var lexer = try Lexer.init(filepath);
    defer lexer.deinit();

    if (std.mem.eql(u8, subcommand, "emu")) {
        try emulate(&lexer, allocator);
    } else if (std.mem.eql(u8, subcommand, "com")) {
        var parts = std.mem.split(u8, filepath, ".");
        const first_part = parts.first();
        const assembly = try std.mem.concat(allocator, u8, &.{ first_part, ".asm" });
        defer allocator.free(assembly);
        const object = try std.mem.concat(allocator, u8, &.{ first_part, ".o" });
        defer allocator.free(object);
        _ = try compile(&lexer, .{ .output = assembly });
        _ = try assemble(allocator, assembly, .{ .output = object });
        _ = try link(allocator, object, .{});
    } else {
        try stderr_writer.print("unknown subcommand: \"{s}\"\n", .{subcommand});
        return Error.cli_error;
    }
}
