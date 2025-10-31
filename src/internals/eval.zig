const std = @import("std");

const sac = @import("./public.zig");
const Token = sac.Token;
const Node = sac.Node;
const Context = sac.Context;
const NodeType = sac.NodeType;
const TokenType = sac.TokenType;

pub const EvalError = error{
    WrongArgumentCount,
    WrongArgumentType,
    WrongExpressionType,
    FunctionDoesNotExist,
    UndefinedIdentifier,
    AssertionFailed,
};

pub fn eval(
    ctx: *Context,
    allocator: std.mem.Allocator,
    node: Node,
) !Node {
    switch (node) {
        NodeType.atom => {
            return node.copy();
        },
        NodeType.sexpr => {
            // Apply lazy evaluation rules for some of the builtin expressions.
            if (node.sexpr.items.len != 0 and node.sexpr.items[0] == NodeType.atom) {
                if (node.sexpr.items[0].atom.id == TokenType.identifier) {
                    // This is a call. Try finding a fitting lazy function.
                    const idn = node.sexpr.items[0].atom.raw.items;
                    const idfo = ctx.lazy_funcs.get(idn);
                    if (idfo) |idf| {
                        // Evaluate it.
                        return try idf(ctx, allocator, node);
                    }
                }
            }

            // Eager evaluation rules past this point.
            var evald = Node{ .sexpr = std.ArrayList(Node).empty };
            for (node.sexpr.items) |arg| {
                errdefer {
                    evald.deinit();
                }
                const earg = try eval(ctx, allocator, arg);
                try evald.sexpr.append(earg);
            }

            if (evald.sexpr.items.len != 0 and evald.sexpr.items[0] == NodeType.atom) {
                if (evald.sexpr.items[0].atom.id == TokenType.identifier) {
                    // This is a call. Find the function.
                    // Handle 'eval', separately.
                    const idn_atom = evald.sexpr.items[0].atom;
                    const idn = idn_atom.raw.items;
                    if (std.mem.eql(
                        u8,
                        idn,
                        "eval",
                    )) {
                        defer evald.deinit();
                        try ctx.ensure_argument_count(evald, 1);
                        try ctx.ensure_argument_nodetype(evald, 0, .sexpr);

                        // Recursively evaluate 'eval' calls.
                        const it = evald.sexpr.items[1];
                        return try eval(
                            ctx,
                            allocator,
                            it,
                        );
                    } else if (std.mem.eql(u8, idn, "true")) {
                        // Refuse to evaluate boolean identifiers.
                        return evald;
                    } else if (std.mem.eql(u8, idn, "false")) {
                        return evald;
                    }

                    // Not an eval call - try resolving the identifier using the eager
                    // function dictionary.
                    const idfo = ctx.funcs.get(idn);
                    defer evald.deinit();

                    if (idfo) |idf| {
                        // Evaluate it.
                        return try idf(ctx, allocator, evald);
                    }
                    return ctx.raise_function_does_not_exists(idn_atom);
                }
            }
            return evald;
        },
    }
    unreachable;
}
