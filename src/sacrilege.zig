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

test "basic expression evaluation" {
    try testEvalValue("(sum (sum 30 30) 2)", 62);
}

test "context get and set" {
    try testEvalValue("(set a 10)(set b 32)(set c (sum (get a) (get b)))(get c)", 42);
}

test "math expressions sum" {
    try testEvalValue("(sum 13)", 13);
    try testEvalValue("(sum 27 3)", 30);
    try testEvalValue("(sum 0 1 2 3 4)", 10);
}

test "math expressions sub" {
    try testEvalValue("(sub 10)", 10);
    try testEvalValue("(sub 100 4)", 96);
    try testEvalValue("(sub 100 10 20)", 70);
}

test "math expressions mult" {
    try testEvalValue("(mult 10)", 10);
    try testEvalValue("(mult 3 4)", 12);
    try testEvalValue("(mult 3 4 5)", 60);
}

test "math expressions div" {
    try testEvalValue("(div 10)", 10);
    try testEvalValue("(div 10 2)", 5);
    try testEvalValue("(div 100 2 2)", 25);
}

test "defun basic function" {
    try testEvalValue("(defun double (x) (mult 2 x))(double 5)", 10);
    try testEvalValue("(defun double (x) (mult 2 x))(double 10)", 20);
}

test "defun function composition" {
    const source = "(defun square (x) (mult x x))\n(defun add (x y) (sum x y))\n(defun add-square (x y) (add (square x) (square y)))\n(add-square 3 4)";
    try testEvalValue(source, 25);
}

test "defun recursive factorial" {
    const source = "(defun factorial (n) (if (eq n 0) 1 (mult n (factorial (sub n 1)))))\n(factorial 0)";
    try testEvalValue(source, 1);

    const source2 = "(defun factorial (n) (if (eq n 0) 1 (mult n (factorial (sub n 1)))))\n(factorial 5)";
    try testEvalValue(source2, 120);
}

test "defun nested function calls" {
    const source = "(defun max (a b) (if (gt a b) a b))\n(defun min (a b) (if (lt a b) a b))\n(defun max-of-three (a b c) (max a (max b c)))\n(max-of-three 1 5 3)";
    try testEvalValue(source, 5);

    const source2 = "(defun max (a b) (if (gt a b) a b))\n(defun min (a b) (if (lt a b) a b))\n(defun min-of-three (a b c) (min a (min b c)))\n(min-of-three 1 5 3)";
    try testEvalValue(source2, 1);
}

test "defun function with multiple steps" {
    const source = "(defun triple (x) (mult 3 x))\n(defun add-one (x) (sum x 1))\n(defun triple-then-add-one (x) (add-one (triple x)))\n(triple-then-add-one 5)";
    try testEvalValue(source, 16);

    const source2 = "(defun square (x) (mult x x))\n(defun square-then-double (x) (mult 2 (square x)))\n(square-then-double 3)";
    try testEvalValue(source2, 18);

    const source3 = "(defun square (x) (mult x x))\n(defun double-then-square (x) (square (mult 2 x)))\n(double-then-square 3)";
    try testEvalValue(source3, 36);
}

test "defun calculate with multiple parameters" {
    const source = "(defun multiply (a b) (mult a b))\n(defun subtract (a b) (sub a b))\n(defun calculate (x y z) (subtract (multiply x y) z))\n(calculate 5 3 2)";
    try testEvalValue(source, 13);
}

test "defun distance function" {
    const source = "(defun abs (x) (if (lt x 0) (sub 0 x) x))\n(defun distance (a b) (abs (sub a b)))\n(distance 5 2)";
    try testEvalValue(source, 3);

    const source2 = "(defun abs (x) (if (lt x 0) (sub 0 x) x))\n(defun distance (a b) (abs (sub a b)))\n(distance 2 5)";
    try testEvalValue(source2, 3);
}

test "lists basic operations" {
    try testEvalValue("(len (list))", 0);
    try testEvalValue("(len (list 1 2 3))", 3);
    try testEvalValue("(car (list 10 20 30))", 10);
    try testEvalValue("(elem 2 (list 10 20 30))", 20);
    try testEvalValue("(last (list 10 20 30))", 30);
}

test "lists cons operation" {
    try testEvalValue("(car (cons 1 (list 2 3)))", 1);
    try testEvalValue("(len (cons 1 (list 2 3)))", 3);
    try testEvalValue("(elem 2 (cons 1 (list 2 3)))", 2);
}

