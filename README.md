# Sacrilege

Sacrilege is a small, embeddable, Lisp-like language implemented in Zig (0.15.2). It features s-expressions, a growing standard library of list and numeric operations, lexical closures via `lambda`, user-defined functions with tail-call optimization, and simple module/file loading.

This repository includes a test suite and example `.sac` programs showcasing language features.

## Quick start

- Prerequisites: Zig 0.15.2
- Run tests (executes all embedded examples):

```bash
zig test src/sacrilege.zig
```

## Language at a glance

- Programs are made of s-expressions: `(operator arg1 arg2 ...)`
- Atoms include: identifiers, numbers, and strings
- Truth values are identifiers `true` and `false`
- Lists are just s-expressions used as data, e.g. `(list 1 2 3)`
- Variables: `(set name expr)` and `(get name)`
- Functions: `(defun name (params...) body...)` and anonymous `(lambda (params...) body...)`
- Control flow: `(if cond then-expr [else-expr])` (lazy evaluation)
- Files/modules: `(evalfile "path")`, `(include "path")`, `(require "path")`

See `docs/Language.md` for the full tour and `docs/Builtins.md` for the built-in API.

## Examples

Basic arithmetic and lists:

```lisp
(sum 1 2 3)           ; => 6
(mult 2 3 4)          ; => 24
(list 1 2 3)          ; => (1 2 3)
(car (list 10 20 30)) ; => 10
(cdr (list 10 20 30)) ; => (20 30)
```

Functions and closures:

```lisp
(defun add (x y) (sum x y))
(add 3 4) ; => 7

(set a 10)
(set inc-a (lambda (x) (sum a x)))
(inc-a 5) ; => 15  ; captured value of a
(set a 100)
(inc-a 5) ; => 15  ; still uses captured 10
```

Higher-order and composition:

```lisp
(set inc   (lambda (x) (sum x 1)))
(set double (lambda (x) (mult 2 x)))
(set inc-then-double (lambda (x) (double (inc x))))
(inc-then-double 5) ; => 12
```

Conditional (lazy):

```lisp
(if (eq 1 1) (print "equal") (print "nope"))
```

Modules/files:

```lisp
(include "src/examples/lib/math-lib.sac")
(require "src/examples/lib/nested-lib.sac")
```

More runnable snippets are collected in `docs/Examples.md`, and you can find the full set of test examples under `src/examples/`.

## Implementation notes

- Eager evaluation by default; selective lazy forms: `if`, `foreach`, `defun`, `lambda`, `set`, `get`
- User-defined functions benefit from tail-call optimization for self-recursive final calls
- Lambdas are closed over by value; free identifiers are captured at definition time
- Anonymous functions are assigned unique names per-context (e.g. `__lambda_<ctx>_<n>`) to avoid collisions

## Developing

- Run all tests:

```bash
zig test src/sacrilege.zig -freference-trace
```

- Explore internals:
  - Evaluator: `src/internals/eval.zig`
  - Built-ins: `src/internals/builtins.zig`
  - Context: `src/internals/context.zig`
  - Lexer/Parser: `src/internals/lexer.zig`, `src/internals/parser.zig`, `src/internals/node.zig`

## Performance tests

Build and run the standalone benchmark runner:

```bash
zig build-exe -OReleaseFast src/bench.zig -femit-bin=./bench && ./bench
```

It reports ns/op for a set of micro and file-level benchmarks, measuring both parse+eval and eval-only.
