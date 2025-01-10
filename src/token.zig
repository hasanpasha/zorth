pub const TokenType = enum {
    push,
    plus,
    minus,
    equal,
    dump,
    @"if",
    @"else",
    end,
};

pub const Token = union(TokenType) {
    push: i64,
    plus,
    minus,
    equal,
    dump,
    @"if": usize,
    @"else": usize,
    end,
};
