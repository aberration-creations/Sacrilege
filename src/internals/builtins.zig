const std = @import("std");

const sac = @import("./public.zig");
const Context = sac.Context;
const Node = sac.Node;
const Token = sac.Token;
const EvalError = sac.EvalError;
const eval = sac.eval;
const NodeType = sac.NodeType;
const TokenType = sac.TokenType;
const Tokenizer = sac.Tokenizer;
const parse = sac.parse;
const Position = sac.Position;

pub fn registerBuiltins(ctx: *Context) !void {
    try ctx.lazy_funcs.put("if", &builtin_lazy_if);
    try ctx.lazy_funcs.put("foreach", &builtin_lazy_foreach);
    try ctx.lazy_funcs.put("defun", &builtin_defun);

    try ctx.funcs.put("assert", &builtin_assert);

    try ctx.funcs.put("sum", &builtin_sum);
    try ctx.funcs.put("sub", &builtin_sub);
    try ctx.funcs.put("mult", &builtin_mult);
    try ctx.funcs.put("div", &builtin_div);
    try ctx.funcs.put("eq", &builtin_equal);
    try ctx.funcs.put("lt", &builtin_lt);
    try ctx.funcs.put("gt", &builtin_gt);

    try ctx.funcs.put("and", &builtin_and);
    try ctx.funcs.put("or", &builtin_or);
    try ctx.funcs.put("not", &builtin_not);

    try ctx.funcs.put("print", &builtin_print);

    try ctx.lazy_funcs.put("set", &builtin_set);
    try ctx.lazy_funcs.put("get", &builtin_get);

    try ctx.funcs.put("len", &builtin_len);
    try ctx.funcs.put("car", &builtin_car);
    try ctx.funcs.put("cdr", &builtin_cdr);
    try ctx.funcs.put("elem", &builtin_elem);
    try ctx.funcs.put("last", &builtin_last);
    try ctx.funcs.put("append", &builtin_append);

    // List constructors and predicates
    try ctx.funcs.put("list", &builtin_list);
    try ctx.funcs.put("cons", &builtin_cons);
    try ctx.funcs.put("empty", &builtin_is_empty);

    try ctx.funcs.put("readfile", &builtin_readfile);
    try ctx.funcs.put("evalfile", &builtin_evalfile);

    try ctx.funcs.put("parse", &builtin_parse);
}

pub fn builtin_true(allocator: std.mem.Allocator) anyerror!Node {
    return try make_identifier(allocator, "true");
}

pub fn builtin_false(allocator: std.mem.Allocator) anyerror!Node {
    return try make_identifier(allocator, "false");
}

pub fn builtin_empty(_: std.mem.Allocator) Node {
    return Node{ .sexpr = std.ArrayList(Node).empty };
}

fn builtin_assert(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count(node, 1);
    var true_node = try builtin_true(allocator);
    defer true_node.deinit(allocator);
    if (!node.sexpr.items[1].equal(true_node)) {
        return ctx.raise_error(EvalError.AssertionFailed, node.sexpr.items[0].atom, "assertion failed!", .{});
    }
    return builtin_empty(allocator);
}

fn builtin_equal(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count(node, 2);
    if (!node.sexpr.items[1].equal(node.sexpr.items[2])) {
        return try builtin_false(allocator);
    }
    return try builtin_true(allocator);
}

fn builtin_lt(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count(node, 2);
    if (try node_to_i128(ctx, node.sexpr.items[1]) < try node_to_i128(ctx, node.sexpr.items[2])) {
        return try builtin_true(allocator);
    }
    return try builtin_false(allocator);
}

fn builtin_gt(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count(node, 2);
    if (try node_to_i128(ctx, node.sexpr.items[1]) > try node_to_i128(ctx, node.sexpr.items[2])) {
        return try builtin_true(allocator);
    }
    return try builtin_false(allocator);
}

fn builtin_print(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    for (node.sexpr.items[1..]) |item| {
        switch (item) {
            NodeType.atom => {
                try stdout.print("{s} ", .{item.atom.raw.items});
            },
            NodeType.sexpr => {
                return EvalError.WrongArgumentType;
            },
        }
    }
    try stdout.print("\n", .{});
    try stdout.flush();
    return builtin_empty(allocator);
}

