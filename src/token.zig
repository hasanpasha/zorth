pub const TokenType = enum {
    push,
    plus,
    minus,
    dump,
};

pub const Token = union(TokenType) {
    push: i64,
    plus,
    minus,
    dump,
};
