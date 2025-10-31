const std = @import("std");

const sac = @import("./public.zig");
const Node = sac.Node;
const EvalError = sac.EvalError;
const Token = sac.Token;
const TokenType = sac.TokenType;
const NodeType = sac.NodeType;

pub const Func = fn (*Context, std.mem.Allocator, Node) anyerror!Node;

var context_id_counter: u32 = 0;

pub const Context = struct {
    const Self = @This();

    funcs: std.StringHashMap(*const Func),
    lazy_funcs: std.StringHashMap(*const Func),
    ids: std.StringHashMap(Node),
    strings: std.ArrayList(std.ArrayList(u8)),

    context_id: u32 = 0,
    is_error: bool = false,
    error_type: EvalError = undefined,
    error_line: u32 = undefined,
    error_column: u32 = undefined,
    error_content: []u8 = undefined,
    error_buffer: [256]u8 = undefined,

    pub fn deinit(
        self: *Self,
    ) void {
        var keys = self.ids.keyIterator();
        while (keys.next()) |key| {
            if (self.ids.get(key.*)) |node| {
                node.deinit();
            }
        }
        for (self.strings.items) |str| {
            str.deinit();
        }
        self.strings.deinit();
        self.funcs.clearAndFree();
        self.lazy_funcs.clearAndFree();
        self.ids.clearAndFree();
        self.funcs.deinit();
        self.lazy_funcs.deinit();
        self.ids.deinit();
    }

    pub fn init(allocator: std.mem.Allocator) !Self {
        context_id_counter += 1;
        var ctx = Self{
            .funcs = std.StringHashMap(*const Func).init(allocator),
            .lazy_funcs = std.StringHashMap(*const Func).init(allocator),
            .ids = std.StringHashMap(Node).init(allocator),
            .strings = std.ArrayList(std.ArrayList(u8)).empty,
            .context_id = context_id_counter,
        };
        errdefer ctx.deinit();
        try sac.registerBuiltins(&ctx);
        return ctx;
    }

    pub fn register_func(self: *Self, name: []const u8, func: *const Func) !void {
        try self.funcs.put(name, func);
    }

    pub fn ensure_argument_count(self: *Self, node: Node, expected_count: u32) !void {
        if (node.sexpr.items.len - 1 != expected_count) {
            return self.raise_wrong_argument_count(node, expected_count);
        }
    }

    pub fn ensure_argument_count_at_least(self: *Self, node: Node, minCount: u32) !void {
        const argCount = node.sexpr.items.len - 1;
        const fnNameToken = node.sexpr.items[0].atom;
        if (argCount < minCount) {
            return self.raise_error(EvalError.WrongArgumentCount, node.findFirstToken(), "Wrong argument count {s} expected at least {} found {}", .{ fnNameToken.raw.items, minCount, argCount });
        }
    }

    pub fn ensure_argument_nodetype(self: *Self, node: Node, index: u32, expected: NodeType) !void {
        const arg = node.sexpr.items[index + 1];
        const fnNameToken = node.sexpr.items[0].atom;
        if (arg != expected) {
            const nodetype: NodeType = arg;
            return self.raise_error(EvalError.WrongArgumentType, arg.findFirstToken(), "Wrong argument for {s} index {} expected {s} found {s}", .{ fnNameToken.raw.items, index, expected.getTypeString(), nodetype.getTypeString() });
        }
    }

    pub fn ensure_argument_tokentype(self: *Self, node: Node, index: u32, expected: TokenType) !void {
        const arg = node.sexpr.items[index + 1];
        const fnNameToken = node.sexpr.items[0].atom;
        if (arg != NodeType.atom) {
            const nodetype: NodeType = arg;
            return self.raise_error(EvalError.WrongArgumentType, arg.findFirstToken(), "Wrong argument for {s} index {} expected {s} found {s}", .{ fnNameToken.raw.items, index, expected.getTypeString(), nodetype.getTypeString() });
        }
        if (arg.atom.id != expected) {
            return self.raise_error(EvalError.WrongArgumentType, arg.findFirstToken(), "Wrong argument for {s} index {} expected {s} found {s}", .{ fnNameToken.raw.items, index, expected.getTypeString(), arg.atom.id.getTypeString() });
        }
    }

    pub fn raise_wrong_argument_count(self: *Self, node: Node, expected_count: u32) anyerror {
        const token = node.sexpr.items[0].atom;
        return self.raise_error(EvalError.WrongArgumentCount, token, "Wrong argument count expected {} found {}", .{ expected_count, node.sexpr.items.len - 1 });
    }

    pub fn raise_wrong_argument_node_type(self: *Self, node: Node, expected_type: TokenType) anyerror {
        const token = node.sexpr.items[0].atom;
        return self.raise_error(EvalError.WrongArgumentType, token, "Wrong argument type expected \"{s}\"", .{expected_type.getTypeString()});
    }

    pub fn ensure_node_datatype(self: *Self, node: Node, expected: TokenType) !void {
        if (node != NodeType.atom) {
            const nodetype: NodeType = node;
            return self.raise_error(EvalError.WrongArgumentType, node.findFirstToken(), "Wrong argument expected {s} found {s}", .{ expected.getTypeString(), nodetype.getTypeString() });
        }
        if (node.atom.id != expected) {
            return self.raise_error(EvalError.WrongArgumentType, node.findFirstToken(), "Wrong argument expected {s} found {s}", .{ expected.getTypeString(), node.atom.id.getTypeString() });
        }
    }

    pub fn raise_wrong_argument_token_type(self: *Self, token: Token, expected_type: TokenType) anyerror {
        return self.raise_error(EvalError.WrongArgumentType, token, "Wrong argument type expected {s} found {s}", .{ expected_type.getTypeString(), token.id.getTypeString() });
    }

    pub fn raise_undefined_indentifier(self: *Self, token: Token) anyerror {
        return self.raise_error(EvalError.UndefinedIdentifier, token, "Undefined identifier {s}", .{token.raw.items});
    }

    pub fn raise_function_does_not_exists(self: *Self, token: Token) anyerror {
        return self.raise_error(EvalError.FunctionDoesNotExist, token, "Function {s} does not exist", .{token.raw.items});
    }

    pub fn raise_error(self: *Self, etype: EvalError, at: Token, comptime format: []const u8, args: anytype) anyerror {
        self.is_error = true;
        self.error_type = etype;
        self.error_line = at.pos.line;
        self.error_column = at.pos.char;
        self.error_content = try std.fmt.bufPrint(&self.error_buffer, format, args);
        return etype;
    }

    pub fn debugPrintError(ctx: Context, sourcepath: []const u8) void {
        if (ctx.is_error) {
            var content: []const u8 = ctx.error_content;
            if (ctx.error_content.len > 256) {
                // if error_content is corrupted, try to restore it
                content = &ctx.error_buffer;
            }
            std.debug.print("\x1b[1m{s}:{}:{}: \x1b[31merror:\x1b[0;1m {s}\x1b[0m\n", .{ sourcepath, ctx.error_line, ctx.error_column, content });
        }
    }
};