fn builtin_set(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    //try ctx.ensure_argument_count(node, 2);
    try ctx.ensure_argument_tokentype(node, 0, TokenType.identifier);
    const key = try node.sexpr.items[1].atom.raw.clone(allocator);
    // Evaluate the value expression before storing it in the context so
    // subsequent (get ...) returns the evaluated value.
    const evaluated_value = try eval(ctx, allocator, node.sexpr.items[2]);
    const value = try evaluated_value.copy(allocator);
    // we copied evaluated_value into `value` which is stored in the context;
    // free the temporary evaluated_value to avoid leaking its contents
    defer evaluated_value.deinit(allocator);
    try ctx.strings.append(allocator, key);
    if (ctx.ids.get(key.items)) |*existing| {
        existing.deinit(allocator);
    }
    try ctx.ids.put(key.items, value);

    return builtin_empty(allocator);
}

fn builtin_get(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count(node, 1);
    if (node.sexpr.items[1] != NodeType.atom) {
        return ctx.raise_wrong_argument_node_type(node, TokenType.identifier);
    }
    if (node.sexpr.items[1].atom.id != TokenType.identifier) {
        return ctx.raise_wrong_argument_token_type(node.sexpr.items[1].atom, TokenType.identifier);
    }
    const key = node.sexpr.items[1].atom.raw;
    if (ctx.ids.get(key.items)) |n| {
        var result = try n.copy(allocator);
        if (result == NodeType.atom) {
            result.atom.pos = node.sexpr.items[0].atom.pos;
        }
        return result;
    }
    return ctx.raise_undefined_indentifier(node.sexpr.items[1].atom);
}

fn builtin_defun(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len < 3) {
        return EvalError.WrongArgumentCount;
    }
    try ctx.ensure_argument_tokentype(node, 0, TokenType.identifier);

    const name_token = node.sexpr.items[1].atom;
    var name_copy = try name_token.raw.clone(allocator);
    errdefer name_copy.deinit(allocator);

    var fn_def = Node.new_sexpr();
    errdefer fn_def.deinit(allocator);

    var body_start_index: usize = 2;
    if (node.sexpr.items.len >= 4) {
        const maybe_params = node.sexpr.items[2];
        if (maybe_params != NodeType.sexpr) {
            return EvalError.WrongArgumentType;
        }
        for (maybe_params.sexpr.items) |param| {
            if (param != NodeType.atom or param.atom.id != TokenType.identifier) {
                return EvalError.WrongArgumentType;
            }
        }
        try fn_def.sexpr.append(allocator, try maybe_params.copy(allocator));
        body_start_index = 3;
    } else {
        try fn_def.sexpr.append(allocator, Node.new_sexpr());
    }

    if (node.sexpr.items.len <= body_start_index) {
        return EvalError.WrongArgumentCount;
    }
    // Build a set of parameter names to avoid capturing them.
    var param_names = std.StringHashMap(void).init(allocator);
    defer {
        param_names.deinit();
    }
    const params_node_ref = fn_def.sexpr.items[0];
    for (params_node_ref.sexpr.items) |p| {
        if (p == NodeType.atom and p.atom.id == TokenType.identifier) {
            try param_names.put(p.atom.raw.items, {});
        }
    }

    // Capture free identifiers by replacing them with their current values.
    const transform = struct {
        fn walk(tctx: *Context, alloc: std.mem.Allocator, n: Node, params: *std.StringHashMap(void)) anyerror!Node {
            switch (n) {
                NodeType.atom => {
                    if (n.atom.id == TokenType.identifier) {
                        // Do not capture parameter names.
                        if (params.get(n.atom.raw.items) == null) {
                            if (tctx.ids.get(n.atom.raw.items)) |val| {
                                return try val.copy(alloc);
                            }
                        }
                    }
                    return n.copy(alloc);
                },
                NodeType.sexpr => {
                    var out = Node.new_sexpr();
                    if (n.sexpr.items.len > 0) {
                        const head = n.sexpr.items[0];
                        var head_is_ident = false;
                        var head_name: []const u8 = &[_]u8{};
                        if (head == NodeType.atom and head.atom.id == TokenType.identifier) {
                            head_is_ident = true;
                            head_name = head.atom.raw.items;
                            try out.sexpr.append(alloc, try head.copy(alloc));
                        } else {
                            try out.sexpr.append(alloc, try walk(tctx, alloc, head, params));
                        }

                        var idx: usize = 1;
                        while (idx < n.sexpr.items.len) : (idx += 1) {
                            const child = n.sexpr.items[idx];
                            // Special-cases: for set/get, preserve the identifier operand untransformed
                            if (head_is_ident and (std.mem.eql(u8, head_name, "set") or std.mem.eql(u8, head_name, "get")) and idx == 1) {
                                try out.sexpr.append(alloc, try child.copy(alloc));
                                continue;
                            }
                            try out.sexpr.append(alloc, try walk(tctx, alloc, child, params));
                        }
                    }
                    return out;
                },
            }
            unreachable;
        }
    };

    for (node.sexpr.items[body_start_index..]) |expr| {
        const transformed = try transform.walk(ctx, allocator, expr, &param_names);
        try fn_def.sexpr.append(allocator, transformed);
    }

    try ctx.strings.append(allocator, name_copy);
    errdefer {
        _ = ctx.strings.pop();
        name_copy.deinit(allocator);
    }

    if (ctx.ids.get(name_copy.items)) |*existing| {
        existing.deinit(allocator);
    }
    try ctx.ids.put(name_copy.items, fn_def);

    if (ctx.funcs.get(name_copy.items)) |_| {
        _ = ctx.funcs.remove(name_copy.items);
    }
    try ctx.funcs.put(name_copy.items, &builtin_user_function);
    return builtin_empty(allocator);
}