test "lists append operation" {
    try testEvalValue("(len (append (list 1 2) 3 4))", 4);
    try testEvalValue("(car (append (list 1 2) 3 4))", 1);
    try testEvalValue("(last (append (list 1 2) 3 4))", 4);
}

test "lists nested lists" {
    const source = "(defun make-nested () (list (list 1 2) (list 3 (list 4 5))))\n(len (make-nested))";
    try testEvalValue(source, 2);

    const source2 = "(defun make-nested () (list (list 1 2) (list 3 (list 4 5))))\n(len (car (make-nested)))";
    try testEvalValue(source2, 2);
}

test "lists empty predicate" {
    try testEvalBool("(empty? (list))", true);
    try testEvalBool("(empty? (list 1))", false);
}

test "lists cdr operation" {
    try testEvalValue("(car (cdr (list 9 8 7)))", 8);
    try testEvalValue("(len (cdr (list 9 8 7)))", 2);
}

test "lists advanced operations" {
    try testEvalBool("(null? (list))", true);
    try testEvalBool("(empty? (list))", true);
    try testEvalBool("(list? (list 1 2))", true);
    try testEvalBool("(pair? (list 1 2))", true);
    try testEvalBool("(pair? (list))", false);
}

test "lists advanced length" {
    try testEvalValue("(length (list))", 0);
    try testEvalValue("(length (list 1 2 3 4))", 4);
}

test "lists advanced list-ref" {
    try testEvalValue("(list-ref (list 10 20 30) 0)", 10);
    try testEvalValue("(list-ref (list 10 20 30) 2)", 30);
}

test "lists advanced list-tail" {
    try testEvalValue("(car (list-tail (list 1 2 3 4) 2))", 3);
    try testEvalValue("(length (list-tail (list 1 2 3 4) 4))", 0);
}

test "lists advanced reverse" {
    try testEvalValue("(car (reverse (list 1 2 3)))", 3);
    try testEvalValue("(last (reverse (list 1 2 3)))", 1);
}

test "lists advanced list-star" {
    // list* should work similarly to list - test by checking operations on the result
    try testEvalValue("(car (list* 1 2 (list 3 4)))", 1);
    try testEvalValue("(elem 2 (list* 1 2 (list 3 4)))", 2);
    try testEvalValue("(last (list* 1 2 (list 3 4)))", 4);
    try testEvalValue("(len (list* 1 2 (list 3 4)))", 4);
}

test "lists with strings basic operations" {
    try testEvalString("(car (list \"hello\" \"world\" \"test\"))", "hello");
    try testEvalString("(elem 2 (list \"hello\" \"world\" \"test\"))", "world");
    try testEvalString("(last (list \"hello\" \"world\" \"test\"))", "test");
    try testEvalValue("(len (list \"hello\" \"world\" \"test\"))", 3);
}

test "lists with strings cons and append" {
    try testEvalString("(car (cons \"first\" (list \"second\" \"third\")))", "first");
    try testEvalString("(last (append (list \"a\" \"b\") \"c\" \"d\"))", "d");
    try testEvalString("(car (append (list \"a\" \"b\") \"c\" \"d\"))", "a");
    try testEvalValue("(len (append (list \"x\" \"y\") \"z\"))", 3);
}

test "lists with strings mixed types" {
    try testEvalString("(car (list \"hello\" 42 \"world\"))", "hello");
    try testEvalValue("(elem 2 (list \"hello\" 42 \"world\"))", 42);
    try testEvalString("(last (list \"hello\" 42 \"world\"))", "world");
}

test "lists with strings advanced operations" {
    try testEvalString("(list-ref (list \"zero\" \"one\" \"two\") 0)", "zero");
    try testEvalString("(list-ref (list \"zero\" \"one\" \"two\") 2)", "two");
    try testEvalString("(car (list-tail (list \"a\" \"b\" \"c\" \"d\") 2))", "c");
    try testEvalString("(car (reverse (list \"first\" \"second\" \"third\")))", "third");
    try testEvalString("(last (reverse (list \"first\" \"second\" \"third\")))", "first");
}

test "lists with strings predicates" {
    try testEvalBool("(empty? (list))", true);
    try testEvalBool("(empty? (list \"item\"))", false);
    try testEvalBool("(list? (list \"a\" \"b\"))", true);
    try testEvalBool("(pair? (list \"a\" \"b\"))", true);
    try testEvalBool("(pair? (list))", false);
}

