const std = @import("std");

const sac = @import("./public.zig");
const Node = sac.Node;

pub const ParseError = error{
    UnexpectedParenthesis,
    NonExpression,
    EmptyExpression,
    UnmatchedParenthesis,
};

pub fn parse(
    input: []const sac.Token,
    level: usize,
    ntokparsed: *usize,
    allocator: std.mem.Allocator,
) !Node {
    var current = Node.new_sexpr();

    var tokn: usize = 0;
    while (true) {
        if (tokn >= input.len) {
            break;
        }

        switch (input[tokn].id) {
            sac.TokenType.paren_b => {
                var nparsed: usize = 0;
                const nested = try parse(input[(tokn + 1)..], level + 1, &nparsed, allocator);
                try current.sexpr.append(allocator, nested);
                tokn += nparsed;
            },
            sac.TokenType.paren_e => {
                ntokparsed.* = tokn + 1;
                return current;
            },
            else => {
                try current.sexpr.append(allocator, Node{ .atom = try input[tokn].copy(allocator) });
            },
        }
        tokn += 1;
    }
    if (level != 0) {
        return ParseError.UnmatchedParenthesis;
    }
    return current;
}
