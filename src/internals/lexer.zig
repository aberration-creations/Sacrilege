const std = @import("std");

pub const Position = struct { line: u32, char: u32 };

pub const TokenType = enum(u8) {
    unassigned,
    paren_b,
    paren_e,
    number,
    string,
    partial_string, // incomplete string, should resolve into string otherwise its an error
    partial_string_escape, // same as above
    identifier,
    definition, // code that won't be eval'd implicitly.

    pub fn getTypeString(self: TokenType) []const u8 {
        switch (self) {
            .unassigned => return "void",
            .paren_b => return "paren_begin",
            .paren_e => return "paren_end",
            .number => return "number",
            .string => return "string",
            .partial_string => return "partial_string",
            .partial_string_escape => return "partial_string_escape",
            .identifier => return "identifier",
            .definition => return "definition",
        }
        unreachable;
    }
};

pub const Token = struct {
    const Self = @This();

    id: TokenType,
    pos: Position,
    raw: std.ArrayList(u8),

    pub fn init(line: u32, char: u32) !Self {
        return Self{
            .id = TokenType.unassigned,
            .pos = Position{
                .line = line,
                .char = char,
            },
            .raw = std.ArrayList(u8).empty,
        };
    }

    pub fn init_with_content(
        allocator: std.mem.Allocator,
        name: []const u8,
        token_type: TokenType,
    ) !Self {
        var rc = std.ArrayList(u8).empty;
        try rc.appendSlice(allocator, name);
        return Self{
            .id = token_type,
            .pos = Position{ .line = 0, .char = 0 },
            .raw = rc,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.raw.deinit(allocator);
    }

    pub fn copy(self: Self, allocator: std.mem.Allocator) !Self {
        return Token{
            .id = self.id,
            .pos = self.pos,
            .raw = try self.raw.clone(allocator),
        };
    }

    pub fn print(self: Token) void {
        std.debug.print("token: id: {}, raw: {s}\n", .{ self.id, self.raw.items });
    }

    pub fn apply(self: *Token, allocator: std.mem.Allocator, c: u8) !bool {
        switch (self.id) {
            TokenType.unassigned => {
                switch (c) {
                    '(' => {
                        self.id = TokenType.paren_b;
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    ')' => {
                        self.id = TokenType.paren_e;
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    '0'...'9' => {
                        self.id = TokenType.number;
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    '"' => {
                        self.id = TokenType.partial_string;
                        return true;
                    },
                    'a'...'z' => {
                        self.id = TokenType.identifier;
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    'A'...'Z' => {
                        self.id = TokenType.identifier;
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    '\'' => {
                        self.id = TokenType.definition;
                        return true;
                    },
                    else => {
                        return false;
                    },
                }
            },
            TokenType.paren_b, TokenType.paren_e => {
                return false;
            },
            TokenType.number => {
                switch (c) {
                    '0'...'9' => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    else => {
                        return false;
                    },
                }
            },
            TokenType.partial_string => {
                switch (c) {
                    '"' => {
                        self.id = TokenType.string;
                        return true;
                    },
                    '\n', '\r' => {
                        return false;
                    },
                    '\\' => {
                        self.id = TokenType.partial_string_escape;
                        return true;
                    },
                    else => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                }
            },
            TokenType.partial_string_escape => {
                self.id = TokenType.partial_string;
                switch (c) {
                    'r' => {
                        try self.raw.append(allocator, '\r');
                        return true;
                    },
                    'n' => {
                        try self.raw.append(allocator, '\n');
                        return true;
                    },
                    '\\' => {
                        try self.raw.append(allocator, '\\');
                        return true;
                    },
                    't' => {
                        try self.raw.append(allocator, '\t');
                        return true;
                    },
                    else => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                }
            },
            TokenType.string => {
                return false;
            },
            TokenType.identifier => {
                switch (c) {
                    'a'...'z' => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    'A'...'Z' => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    '-' => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    '_' => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    '0'...'9' => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    else => {
                        return false;
                    },
                }
            },
            TokenType.definition => {
                switch (c) {
                    '\'' => {
                        return false;
                    },
                    'a'...'z',
                    'A'...'Z',
                    '0'...'9',
                    '.',
                    ',',
                    => {
                        try self.raw.append(allocator, c);
                        return true;
                    },
                    else => {
                        return false;
                    },
                }
            },
        }
    }
};

pub const Tokenizer = struct {
    tokens: std.ArrayList(Token),

    pub fn init() Tokenizer {
        return Tokenizer{
            .tokens = std.ArrayList(Token).empty,
        };
    }

    pub fn deinit(self: *Tokenizer, allocator: std.mem.Allocator) void {
        for (self.tokens.items) |*tok| {
            tok.deinit(allocator);
        }
        self.tokens.deinit(allocator);
    }

    pub fn tokenize(
        self: *Tokenizer,
        allocator: std.mem.Allocator,
        input: []const u8,
    ) !void {
        var i: usize = 0;
        var charpos: u32 = 0;
        var linepos: u32 = 1;
        var current: Token = try Token.init(1, 1);
        while (i < input.len) {
            const elem = input[i];
            if (elem == '\n') {
                linepos += 1;
                charpos = 0;
            } else {
                charpos += 1;
            }

            // Skip comments that start with ';' until end of line.
            if (elem == ';') {
                if (current.id != TokenType.unassigned) {
                    try self.tokens.append(allocator, current);
                } else {
                    current.deinit(allocator);
                }
                current = try Token.init(linepos, charpos);
                // advance until newline or end (leave i at newline to let loop handle it)
                i += 1;
                while (i < input.len and input[i] != '\n') {
                    i += 1;
                }
                continue;
            }

            const previd = current.id;
            if (!try current.apply(allocator, elem)) {
                if (current.id != TokenType.unassigned) {
                    try self.tokens.append(allocator, current);
                } else {
                    current.deinit(allocator);
                }
                current = try Token.init(linepos, charpos);
                _ = try current.apply(allocator, elem);
            } else {
                if (previd == TokenType.unassigned and previd != current.id) {
                    current.pos.line = linepos;
                    current.pos.char = charpos;
                }
            }
            i += 1;
        }
        if (current.id != TokenType.unassigned) {
            try self.tokens.append(allocator, current);
        } else {
            current.deinit(allocator);
        }
    }

    pub fn print(self: *Tokenizer) void {
        for (self.tokens.items) |tok| {
            tok.print();
        }
    }
};

test "token accept first char" {
    try testTokenAccept('(', true, .paren_b);
    try testTokenAccept(')', true, .paren_e);
    try testTokenAccept('0', true, .number);
    try testTokenAccept('"', true, .partial_string);
    try testTokenAccept('a', true, .identifier);
    try testTokenAccept('A', true, .identifier);
    try testTokenAccept('\'', true, .definition);
    try testTokenAccept(' ', false, .unassigned);
    try testTokenAccept('\n', false, .unassigned);
    try testTokenAccept('\t', false, .unassigned);
}

fn testTokenAccept(c: u8, result: bool, id: TokenType) !void {
    const allocator = std.testing.allocator;
    var tok = try Token.init(1, 1);
    defer tok.deinit(allocator);
    const val = try tok.apply(allocator, c);
    try std.testing.expectEqual(result, val);
    try std.testing.expectEqual(id, tok.id);
}

test "empty tokenizerd deinit" {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init();
    defer tokenizer.deinit(allocator);
}

test "tokenizer deinit after tokenize" {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init();
    defer tokenizer.deinit(allocator);
    try tokenizer.tokenize(allocator, "()");
}

test "tokenzier tokens for basic function call" {
    const allocator = std.testing.allocator;
    var t = try testTokenize("(add 20 40)");
    defer t.deinit(allocator);
    try expectTokenCount(t, 5);
    try expectToken(t, 0, "(", .paren_b);
    try expectToken(t, 1, "add", .identifier);
    try expectToken(t, 2, "20", .number);
    try expectToken(t, 3, "40", .number);
    try expectToken(t, 4, ")", .paren_e);
}

test "tokenzier with strings" {
    const allocator = std.testing.allocator;
    var t = try testTokenize("(set title \"Sacrilege\")");
    defer t.deinit(allocator);
    try expectTokenCount(t, 5);
    try expectToken(t, 0, "(", .paren_b);
    try expectToken(t, 1, "set", .identifier);
    try expectToken(t, 2, "title", .identifier);
    try expectToken(t, 3, "Sacrilege", .string);
    try expectToken(t, 4, ")", .paren_e);
}

test "string can have space" {
    const allocator = std.testing.allocator;
    var t = try testTokenize(
        \\ "text with space"
    );
    defer t.deinit(allocator);
    try expectToken(t, 0, "text with space", .string);
}

test "newline not allowed in strings" {
    const allocator = std.testing.allocator;
    var t = try testTokenize(
        \\"text
        \\space"
    );
    defer t.deinit(allocator);
    try expectToken(t, 0, "text", .partial_string);
    try expectToken(t, 1, "space", .identifier);
    try expectToken(t, 2, "", .partial_string);
}

test "string can have symbols" {
    const allocator = std.testing.allocator;

    var t = try testTokenize(
        \\ "!@#$%^&*()_+{}:<>?"
    );
    defer t.deinit(allocator);
    try expectToken(t, 0, "!@#$%^&*()_+{}:<>?", .string);
}

test "string can have escaped quotes" {
    const allocator = std.testing.allocator;

    var t = try testTokenize(
        \\"text\"space\""
    );
    defer t.deinit(allocator);
    try expectToken(t, 0, "text\"space\"", .string);
}

test "string can have escaped tab, newline, backslash" {
    const allocator = std.testing.allocator;

    var t = try testTokenize(
        \\"\ttext\r\nspace\\\\"
    );
    defer t.deinit(allocator);
    try expectToken(t, 0, "\ttext\r\nspace\\\\", .string);
}

test "tokenzier column position tracking" {
    const allocator = std.testing.allocator;

    var t = try testTokenize("(set title \"Sacrilege\")");
    defer t.deinit(allocator);
    try expectTokenCount(t, 5);
    try expectTokenPosition(t, 0, "(", 1, 1);
    try expectTokenPosition(t, 1, "set", 1, 2);
    try expectTokenPosition(t, 2, "title", 1, 6);
}

test "tokenzier line position tracking" {
    const allocator = std.testing.allocator;

    var t = try testTokenize("(\n  set \n  title \n\"Sacrilege\")");
    defer t.deinit(allocator);
    try expectTokenCount(t, 5);
    try expectTokenPosition(t, 0, "(", 1, 1);
    try expectTokenPosition(t, 1, "set", 2, 3);
    try expectTokenPosition(t, 2, "title", 3, 3);
}

fn testTokenize(input: []const u8) !Tokenizer {
    const allocator = std.testing.allocator;
    var tokenizer = Tokenizer.init();
    try tokenizer.tokenize(allocator, input);
    return tokenizer;
}

fn expectToken(tokenizer: Tokenizer, index: usize, expected: []const u8, oftype: TokenType) !void {
    const token = tokenizer.tokens.items[index];
    try std.testing.expectEqualStrings(expected, token.raw.items);
    try std.testing.expectEqual(oftype, token.id);
}

fn expectTokenPosition(tokenizer: Tokenizer, index: usize, expected: []const u8, line: u32, char: u32) !void {
    const token = tokenizer.tokens.items[index];
    try std.testing.expectEqualStrings(expected, token.raw.items);
    try std.testing.expectEqual(line, token.pos.line);
    try std.testing.expectEqual(char, token.pos.char);
}

fn expectTokenCount(tokenizer: Tokenizer, expected: usize) !void {
    const actual = tokenizer.tokens.items.len;
    try std.testing.expectEqual(expected, actual);
}
