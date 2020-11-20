# PipelessPipes

Takes a start value and a `begin ... end` block of expressions, then pipes the result of each expression into the next one. Either, the position is specified by `_`, or it is implicitly the first argument.

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