test "lists with strings equality" {
    try testEvalBool("(eq (car (list \"test\")) \"test\")", true);
    try testEvalBool("(eq (car (list \"hello\")) \"world\")", false);
    try testEvalBool("(eq (elem 3 (list \"a\" \"b\" \"c\")) \"c\")", true);
}

test "predicates boolean operations" {
    try testEvalBool("(not true)", false);
    try testEvalBool("(not false)", true);
    try testEvalBool("(and true true)", true);
    try testEvalBool("(and true false)", false);
    try testEvalBool("(or false false)", false);
    try testEvalBool("(or true false)", true);
}

test "predicates numeric comparisons" {
    try testEvalBool("(lt 1 2)", true);
    try testEvalBool("(lt 2 1)", false);
    try testEvalBool("(gt 5 3)", true);
    try testEvalBool("(gt 3 5)", false);
    try testEvalBool("(eq 10 10)", true);
    try testEvalBool("(eq 10 11)", false);
}

test "predicates user-defined predicates" {
    const source = "(defun zero? (n) (eq n 0))\n(zero? 0)";
    try testEvalBool(source, true);

    const source2 = "(defun zero? (n) (eq n 0))\n(zero? 1)";
    try testEvalBool(source2, false);
}

test "predicates even and odd" {
    const source = "(defun mod (n d) (sub n (mult d (div n d))))\n(defun even? (n) (eq (mod n 2) 0))\n(even? 4)";
    try testEvalBool(source, true);

    const source2 = "(defun mod (n d) (sub n (mult d (div n d))))\n(defun even? (n) (eq (mod n 2) 0))\n(even? 5)";
    try testEvalBool(source2, false);

    const source3 = "(defun mod (n d) (sub n (mult d (div n d))))\n(defun even? (n) (eq (mod n 2) 0))\n(defun odd? (n) (not (even? n)))\n(odd? 5)";
    try testEvalBool(source3, true);

    const source4 = "(defun mod (n d) (sub n (mult d (div n d))))\n(defun even? (n) (eq (mod n 2) 0))\n(defun odd? (n) (not (even? n)))\n(odd? 4)";
    try testEvalBool(source4, false);
}

test "predicates between predicate" {
    const source = "(defun between? (x lo hi) (and (lt lo x) (lt x hi)))\n(between? 5 1 10)";
    try testEvalBool(source, true);

    const source2 = "(defun between? (x lo hi) (and (lt lo x) (lt x hi)))\n(between? 1 1 10)";
    try testEvalBool(source2, false);
}

test "lambdas basic application" {
    try testEvalValue("((lambda (x) (sum x 1)) 5)", 6);
    try testEvalValue("((lambda (x y) (sum x y)) 3 4)", 7);
}

test "lambdas closures capture by value" {
    const source = "(set a 10)\n(set inc-a (lambda (x) (sum a x)))\n(inc-a 5)";
    try testEvalValue(source, 15);

    // After changing a, the closure should still use the captured value
    const source2 = "(set a 10)\n(set inc-a (lambda (x) (sum a x)))\n(set a 100)\n(inc-a 5)";
    try testEvalValue(source2, 15);
}

test "lambdas higher-order usage" {
    const source = "(defun apply (f x) (f x))\n(apply (lambda (z) (sum z 2)) 5)";
    try testEvalValue(source, 7);
}

test "lambdas returning lambdas" {
    const source = "(defun make-adder (n) (lambda (x) (sum x n)))\n((make-adder 3) 4)";
    try testEvalValue(source, 7);
}

test "lambdas composition" {
    const source = "(set inc (lambda (x) (sum x 1)))\n(set double (lambda (x) (mult 2 x)))\n(set inc-then-double (lambda (x) (double (inc x))))\n(inc-then-double 5)";
    try testEvalValue(source, 12);
}

test "subroutine call with eval" {
    const source = "(set a 13)\n(defun myfun (set a 42))\n(get a)";
    try testEvalValue(source, 13);

    const source2 = "(set a 13)\n(defun myfun (set a 42))\n(eval (get myfun))\n(get a)";
    try testEvalValue(source2, 42);
}

