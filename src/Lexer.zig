const std = @import("std");
const ascii = std.ascii;
const Token = @import("token.zig").Token;
const Chameleon = @import("chameleon");

const Self = @This();

filepath: []const u8,
file: std.fs.File,
current_char: u8 = 0,
line_no: usize = 1,
column_no: usize = 0,

const Error = error{
    unexpected_character,
};

/// The caller is responsible of closing the file
pub fn init_with_file(filepath: []const u8, file: std.fs.File) Self {
    var instance = Self{
        .filepath = filepath,
        .file = file,
    };
    instance.advance();

    return instance;
}

/// The caller should call `deinit` after exhausting the lexer
pub fn init(filepath: []const u8) !Self {
    const f = try std.fs.cwd().openFile(filepath, .{});

    return init_with_file(filepath, f);
}

pub fn deinit(self: Self) void {
    self.file.close();
}

pub fn print_context(self: Self, writer: std.fs.File.Writer) !void {
    try self.file.seekBy(-@as(i64, @intCast(self.column_no)));

    var buffer: [1024]u8 = undefined;
    const context = try self.file.reader().readUntilDelimiter(&buffer, '\n');

    comptime var c = Chameleon.initComptime();
    try c.underline().bold().print(writer, "{s}:{}:{}:\n", .{
        self.filepath,
        self.line_no,
        self.column_no,
    });
    try writer.print("{s}\n", .{context});
    try writer.writeByteNTimes(' ', self.column_no - 1);
    try writer.print("{s}\n", .{c.reset().green().bold().fmt("^")});
}

fn advance(self: *Self) void {
    if ((self.column_no == 0 and self.current_char == 0) or self.current_char != 0) {
        if (self.current_char == '\n') {
            self.line_no += 1;
            self.column_no = 1;
        } else {
            self.column_no += 1;
        }

        self.current_char = self.file.reader().readByte() catch 0;
    }
}

fn skip_whitespace(self: *Self) void {
    while (self.current_char == ' ' or self.current_char == '\t' or self.current_char == '\r' or self.current_char == '\n') {
        self.advance();
    }
}

fn parse_number(self: *Self) !Token {
    var value: [256]u8 = undefined;
    var idx: usize = 0;
    while (ascii.isDigit(self.current_char)) : (idx += 1) {
        value[idx] = self.current_char;
        self.advance();
    }

    const num = try std.fmt.parseInt(i64, value[0..idx], 10);
    return .{ .push = num };
}

fn advance_with(self: *Self, op: Token) Token {
    self.advance();
    return op;
}

pub fn next(self: *Self) !?Token {
    self.skip_whitespace();

    // if (ascii.isAlphabetic(self.current_char)) {
    //     return self.parse_id();
    // }

    if (ascii.isDigit(self.current_char)) {
        return try self.parse_number();
    }

    return switch (self.current_char) {
        '+' => self.advance_with(.plus),
        '-' => self.advance_with(.minus),
        '.' => self.advance_with(.dump),
        0 => null,
        else => {
            try self.print_context(std.io.getStdErr().writer());
            return Error.unexpected_character;
        },
    };
}
