# PipelessPipes

> For pipes that get out of your way

## Summary

PipelessPipes defines the `@_` macro. It takes a start value and a `begin ... end` block of expressions.

The result of each expression is fed into the next one using one of two rules:

1. **There is at least one underscore in the expression**
  - every `_` is replaced with the result of the previous expression
2. **There is no underscore**
  - the result of the previous expression is used as the first argument in the current expression, as long as it is a function call or a symbol representing a function.

Lines that are prefaced with `@!` are executed, but their result is not fed into the next pipeline step.
This is very useful to inspect pipeline state during debugging, for example.

## Motivation

- The implicit first argument insertion is useful for many data pipeline scenarios, like `groupby`, `transform` and `combine` in DataFrames.jl
- The `_` syntax is there to either increase legibility or to use functions like `filter` or `map` which need the previous result as the second argument
- There is no need to type `|>` over and over
- Any line can be commented out or in without breaking syntax, there is no problem with dangling `|>` symbols
- The state of the pipeline can easily be checked with the `@!` macro
- The `begin ... end` block marks very clearly where the macro is applied and works well with auto-indentation

## Longer Explanation

An example with a DataFrame:

```julia
using DataFrames, PipelessPipes

df = DataFrame(group = [1, 2, 1, 2], weight = [1, 3, 5, 7])

result = @_ df begin
    filter(r -> r.weight < 6, _)
    groupby(:group)
    combine(:weight => sum => :total_weight)
end
```

The pipeless block is equivalent to this:

```julia
result = let
    var1 = filter(r -> r.weight < 6, df)
    var2 = groupby(var1, :group)
    var3 = combine(var2, :weight => sum => :total_weight)
end
```

For debugging, it's often useful to look at values in the middle of a pipeline.
You can use the `@!` macro to mark expressions that should not pass on their result.
For these expressions there is no implicit first argument spliced in if there is no `_`, because that would be impractical for most purposes.

If for example, we wanted to know how many groups were created after step 2, we could do this:

```julia
result = @_ df begin
    filter(r -> r.weight < 6, _)
    groupby(:group)
    @! println("There are $(length(_)) groups after step 2.")
    combine(:weight => sum => :total_weight)
end
```

Here is a list of equivalent expressions, where `_` is replaced by `prev` and the new variable is `next`.
In reality, each new variable simply gets a new name via `gensym`, which is guaranteed not to conflict with anything else.

| **Before** | **After** | **Comment** |
| :-- | :-- | :-- |
| `sum` | `next = sum(prev)` | Symbol gets expanded into function call |
| `sum(_)` | `next = sum(prev)` | Call expression gets `_` replaced |
| `_ + 3` | `next = prev + 3` | Infix call expressions work the same way as other calls |
| `+(3)` | `next = prev + 3` | Infix notation with _ would look better, but this is also possible |
| `1 + 2` | `next = prev + 1 + 2` | This might feel weird, but `1 + 2` is a normal call expression |
| `filter(isodd, _)` | `next = filter(isodd, prev)` | Underscore can go anywhere |
| `@! println(_)` | `println(prev)` | `println` without affecting the pipeline; using `_` |
| `@! println("hello")` | `println("hello")` | `println` without affecting the pipeline; no implicit first arg |