fn testEvalValue(source: []const u8, expected: i128) !void {
    const allocator = std.testing.allocator;
    var node = try parseRawSource(source, allocator);
    defer node.deinit(allocator);

    var ctx = try sac.Context.init(allocator);
    defer ctx.deinit(allocator);

    // Handle multiple top-level expressions by evaluating each and returning the last
    var result: sac.Node = undefined;
    var have_result = false;
    if (node == .sexpr and node.sexpr.items.len > 0) {
        // Check if this is a function call (first item is an identifier atom)
        const first = node.sexpr.items[0];
        const is_function_call = first == .atom and first.atom.id == .identifier;

        if (!is_function_call) {
            // Multiple top-level expressions - evaluate each sequentially
            for (node.sexpr.items) |form| {
                if (have_result) {
                    result.deinit(ctx.pool_allocator);
                } else {
                    have_result = true;
                }
                result = try sac.eval(&ctx, form);
            }
        } else {
            // Single function call
            result = try sac.eval(&ctx, node);
            have_result = true;
        }
    } else {
        // Single expression
        result = try sac.eval(&ctx, node);
        have_result = true;
    }
    defer if (have_result) result.deinit(ctx.pool_allocator);

    try std.testing.expect(result == .atom);
    try std.testing.expectEqual(sac.TokenType.number, result.atom.id);
    const value = try std.fmt.parseInt(i128, result.atom.raw.items, 10);
    try std.testing.expectEqual(expected, value);
}

fn testEvalBool(source: []const u8, expected: bool) !void {
    const allocator = std.testing.allocator;
    var node = try parseRawSource(source, allocator);
    defer node.deinit(allocator);

    var ctx = try sac.Context.init(allocator);
    defer ctx.deinit(allocator);

    // Handle multiple top-level expressions by evaluating each and returning the last
    var result: sac.Node = undefined;
    var have_result = false;
    if (node == .sexpr and node.sexpr.items.len > 0) {
        // Check if this is a function call (first item is an identifier atom)
        const first = node.sexpr.items[0];
        const is_function_call = first == .atom and first.atom.id == .identifier;

        if (!is_function_call) {
            // Multiple top-level expressions - evaluate each sequentially
            for (node.sexpr.items) |form| {
                if (have_result) {
                    result.deinit(ctx.pool_allocator);
                } else {
                    have_result = true;
                }
                result = try sac.eval(&ctx, form);
            }
        } else {
            // Single function call
            result = try sac.eval(&ctx, node);
            have_result = true;
        }
    } else {
        // Single expression
        result = try sac.eval(&ctx, node);
        have_result = true;
    }
    defer if (have_result) result.deinit(ctx.pool_allocator);

    // Boolean values are returned as identifier atoms
    try std.testing.expect(result == .atom);
    try std.testing.expectEqual(sac.TokenType.identifier, result.atom.id);

    const bool_str = result.atom.raw.items;
    if (expected) {
        try std.testing.expectEqualStrings("true", bool_str);
    } else {
        try std.testing.expectEqualStrings("false", bool_str);
    }
}

fn testEvalString(source: []const u8, expected: []const u8) !void {
    const allocator = std.testing.allocator;
    var node = try parseRawSource(source, allocator);
    defer node.deinit(allocator);

    var ctx = try sac.Context.init(allocator);
    defer ctx.deinit(allocator);

    // Handle multiple top-level expressions by evaluating each and returning the last
    var result: sac.Node = undefined;
    var have_result = false;
    if (node == .sexpr and node.sexpr.items.len > 0) {
        // Check if this is a function call (first item is an identifier atom)
        const first = node.sexpr.items[0];
        const is_function_call = first == .atom and first.atom.id == .identifier;

        if (!is_function_call) {
            // Multiple top-level expressions - evaluate each sequentially
            for (node.sexpr.items) |form| {
                if (have_result) {
                    result.deinit(ctx.pool_allocator);
                } else {
                    have_result = true;
                }
                result = try sac.eval(&ctx, form);
            }
        } else {
            // Single function call
            result = try sac.eval(&ctx, node);
            have_result = true;
        }
    } else {
        // Single expression
        result = try sac.eval(&ctx, node);
        have_result = true;
    }
    defer if (have_result) result.deinit(ctx.pool_allocator);

    // String values are returned as string atoms
    try std.testing.expect(result == .atom);
    try std.testing.expectEqual(sac.TokenType.string, result.atom.id);

    const actual_str = result.atom.raw.items;
    try std.testing.expectEqualStrings(expected, actual_str);
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