fn builtin_user_function(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len == 0) {
        return EvalError.WrongArgumentCount;
    }

    const fname_token = node.sexpr.items[0].atom;
    const fname = fname_token.raw.items;

    const stored = ctx.ids.get(fname) orelse {
        return ctx.raise_function_does_not_exists(fname_token);
    };
    if (stored != NodeType.sexpr or stored.sexpr.items.len == 0) {
        return EvalError.WrongExpressionType;
    }
    const params_node = stored.sexpr.items[0];
    if (params_node != NodeType.sexpr) {
        return EvalError.WrongExpressionType;
    }

    const param_count = params_node.sexpr.items.len;
    const provided_count = node.sexpr.items.len - 1;
    if (provided_count != param_count) {
        return ctx.raise_error(
            EvalError.WrongArgumentCount,
            fname_token,
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
            var binding = &bindings.items[idx];
            if (binding.prev) |prev_node| {
                if (ctx.ids.get(binding.key)) |*current| {
                    current.deinit(allocator);
                }
                // Deep copy the node before putting it back to avoid double-free
                if (prev_node.copy(allocator)) |prev_node_copy| {
                    _ = ctx.ids.put(binding.key, prev_node_copy) catch {
                        prev_node_copy.deinit(allocator);
                    };
                } else |_| {
                    // If copy fails, we can't restore, but we should still clean up
                }
                binding.prev.?.deinit(allocator);
                binding.prev = null;
            } else {
                if (ctx.ids.get(binding.key)) |*current| {
                    current.deinit(allocator);
                    _ = ctx.ids.remove(binding.key);
                }
            }
        }
        for (bindings.items) |binding| {
            if (binding.prev) |prev_node| {
                prev_node.deinit(allocator);
            }
        }
        bindings.deinit(allocator);
    }

    for (params_node.sexpr.items, node.sexpr.items[1..]) |param_value, arg_node| {
        if (param_value != NodeType.atom or param_value.atom.id != TokenType.identifier) {
            return EvalError.WrongArgumentType;
        }

        const evaluated_arg = try eval(ctx, allocator, arg_node);

        var binding = Binding{
            .key = param_value.atom.raw.items,
        };

        if (ctx.ids.get(binding.key)) |*existing| {
            binding.prev = try existing.*.copy(allocator);
            existing.deinit(allocator);
            try ctx.ids.put(binding.key, evaluated_arg);
        } else {
            errdefer evaluated_arg.deinit(allocator);
            try ctx.ids.put(binding.key, evaluated_arg);
        }

        try bindings.append(allocator, binding);
    }

    // Tail Call Optimization for user-defined functions:
    // Evaluate non-last body expressions for side-effects, and if the last
    // expression is a self-call in tail position, rebind parameters and
    // continue the loop instead of recursing.
    while (true) {
        const body_len_total = stored.sexpr.items.len;
        if (body_len_total <= 1) {
            return builtin_empty(allocator);
        }

        // Evaluate all non-last expressions and discard their results.
        if (body_len_total > 2) {
            for (stored.sexpr.items[1 .. body_len_total - 1]) |non_last| {
                var tmp = try eval(ctx, allocator, non_last);
                tmp.deinit(allocator);
            }
        }

        const last_expr = stored.sexpr.items[body_len_total - 1];
        var is_tail_self_call = false;
        if (last_expr == NodeType.sexpr and last_expr.sexpr.items.len > 0) {
            const op = last_expr.sexpr.items[0];
            if (op == NodeType.atom and op.atom.id == TokenType.identifier) {
                if (std.mem.eql(u8, op.atom.raw.items, fname)) {
                    is_tail_self_call = true;
                }
            }
        }

        if (!is_tail_self_call) {
            // Not a tail self-call: evaluate and return the result.
            return try eval(ctx, allocator, last_expr);
        }

        // Tail self-call detected. Rebind arguments and loop.
        const provided_tail = last_expr.sexpr.items.len - 1;
        if (provided_tail != param_count) {
            return ctx.raise_error(
                EvalError.WrongArgumentCount,
                last_expr.sexpr.items[0].atom,
                "Wrong argument count expected {} found {}",
                .{ param_count, provided_tail },
            );
        }

        // Evaluate each argument and replace current bound values.
        for (params_node.sexpr.items, last_expr.sexpr.items[1..]) |param_value, arg_node| {
            // Sanity: params are identifiers (already validated earlier)
            const evaluated_arg = try eval(ctx, allocator, arg_node);
            const key = param_value.atom.raw.items;
            if (ctx.ids.get(key)) |*current| {
                current.deinit(allocator);
                try ctx.ids.put(key, evaluated_arg);
            } else {
                // Should not happen, but ensure binding exists
                try ctx.ids.put(key, evaluated_arg);
            }
        }

        // Loop back; bindings' prev values remain untouched and will be
        // restored by the defer at the end of this function.
    }
}

