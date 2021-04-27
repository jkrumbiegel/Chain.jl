# Chain.jl

A [Julia package](https://julialang.org/packages/) for piping a value through a series of transformation expressions using a more convenient syntax than Julia's native [piping functionality](https://docs.julialang.org/en/v1/manual/functions/#Function-composition-and-piping).

<table>
<tr><th>Chain.jl</th><th>Base Julia</th></tr>
<tr>
<td>
      
```julia
@chain df begin
  dropmissing
  groupby(:group)
  combine(:age => sum, :wage => sum)
  lm(@formula(wage_sum ~ age_sum), _)
end
```

</td>
<td>

```julia
df |>
  dropmissing |>
  x -> groupby(x, :group) |>
  x -> combine(x, :age => sum, :wage => sum) |>
  x -> lm(@formula(wage_sum ~ age_sum), x)
```

</td>
</tr>
<tr>
<th><a href="https://github.com/oxinabox/Pipe.jl">Pipe.jl</a></th>
<th><a href="https://github.com/MikeInnes/Lazy.jl">Lazy.jl</a></th>
</tr>
<tr>
<td>
  
```julia
@pipe df |>
  dropmissing |>
  groupby(_, :group) |>
  combine(_, :age => sum, :wage => sum) |>
  lm(@formula(wage_sum ~ age_sum), _)
```

</td>
<td>
		
```julia
@> df begin
  dropmissing
  groupby(:group)
  combine(:age => sum, :wage => sum)
  x -> lm(@formula(wage_sum ~ age_sum), x)
end
```

</td>
</tr>
</tr>
</table>

## Build Status

![Run tests](https://github.com/jkrumbiegel/Chain.jl/workflows/Run%20tests/badge.svg)

## Summary

Chain.jl defines the `@chain` macro. It takes a start value and a `begin ... end` block of expressions.

The result of each expression is fed into the next one using one of two rules:

1. **There is at least one underscore in the expression**
  - every `_` is replaced with the result of the previous expression
2. **There is no underscore**
  - the result of the previous expression is used as the first argument in the current expression, as long as it is a function call, a macro call or a symbol representing a function.

Lines that are prefaced with `@aside` are executed, but their result is not fed into the next pipeline step.
This is very useful to inspect pipeline state during debugging, for example.

## Motivation

- The implicit first argument insertion is useful for many data pipeline scenarios, like `groupby`, `transform` and `combine` in DataFrames.jl
- The `_` syntax is there to either increase legibility or to use functions like `filter` or `map` which need the previous result as the second argument
- There is no need to type `|>` over and over
- Any line can be commented out or in without breaking syntax, there is no problem with dangling `|>` symbols
- The state of the pipeline can easily be checked with the `@aside` macro
- The `begin ... end` block marks very clearly where the macro is applied and works well with auto-indentation
- Because everything is just lines with separate expressions and not one huge function call, IDEs can show exactly in which line errors happened
- Pipe is a name defined by Base Julia which can lead to conflicts

## Example

An example with a DataFrame:

```julia
using DataFrames, Chain

df = DataFrame(group = [1, 2, 1, 2, missing], weight = [1, 3, 5, 7, missing])

result = @chain df begin
    dropmissing
    subset(:weight => ByRow(<(6)))
    groupby(:group)
    combine(:weight => sum => :total_weight)
end
```

The pipeless block is equivalent to this:

```julia
result = let
    var1 = dropmissing(df)
    var2 = subset(var1, :weight => ByRow(<(6)))
    var3 = groupby(var2, :group)
    var4 = combine(var3, :weight => sum => :total_weight)
end
```

## Alternative one-argument syntax

If your initial argument name is long and / or the chain's result is assigned to a long variable, it can look cleaner if the initial value is moved into the chain.
Here is such a long expression:

```julia
a_long_result_variable_name = @chain a_long_input_variable_name begin
    do_something
	do_something_else(parameter)
    do_other_thing(parameter, _)
end
```

This is equivalent to the following expression:

```julia
a_long_result_variable_name = @chain begin
    a_long_input_variable_name
    do_something
	do_something_else(parameter)
    do_other_thing(parameter, _)
end
```

## One-liner syntax

You can also use `@chain` as a one-liner, where no begin-end block is necessary.
This works well for short sequences that are still easy to parse visually without being on separate lines.

```julia
@chain 1:10 filter(isodd, _) sum sqrt
```

## The `@aside` macro

For debugging, it's often useful to look at values in the middle of a pipeline.
You can use the `@aside` macro to mark expressions that should not pass on their result.
For these expressions there is no implicit first argument spliced in if there is no `_`, because that would be impractical for most purposes.

If for example, we wanted to know how many groups were created after step 3, we could do this:

```julia
result = @chain df begin
    dropmissing
    subset(:weight => ByRow(<(6)))
    groupby(:group)
    @aside println("There are $(length(_)) groups after step 3.")
    combine(:weight => sum => :total_weight)
end
```

Which is again equivalent to this:

```julia
result = let
    var1 = dropmissing(df)
    var2 = subset(var1, :weight => ByRow(<(6)))
    var3 = groupby(var2, :group)
    println("There are $(length(var3)) groups after step 3.")
    var4 = combine(var3, :weight => sum => :total_weight)
end
```

## Nested Chains

The `@chain` macro replaces all underscores in the following block, unless it encounters another `@chain` macrocall.
In that case, the only underscore that is still replaced by the outer macro is the first argument of the inner `@chain`.
You can use this, for example, in combination with the `@aside` macro if you need to process a side result further.

```julia
@chain df begin
    dropmissing
    subset(:weight => ByRow(<(6)))
    @aside @chain _ begin
            select(:group)
            CSV.write("filtered_groups.csv", _)
        end
    groupby(:group)
    combine(:weight => sum => :total_weight)
end
```

## Rewriting Rules

Here is a list of equivalent expressions, where `_` is replaced by `prev` and the new variable is `next`.
In reality, each new variable simply gets a new name via `gensym`, which is guaranteed not to conflict with anything else.

| **Before** | **After** | **Comment** |
| :-- | :-- | :-- |
| `sum` | `next = sum(prev)` | Symbol gets expanded into function call |
| `sum()` | `next = sum(prev)` | First argument is inserted |
| `sum(_)` | `next = sum(prev)` | Call expression gets `_` replaced |
| `_ + 3` | `next = prev + 3` | Infix call expressions work the same way as other calls |
| `+(3)` | `next = prev + 3` | Infix notation with _ would look better, but this is also possible |
| `1 + 2` | `next = prev + 1 + 2` | This might feel weird, but `1 + 2` is a normal call expression |
| `filter(isodd, _)` | `next = filter(isodd, prev)` | Underscore can go anywhere |
| `@aside println(_)` | `println(prev)` | `println` without affecting the pipeline; using `_` |
| `@aside println("hello")` | `println("hello")` | `println` without affecting the pipeline; no implicit first arg |
| `@. sin` | `next = sin.(prev)` | Special-cased alternative to `sin.()` |
| `sin.()` | `next = sin.(prev)` | First argument is prepended for broadcast calls as well |
| `somefunc.(x)` | `next = somefunc.(prev, x)` | First argument is prepended for broadcast calls as well |
| `@somemacro` | `next = @somemacro(prev)` | Macro calls without arguments get an argument spliced in |
| `@somemacro(x)` | `next = @somemacro(prev, x)` | First argument splicing is the same as with functions |
| `@somemacro(x, _)` | `next = @somemacro(x, prev)` | Also underscore behavior |

