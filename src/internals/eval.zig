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
                    // Fast path: if operator identifier is an alias bound to another
                    // identifier that names a registered function, swap and call it.
                    if (ctx.ids.get(idn)) |alias_val| {
                        if (alias_val == NodeType.atom and alias_val.atom.id == TokenType.identifier) {
                            const alt = alias_val.atom.raw.items;
                            if (ctx.funcs.get(alt)) |aidf| {
                                evald.sexpr.items[0].deinit(allocator);
                                evald.sexpr.items[0] = try alias_val.copy(allocator);
                                return try aidf(ctx, allocator, evald);
                            }
                        }
                    }
                    // Try resolving operator identifier via context ids (function values)
                    if (ctx.ids.get(idn)) |alias_val| {
                        if (alias_val == NodeType.atom and alias_val.atom.id == TokenType.identifier) {
                            const alt = alias_val.atom.raw.items;
                            if (ctx.ids.get(alt)) |stored| {
                                // Invoke as function value using stored definition
                                if (stored != NodeType.sexpr or stored.sexpr.items.len == 0) {
                                    return EvalError.WrongExpressionType;
                                }
                                const params_node2 = stored.sexpr.items[0];
                                if (params_node2 != NodeType.sexpr) {
                                    return EvalError.WrongExpressionType;
                                }
                                const param_count2 = params_node2.sexpr.items.len;
                                const provided_count2 = evald.sexpr.items.len - 1;
                                if (provided_count2 != param_count2) {
                                    return ctx.raise_error(
                                        EvalError.WrongArgumentCount,
                                        idn_atom,
                                        "Wrong argument count expected {} found {}",
                                        .{ param_count2, provided_count2 },
                                    );
                                }
                                const Binding2 = struct { key: []const u8, prev: ?Node = null };
                                var bindings2 = std.ArrayList(Binding2).empty;
                                defer {
                                    var j: usize = bindings2.items.len;
                                    while (j > 0) {
                                        j -= 1;
                                        const b = &bindings2.items[j];
                                        if (b.prev) |pv| {
                                            if (ctx.ids.get(b.key)) |*cur| {
                                                cur.deinit(allocator);
                                                _ = ctx.ids.put(b.key, pv) catch {};
                                            } else {
                                                _ = ctx.ids.put(b.key, pv) catch {};
                                            }
                                        } else {
                                            if (ctx.ids.get(b.key)) |*cur| {
                                                cur.deinit(allocator);
                                                _ = ctx.ids.remove(b.key);
                                            }
                                        }
                                    }
                                    bindings2.deinit(allocator);
                                }
                                for (params_node2.sexpr.items, evald.sexpr.items[1..]) |p, a| {
                                    var b = Binding2{ .key = p.atom.raw.items };
                                    const a_copy = try a.copy(allocator);
                                    if (ctx.ids.get(b.key)) |*ex| {
                                        b.prev = try ex.*.copy(allocator);
                                        ex.deinit(allocator);
                                        try ctx.ids.put(b.key, a_copy);
                                    } else {
                                        try ctx.ids.put(b.key, a_copy);
                                    }
                                    try bindings2.append(allocator, b);
                                }
                                var res2 = Node{ .sexpr = std.ArrayList(Node).empty };
                                var have2 = false;
                                for (stored.sexpr.items[1..]) |body2| {
                                    if (have2) {
                                        res2.deinit(allocator);
                                    } else {
                                        have2 = true;
                                    }
                                    res2 = try eval(ctx, allocator, body2);
                                }
                                return res2;
                            }
                        } else if (alias_val == NodeType.sexpr) {
                            // Treat as function value
                            const stored = alias_val;
                            const params_node = stored.sexpr.items[0];
                            const param_count = params_node.sexpr.items.len;
                            const provided_count = evald.sexpr.items.len - 1;
                            if (provided_count != param_count) {
                                return ctx.raise_error(
                                    EvalError.WrongArgumentCount,
                                    idn_atom,
                                    "Wrong argument count expected {} found {}",
                                    .{ param_count, provided_count },
                                );
                            }
                            const Binding = struct { key: []const u8, prev: ?Node = null };
                            var bindings = std.ArrayList(Binding).empty;
                            defer {
                                var idx: usize = bindings.items.len;
                                while (idx > 0) {
                                    idx -= 1;
                                    const binding = &bindings.items[idx];
                                    if (binding.prev) |prev_node| {
                                        if (ctx.ids.get(binding.key)) |*current| {
                                            current.deinit(allocator);
                                            _ = ctx.ids.put(binding.key, prev_node) catch {};
                                        } else {
                                            _ = ctx.ids.put(binding.key, prev_node) catch {};
                                        }
                                    } else {
                                        if (ctx.ids.get(binding.key)) |*current| {
                                            current.deinit(allocator);
                                            _ = ctx.ids.remove(binding.key);
                                        }
                                    }
                                }
                                bindings.deinit(allocator);
                            }
                            for (params_node.sexpr.items, evald.sexpr.items[1..]) |param_value, arg_val| {
                                var binding = Binding{ .key = param_value.atom.raw.items };
                                const arg_copy = try arg_val.copy(allocator);
                                if (ctx.ids.get(binding.key)) |*existing| {
                                    binding.prev = try existing.*.copy(allocator);
                                    existing.deinit(allocator);
                                    try ctx.ids.put(binding.key, arg_copy);
                                } else {
                                    try ctx.ids.put(binding.key, arg_copy);
                                }
                                try bindings.append(allocator, binding);
                            }
                            var result = Node{ .sexpr = std.ArrayList(Node).empty };
                            var have_result = false;
                            for (stored.sexpr.items[1..]) |body| {
                                if (have_result) {
                                    result.deinit(allocator);
                                } else {
                                    have_result = true;
                                    result.deinit(allocator);
                                }
                                result = try eval(ctx, allocator, body);
                            }
                            if (!have_result) return result;
                            return result;
                        }
                    }
                    return ctx.raise_function_does_not_exists(idn_atom);
                } else if (evald.sexpr.items[0] == NodeType.sexpr) {
                    // Operator evaluated to a function value (lambda/defun capture).
                    const stored = evald.sexpr.items[0];
                    if (stored != NodeType.sexpr or stored.sexpr.items.len == 0) {
                        return EvalError.WrongExpressionType;
                    }
                    const params_node = stored.sexpr.items[0];
                    if (params_node != NodeType.sexpr) {
                        return EvalError.WrongExpressionType;
                    }

                    const param_count = params_node.sexpr.items.len;
                    const provided_count = evald.sexpr.items.len - 1;
                    if (provided_count != param_count) {
                        return ctx.raise_error(
                            EvalError.WrongArgumentCount,
                            node.sexpr.items[0].findFirstToken(),
                            "Wrong argument count expected {} found {}",
                            .{ param_count, provided_count },
                        );
                    }

                    const Binding = struct {
                        key: []const u8,
                        prev: ?Node = null,
                    };

                    var bindings = std.ArrayList(Binding).empty;
                    defer {
                        var idx: usize = bindings.items.len;
                        while (idx > 0) {
                            idx -= 1;
                            const binding = &bindings.items[idx];
                            if (binding.prev) |prev_node| {
                                if (ctx.ids.get(binding.key)) |*current| {
                                    current.deinit(allocator);
                                    _ = ctx.ids.put(binding.key, prev_node) catch {};
                                } else {
                                    _ = ctx.ids.put(binding.key, prev_node) catch {};
                                }
                            } else {
                                if (ctx.ids.get(binding.key)) |*current| {
                                    current.deinit(allocator);
                                    _ = ctx.ids.remove(binding.key);
                                }
                            }
                        }
                        bindings.deinit(allocator);
                    }

                    // Bind evaluated args directly from evald
                    for (params_node.sexpr.items, evald.sexpr.items[1..]) |param_value, arg_val| {
                        var binding = Binding{ .key = param_value.atom.raw.items };
                        const arg_copy = try arg_val.copy(allocator);
                        if (ctx.ids.get(binding.key)) |*existing| {
                            binding.prev = try existing.*.copy(allocator);
                            existing.deinit(allocator);
                            try ctx.ids.put(binding.key, arg_copy);
                        } else {
                            try ctx.ids.put(binding.key, arg_copy);
                        }
                        try bindings.append(allocator, binding);
                    }

                    var result = Node{ .sexpr = std.ArrayList(Node).empty };
                    var have_result = false;
                    for (stored.sexpr.items[1..]) |body| {
                        if (have_result) {
                            result.deinit(allocator);
                        } else {
                            have_result = true;
                            result.deinit(allocator);
                        }
                        result = try eval(ctx, allocator, body);
                    }
                    if (!have_result) {
                        return result;
                    }
                    return result;
                }
            }
            evald_active = false;
            return evald;
        },
    }
    unreachable;
}
