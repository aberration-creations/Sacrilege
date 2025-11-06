const std = @import("std");

const sac = @import("./internals/public.zig");
pub const builtin_empty = sac.builtin_empty;
pub const builtin_false = sac.builtin_false;
pub const builtin_true = sac.builtin_true;
pub const Context = sac.Context;
pub const eval = sac.eval;
pub const EvalError = sac.EvalError;
pub const internals = sac;
pub const Node = sac.Node;
pub const NodeType = sac.NodeType;
pub const parse = sac.parse;
pub const Token = sac.Token;
pub const Tokenizer = sac.Tokenizer;
pub const TokenType = sac.TokenType;

pub fn parseRawSource(raw: []const u8, allocator: std.mem.Allocator) !sac.Node {
    var tokenizer = sac.Tokenizer.init();
    defer tokenizer.deinit(allocator);
    try tokenizer.tokenize(allocator, raw);

    var ntokparsed: usize = 0;
    const node = try sac.parse(
        tokenizer.tokens.items,
        0,
        &ntokparsed,
        allocator,
    );
    return node;
}

test "example files run without errors" {
    try testRunFile("./examples/basic-expression.sac");
    try testRunFile("./examples/context-get-set.sac");
    try testRunFile("./examples/subroutine-call.sac");
    try testRunFile("./examples/math-expressions.sac");
    try testRunFile("./examples/lists-tests.sac");
    try testRunFile("./examples/lists-advanced-tests.sac");
    try testRunFile("./examples/predicates-tests.sac");
    try testRunFile("./examples/modules-tests.sac");
    try testRunFile("./examples/lambdas-tests.sac");
}

test "defun arity errors" {
    // double: expects 1
    try testExecutionError(
        "(defun double (x) (mult 2 x))\n(double)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 1 found 0",
    );
    try testExecutionError(
        "(defun double (x) (mult 2 x))\n(double 5 10)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 1 found 2",
    );

    // set-a: expects 0
    try testExecutionError(
        "(defun set-a () (set a 42))\n(set-a 42)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 0 found 1",
    );

    // add: expects 2
    try testExecutionError(
        "(defun add (x y) (sum x y))\n(add 5)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 2 found 1",
    );
    try testExecutionError(
        "(defun add (x y) (sum x y))\n(add 5 10 15)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 2 found 3",
    );

    // calculate: expects 3
    try testExecutionError(
        "(defun calculate (x y z) (sub (mult x y) z))\n(calculate 5)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 3 found 1",
    );
    try testExecutionError(
        "(defun calculate (x y z) (sub (mult x y) z))\n(calculate 5 3)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 3 found 2",
    );
    try testExecutionError(
        "(defun calculate (x y z) (sub (mult x y) z))\n(calculate 5 3 2 1)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 3 found 4",
    );

    // factorial: expects 1
    try testExecutionError(
        "(defun factorial (n) (if (eq n 0) 1 (mult n (factorial (sub n 1)))))\n(factorial)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 1 found 0",
    );
    try testExecutionError(
        "(defun factorial (n) (if (eq n 0) 1 (mult n (factorial (sub n 1)))))\n(factorial 5 10)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 1 found 2",
    );

    // max-of-three: expects 3
    try testExecutionError(
        "(defun max (a b) (if (gt a b) a b))\n(defun max-of-three (a b c) (max a (max b c)))\n(max-of-three 1 5)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 3 found 2",
    );
    try testExecutionError(
        "(defun max (a b) (if (gt a b) a b))\n(defun max-of-three (a b c) (max a (max b c)))\n(max-of-three 1 5 3 9)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 3 found 4",
    );

    // add-square: expects 2
    try testExecutionError(
        "(defun square (x) (mult x x))\n(defun add (x y) (sum x y))\n(defun add-square (x y) (add (square x) (square y)))\n(add-square 3)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 2 found 1",
    );
    try testExecutionError(
        "(defun square (x) (mult x x))\n(defun add (x y) (sum x y))\n(defun add-square (x y) (add (square x) (square y)))\n(add-square 3 4 5)",
        EvalError.WrongArgumentCount,
        "Wrong argument count expected 2 found 3",
    );
}

test "eval error UndefinedIdentifier" {
    try testExecutionError("(get a)", EvalError.UndefinedIdentifier, "Undefined identifier a");
}

test "eval error FunctionDoesNotExist" {
    try testExecutionError("(asdgasdg)", EvalError.FunctionDoesNotExist, "Function asdgasdg does not exist");
}

test "eval error WrongArgumentCount" {
    try testExecutionError("(assert 1 2 3 4)", EvalError.WrongArgumentCount, "Wrong argument count expected 1 found 4");
}

test "eval error sum miminum argument count" {
    try testExecutionError("(sum)", EvalError.WrongArgumentCount, "Wrong argument count sum expected at least 1 found 0");
}

test "eval error sum argument type" {
    try testExecutionError("(sum \"1\" \"2\")", EvalError.WrongArgumentType, "Wrong argument expected number found string");
}

test "eval error recursive eval not invalid argument" {
    try testExecutionError("(eval myfun)", EvalError.WrongArgumentType, "Wrong argument for eval index 0 expected expression found atom");
}

test "eval set not identifier" {
    try testExecutionError("(set 42 16)", EvalError.WrongArgumentType, "Wrong argument for set index 0 expected identifier found number");
}

test "no memory leak when same value is set twice" {
    const allocator = std.testing.allocator;
    var ctx = try testGetContextAfterRuningRaw("(set a 42)(set a 76)");
    defer ctx.deinit(allocator);
}

fn testExecutionError(source: []const u8, errorType: sac.EvalError, errorContent: []const u8) !void {
    const allocator = std.testing.allocator;
    var ctx = try testGetContextAfterRuningRaw(source);
    defer ctx.deinit(allocator);
    try std.testing.expectEqual(true, ctx.is_error);
    try std.testing.expectEqual(errorType, ctx.error_type);
    try std.testing.expectEqualStrings(errorContent, ctx.error_content);
}

fn testGetContextAfterRuningRaw(raw: []const u8) !sac.Context {
    const allocator = std.testing.allocator;
    var node = try parseRawSource(raw, allocator);
    defer node.deinit(allocator);

    var ctx = try sac.Context.init(allocator);
    errdefer ctx.deinit(allocator);

    if (sac.eval(&ctx, node)) |result| {
        result.deinit(ctx.pool_allocator);
    } else |err| {
        if (!ctx.is_error) {
            return err; // not an eval error
        }
    }

    return ctx;
}

fn testRunFile(comptime path: []const u8) !void {
    try testRunImpl(path, @embedFile(path));
}

fn testRunImpl(path: []const u8, raw: []const u8) !void {
    errdefer {
        std.debug.print("\x1b[1mfailed running: {s}\x1b[0m\n", .{path});
    }
    const allocator = std.testing.allocator;
    var node = try parseRawSource(raw, allocator);
    defer node.deinit(allocator);

    var ctx = try sac.Context.init(allocator);
    defer ctx.deinit(allocator);

    if (sac.eval(&ctx, node)) |*result| {
        result.deinit(ctx.pool_allocator);
    } else |err| {
        if (ctx.is_error) {
            ctx.debugPrintError(path);
            try std.testing.expectEqual(ctx.is_error, false);
        } else {
            return err; // not eval error, propagate it up to fail the test
        }
    }
}
