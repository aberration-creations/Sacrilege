## Built-ins

This lists the current built-in functions and lazy forms registered by `registerBuiltins`.

### Lazy forms

- `(if cond then [else])`
- `(foreach f (list ...))` — apply function `f` to each element of list
- `(defun name (params...) body...)`
- `(lambda (params...) body...)`
- `(set name expr)`
- `(get name)`

### Assertions

- `(assert x)` — expects `x` to be `true`

### Numeric

- `(sum a b ...)` — at least 1 argument
- `(sub a [b ...])`
- `(mult a [b ...])`
- `(div a [b ...])` — floor division
- `(eq a b)`
- `(lt a b)`
- `(gt a b)`

### Boolean

- `(and a b ...)`
- `(or a b ...)`
- `(not a)`

### Output

- `(print "str" ...)` — prints atoms separated by spaces and newline

### Variables

- `(set name expr)` — stores evaluated value under `name`
- `(get name)` — retrieves stored value

### Lists

- `(list a b c ...)`
- `(cons x xs)`
- `(len xs)` / `(length xs)`
- `(car xs)`
- `(cdr xs)`
- `(elem n xs)` — 1-based index
- `(last xs)`
- `(append xs item1 item2 ...)` — appends items to list
- `(reverse xs)`
- `(list* a b ... last)` — like Scheme `list*`
- `(empty xs)` / `(empty? xs)` / `(null? xs)`
- `(list? x)`
- `(pair? x)` — non-empty list
- `(list-ref xs i)` — 0-based index
- `(list-tail xs n)` — drop first `n` elements

### Files and parsing

- `(readfile "path")` — returns file content (string)
- `(evalfile "path")` — evaluates all forms in file; returns last value
- `(include "path")` — alias for `evalfile`
- `(require "path")` — evaluate file once; no-op if already loaded
- `(parse "source")` — returns parsed syntax tree value

### Notes

- Booleans are identifiers `true` and `false`.
- Functions may return lists or atoms; evaluators generally expect the right node type and error otherwise.


