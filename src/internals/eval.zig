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
            // Resolve identifiers to their stored values in the context (for
            // example: function parameters bound into ctx.ids). If an identifier
            // has a stored node in ctx.ids, return a copy of that stored node.
            if (node.atom.id == TokenType.identifier) {
                const key = node.atom.raw.items;
                if (ctx.ids.get(key)) |n| {
                    var res = try n.copy(allocator);
                    if (res == NodeType.atom) {
                        // preserve position for better error messages
                        res.atom.pos = node.atom.pos;
                    }
                    return res;
                }
            }
            return node.copy(allocator);
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
            var evald_active = true;
            defer {
                if (evald_active) {
                    evald.deinit(allocator);
                }
            }

            // Evaluate arguments but do NOT resolve the operator identifier
            // into its stored value. The operator should remain an atom so
            // we can look it up in ctx.funcs (user-defined functions are
            // registered there). Copy the operator atom if it's an
            // identifier; otherwise evaluate it normally.
            if (node.sexpr.items.len != 0) {
                const op = node.sexpr.items[0];
                if (op == NodeType.atom and op.atom.id == TokenType.identifier) {
                    try evald.sexpr.append(allocator, try op.copy(allocator));
                } else {
                    const eop = try eval(ctx, allocator, op);
                    try evald.sexpr.append(allocator, eop);
                }
                for (node.sexpr.items[1..]) |arg| {
                    const earg = try eval(ctx, allocator, arg);
                    try evald.sexpr.append(allocator, earg);
                }
            }

            if (evald.sexpr.items.len != 0 and evald.sexpr.items[0] == NodeType.atom) {
                if (evald.sexpr.items[0].atom.id == TokenType.identifier) {
                    // This is a call. Find the function.
                    // Handle 'eval', separately.
                    const idn_atom = evald.sexpr.items[0].atom;
                    const idn = idn_atom.raw.items;
                    if (std.mem.eql(u8, idn, "eval")) {
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
                        evald_active = false;
                        return evald;
                    } else if (std.mem.eql(u8, idn, "false")) {
                        evald_active = false;
                        return evald;
                    }

                    // Not an eval call - try resolving the identifier using the eager
                    // function dictionary.
                    const idfo = ctx.funcs.get(idn);
                    // evald will be deinitialized by the errdefer above on error
                    // and by the normal control flow after the call returns.
                    // Avoid double-deinit here.
                    //defer evald.deinit(allocator);

                    if (idfo) |idf| {
                        // Evaluate it.
                        return try idf(ctx, allocator, evald);
                    }
                    return ctx.raise_function_does_not_exists(idn_atom);
                }
            }
            evald_active = false;
            return evald;
        },
    }
    unreachable;
}