fn node_to_i128(ctx: *Context, node: Node) !i128 {
    try ctx.ensure_node_datatype(node, TokenType.number);
    return try std.fmt.parseInt(
        i128,
        node.atom.raw.items,
        10,
    );
}

fn make_number(allocator: std.mem.Allocator, num: i128, pos: Position) !Node {
    var res = Node{ .atom = try Token.init(pos.line, pos.char) };
    res.atom.id = TokenType.number;

    const ncu8 = try std.fmt.allocPrint(allocator, "{}", .{num});
    defer allocator.free(ncu8);
    try res.atom.raw.appendSlice(allocator, ncu8);
    return res;
}

fn builtin_sum(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count_at_least(node, 1);
    var sum: i128 = 0;
    for (node.sexpr.items[1..]) |arg| {
        sum += try node_to_i128(ctx, arg);
    }
    const pos = node.sexpr.items[0].atom.pos;
    return make_number(allocator, sum, pos);
}

fn builtin_sub(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count_at_least(node, 1);
    var sum: i128 = try node_to_i128(ctx, node.sexpr.items[1]);
    for (node.sexpr.items[2..]) |arg| {
        sum -= try node_to_i128(ctx, arg);
    }
    const pos = node.sexpr.items[0].atom.pos;
    return make_number(allocator, sum, pos);
}

fn builtin_mult(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count_at_least(node, 1);
    var res: i128 = try node_to_i128(ctx, node.sexpr.items[1]);
    for (node.sexpr.items[2..]) |arg| {
        res *= try node_to_i128(ctx, arg);
    }
    const pos = node.sexpr.items[0].atom.pos;
    return make_number(allocator, res, pos);
}

