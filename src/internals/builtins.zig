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
    try ctx.lazy_funcs.put("defun", &builtin_set);

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

    try ctx.funcs.put("set", &builtin_set);
    try ctx.funcs.put("get", &builtin_get);

    try ctx.funcs.put("len", &builtin_len);
    try ctx.funcs.put("car", &builtin_car);
    try ctx.funcs.put("cdr", &builtin_cdr);
    try ctx.funcs.put("elem", &builtin_elem);
    try ctx.funcs.put("last", &builtin_last);
    try ctx.funcs.put("append", &builtin_append);

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
    return builtin_empty(allocator);
}

fn builtin_set(ctx: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    try ctx.ensure_argument_count(node, 2);
    try ctx.ensure_argument_tokentype(node, 0, TokenType.identifier);
    const key = try node.sexpr.items[1].atom.raw.clone(allocator);
    const value = try node.sexpr.items[2].copy(allocator);
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

fn builtin_car(_: *Context, _: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items[1].sexpr.items.len < 1) {
        return EvalError.WrongArgumentCount;
    }
    return node.sexpr.items[1].sexpr.items[0];
}

fn builtin_elem(ctx: *Context, _: std.mem.Allocator, node: Node) anyerror!Node {
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
    return node.sexpr.items[2].sexpr.items[nr];
}

fn builtin_last(_: *Context, _: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    const sl = node.sexpr.items[1].sexpr.items.len;
    if (sl == 0) {
        return EvalError.WrongArgumentType;
    }
    return node.sexpr.items[1].sexpr.items[sl - 1];
}

fn builtin_append(_: *Context, allocator: std.mem.Allocator, node: Node) anyerror!Node {
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items.len < 3) {
        return EvalError.WrongArgumentCount;
    }
    var nl = node.sexpr.items[1]; // TODO arraylist clone?
    for (node.sexpr.items[2..]) |item| {
        try nl.sexpr.append(allocator, item);
    }
    return nl;
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

fn builtin_cdr(_: *Context, _: std.mem.Allocator, node: Node) anyerror!Node {
    // TODO check argument counts
    if (node.sexpr.items[1] != NodeType.sexpr) {
        return EvalError.WrongArgumentType;
    }
    if (node.sexpr.items.len == 0) {
        return EvalError.WrongArgumentCount;
    }
    var nl = node.sexpr.items[1]; // TODO arraylist clone?
    _ = nl.sexpr.orderedRemove(0);
    return nl;
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
        return EvalError.WrongExpressionType;
    }
    if (std.mem.eql(u8, econd.atom.raw.items, "true")) {
        return try eval(ctx, allocator, node.sexpr.items[2]);
    } else if (std.mem.eql(u8, econd.atom.raw.items, "false")) {
        if (node.sexpr.items.len == 4) {
            return try eval(ctx, allocator, node.sexpr.items[3]);
        }
    }
    return EvalError.WrongExpressionType;
}

fn make_identifier(allocator: std.mem.Allocator, name: []const u8) !Node {
    return Node{ .atom = try Token.init_with_content(
        allocator,
        name,
        .identifier,
    ) };
}
