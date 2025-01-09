const std = @import("std");
const ascii = std.ascii;
const Token = @import("token.zig").Token;

const Self = @This();

input: []const u8,
current_char: u8,
index: usize,

const Error = error{
    unexpected_character,
};

pub fn init(input: []const u8) !Self {
    return .{
        .input = input,
        .current_char = input[0],
        .index = 0,
    };
}

fn advance(self: *Self) void {
    self.advance_by(1);
}

fn advance_by(self: *Self, offset: usize) void {
    if ((self.index + offset) <= self.input.len and self.current_char != 0) {
        self.index += offset;
        if (self.index < self.input.len) {
            self.current_char = self.input[self.index];
        } else {
            self.current_char = 0;
        }
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
        else => Error.unexpected_character,
    };
}