fn builtin_div(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count_at_least(node, 1);
    var res: i128 = try node_to_i128(ctx, node.sexpr.items[1]);
    for (node.sexpr.items[2..]) |arg| {
        res = @divFloor(res, try node_to_i128(ctx, arg));
    }
    const pos = node.sexpr.items[0].atom.pos;
    return make_number(allocator, res, pos);
}

fn builtin_len(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 2) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    const pos = node.sexpr.items[0].atom.pos;
    return make_number(allocator, @as(i128, node.sexpr.items[1].sexpr.items.len), pos);
}

fn builtin_car(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].sexpr.items.len < 1) {
        return EvalError.WrongArgumentCount;
    }
    return try node.sexpr.items[1].sexpr.items[0].copy(allocator);
}

fn builtin_elem(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len < 3) {
        return EvalError.WrongArgumentCount;
    }
    const unr: u128 = @intCast(try node_to_i128(ctx, node.sexpr.items[1]) - 1);
    const nr: usize = @truncate(unr);
    if (node.sexpr.items[2] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[2].sexpr.items.len < nr) {
        return EvalError.WrongArgumentCount;
    }
    return try node.sexpr.items[2].sexpr.items[nr].copy(allocator);
}

fn builtin_last(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    const sl = node.sexpr.items[1].sexpr.items.len;
    if (sl == 0) {
        return EvalError.WrongArgumentType;
    }
    return try node.sexpr.items[1].sexpr.items[sl - 1].copy(allocator);
}

fn builtin_append(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items.len < 3) {
        return EvalError.WrongArgumentCount;
    }
    var out = Node.new_sexpr();
    // copy base list
    for (node.sexpr.items[1].sexpr.items) |it| {
        try out.sexpr.append(allocator, try it.copy(allocator));
    }
    // append additional items (as elements)
    for (node.sexpr.items[2..]) |item| {
        try out.sexpr.append(allocator, try item.copy(allocator));
    }
    return out;
}

fn builtin_list(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    // Build a new list from evaluated arguments
    var out = Node.new_sexpr();
    for (node.sexpr.items[1..]) |arg| {
        try out.sexpr.append(allocator, try arg.copy(allocator));
    }
    return out;
}

fn builtin_cons(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 3) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[2] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    var out = Node.new_sexpr();
    try out.sexpr.append(allocator, try node.sexpr.items[1].copy(allocator));
    // Append the rest (shallow copy of items, but copy nodes to own storage)
    for (node.sexpr.items[2].sexpr.items) |it| {
        try out.sexpr.append(allocator, try it.copy(allocator));
    }
    return out;
}

fn builtin_is_empty(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 2) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].sexpr.items.len == 0) {
        return try builtin_true(allocator);
    }
    return try builtin_false(allocator);
}

fn builtin_and(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len == 1) {
        return EvalError.WrongArgumentCount;
    }
    for (node.sexpr.items[1..]) |item| {
        if (item != NodeType.atom) {
            return EvalError.WrongArgumentType;
        }
        if (item.atom.id != TokenType.identifier) {
            return EvalError.WrongArgumentType;
        }
        if (!std.mem.eql(u8, item.atom.raw.items, "true")) {
            return builtin_false(allocator);
        }
    }
    return builtin_true(allocator);
}

fn builtin_or(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len == 1) {
        return EvalError.WrongArgumentCount;
    }
    for (node.sexpr.items[1..]) |item| {
        if (item != NodeType.atom) {
            return EvalError.WrongArgumentType;
        }
        if (item.atom.id != TokenType.identifier) {
            return EvalError.WrongArgumentType;
        }
        if (std.mem.eql(u8, item.atom.raw.items, "true")) {
            return builtin_true(allocator);
        }
    }
    return builtin_false(allocator);
}

fn builtin_not(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 2) {
        return EvalError.WrongArgumentCount;
    }
    if (node != NodeType.atom) {
        return EvalError.WrongArgumentType;
    }
    if (node.atom.id != TokenType.identifier) {
        return EvalError.WrongArgumentType;
    }
    if (std.mem.eql(u8, node.atom.raw.items, "true")) {
        return builtin_false(allocator);
    }
    if (std.mem.eql(u8, node.atom.raw.items, "false")) {
        return builtin_true(allocator);
    }
    return EvalError.WrongArgumentType;
}

fn builtin_cdr(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    // TODO check argument counts
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items.len == 0) {
        return EvalError.WrongArgumentCount;
    }
    var out = Node.new_sexpr();
    var idx: usize = 1;
    while (idx < node.sexpr.items[1].sexpr.items.len) : (idx += 1) {
        try out.sexpr.append(allocator, try node.sexpr.items[1].sexpr.items[idx].copy(allocator));
    }
    return out;
}

fn builtin_readfile(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 2) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1] != NodeType.atom) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].atom.id != TokenType.string) {
        return EvalError.WrongArgumentType;
    }
    const filename = node.sexpr.items[1].atom.raw.items;

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const raw = try file.readToEndAlloc(allocator, 1024 * 1024);
    var nc = std.ArrayList(u8).empty;
    try nc.appendSlice(allocator, raw);
    return Node{ .atom = try Token.init_with_content(allocator, raw, .string) };
}

fn builtin_parse(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 2) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1] != NodeType.atom) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].atom.id != TokenType.string) {
        return EvalError.WrongArgumentType;
    }
    var tokenizer = Tokenizer.init();
    defer tokenizer.deinit(allocator);
    try tokenizer.tokenize(allocator, node.sexpr.items[1].atom.raw.items);
    var ntokparsed: usize = 0;
    return try parse(tokenizer.tokens.items, 0, &ntokparsed, allocator);
}

fn builtin_evalfile(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len != 2) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1] != NodeType.atom) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].atom.id != TokenType.string) {
        return EvalError.WrongArgumentType;
    }
    const filename = node.sexpr.items[1].atom.raw.items;

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const raw = try file.readToEndAlloc(allocator, 1024 * 1024);
    var tokenizer = Tokenizer.init();
    defer tokenizer.deinit(allocator);
    try tokenizer.tokenize(allocator, raw);
    var ntokparsed: usize = 0;
    const nparsed = try parse(tokenizer.tokens.items, 0, &ntokparsed, allocator);
    return try eval(ctx, allocator, nparsed);
}

fn builtin_lazy_foreach(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len < 3) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].sexpr.items.len == 0) {
        return EvalError.WrongArgumentCount;
    }
    if (node.sexpr.items[1].sexpr.items[0] != NodeType.atom) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].sexpr.items[0].atom.id != TokenType.identifier) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[2] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }

    var rslt = Node.new_sexpr();
    for (node.sexpr.items[2].sexpr.items) |item| {
        var evalNode = node.sexpr.items[1];
        try evalNode.sexpr.append(allocator, try eval(ctx, allocator, item));
        try rslt.sexpr.append(allocator, try eval(ctx, allocator, evalNode));
    }
    return rslt;
}

fn builtin_lazy_if(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items.len < 3 or node.sexpr.items.len > 4) {
        return EvalError.WrongArgumentCount;
    }
    const econd = try eval(ctx, allocator, node.sexpr.items[1]);
    if (econd != NodeType.atom) {
        econd.deinit(allocator);
        return EvalError.WrongExpressionType;
    }
    if (std.mem.eql(u8, econd.atom.raw.items, "true")) {
        econd.deinit(allocator);
        return try eval(ctx, allocator, node.sexpr.items[2]);
    } else if (std.mem.eql(u8, econd.atom.raw.items, "false")) {
        if (node.sexpr.items.len == 4) {
            econd.deinit(allocator);
            return try eval(ctx, allocator, node.sexpr.items[3]);
        }
    }
    econd.deinit(allocator);
    return EvalError.WrongExpressionType;
}

fn make_identifier(allocator: std.mem.Allocator, name: []const u8) !Node {
    return Node{ .atom = try Token.init_with_content(
        allocator,
        name,
        .identifier,
    ) };
}
