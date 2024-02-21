# Chain.jl

A [Julia package](https://julialang.org/packages/) for piping a value through a series of transformation expressions using a more convenient syntax than Julia's native [piping functionality](https://docs.julialang.org/en/v1/manual/functions/#Function-composition-and-piping).

<table>
<tr><th>Chain.jl</th><th>Base Julia</th></tr>
<tr>
<td>
      
```julia
@chain df begin
  dropmissing
  filter(:id => >(6), _)
  groupby(:group)
  combine(:age => sum)
end
```

</td>
<td>

```julia
df |>
  dropmissing |>
  x -> filter(:id => >(6), x) |>
  x -> groupby(x, :group) |>
  x -> combine(x, :age => sum)
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
  filter(:id => >(6), _)|>
  groupby(_, :group) |>
  combine(_, :age => sum)
```

</td>
<td>
		
```julia
@> df begin
  dropmissing
  x -> filter(:id => >(6), x)
  groupby(:group)
  combine(:age => sum)
end
```

</td>
</tr>
</tr>
</table>

## Build Status

![Run tests](https://github.com/jkrumbiegel/Chain.jl/workflows/Run%20tests/badge.svg)

## Summary

Chain.jl exports the `@chain` macro.

This macro rewrites a series of expressions into a chain, where the result of one expression
is inserted into the next expression following certain rules.

**Rule 1**

Any `expr` that is a `begin ... end` block is flattened.
For example, these two pseudocodes are equivalent:

```julia
@chain a b c d e f

@chain a begin
    b
    c
    d
end e f
```

**Rule 2**

Any expression but the first (in the flattened representation) will have the preceding result
inserted as its first argument, unless at least one underscore `_` is present.
In that case, all underscores will be replaced with the preceding result.

If the expression is a symbol, the symbol is treated equivalently to a function call.

For example, the following code block

```julia
@chain begin
    x
    f()
    @g()
    h
    @i
    j(123, _)
    k(_, 123, _)
end
```

is equivalent to

```julia
begin
    local temp1 = f(x)
    local temp2 = @g(temp1)
    local temp3 = h(temp2)
    local temp4 = @i(temp3)
    local temp5 = j(123, temp4)
    local temp6 = k(temp5, 123, temp5)
end
```

**Rule 3**

An expression that begins with `@aside` does not pass its result on to the following expression.
Instead, the result of the previous expression will be passed on.
This is meant for inspecting the state of the chain.
The expression within `@aside` will not get the previous result auto-inserted, you can use
underscores to reference it.

```julia
@chain begin
    [1, 2, 3]
    filter(isodd, _)
    @aside @info "There are \$(length(_)) elements after filtering"
    sum
end
```

**Rule 4**

It is allowed to start an expression with a variable assignment.
In this case, the usual insertion rules apply to the right-hand side of that assignment.
This can be used to store intermediate results.

```julia
@chain begin
    [1, 2, 3]
    filtered = filter(isodd, _)
    sum
end

filtered == [1, 3]
```

**Rule 5**

The `@.` macro may be used with a symbol to broadcast that function over the preceding result.

```julia
@chain begin
    [1, 2, 3]
    @. sqrt
end
```

is equivalent to

```julia
@chain begin
    [1, 2, 3]
    sqrt.(_)
end
```


## Motivation

- The implicit first argument insertion is useful for many data pipeline scenarios, like `groupby`, `transform` and `combine` in DataFrames.jl
- The `_` syntax is there to either increase legibility or to use functions like `filter` or `map` which need the previous result as the second argument
- There is no need to type `|>` over and over
- Any line can be commented out or in without breaking syntax, there is no problem with dangling `|>` symbols
- The state of the pipeline can easily be checked with the `@aside` macro
- Flattening of `begin ... end` blocks allows you to split your chain over multiple lines
- Because everything is just lines with separate expressions and not one huge function call, IDEs can show exactly in which line errors happened
- Pipe is a name defined by Base Julia which can lead to conflicts

## Example

An example with a DataFrame:

```julia
using DataFrames, Chain

df = DataFrame(group = [1, 2, 1, 2, missing], weight = [1, 3, 5, 7, missing])

result = @chain df begin
    dropmissing
    filter(r -> r.weight < 6, _)
    groupby(:group)
    combine(:weight => sum => :total_weight)
end
```

The chain block is equivalent to this:

```julia
result = begin
    local var"##1" = dropmissing(df)
    local var"##2" = filter(r -> r.weight < 6, var"##1")
    local var"##3" = groupby(var"##2", :group)
    local var"##4" = combine(var"##3", :weight => sum => :total_weight)
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

## Variable assignments in the chain

You can prefix any of the expressions that Chain.jl can handle with a variable assignment.
The previous value will be spliced into the right-hand-side expression and the result will be available afterwards under the chosen variable name.

```julia
@chain 1:10 begin
    _ * 3
    filtered = filter(iseven, _)
    sum
end

filtered == [6, 12, 18, 24, 30]
```

## The `@aside` macro

For debugging, it's often useful to look at values in the middle of a pipeline.
You can use the `@aside` macro to mark expressions that should not pass on their result.
For these expressions there is no implicit first argument spliced in if there is no `_`, because that would be impractical for most purposes.

If for example, we wanted to know how many groups were created after step 3, we could do this:

```julia
result = @chain df begin
    dropmissing
    filter(r -> r.weight < 6, _)
    groupby(:group)
    @aside println("There are $(length(_)) groups after step 3.")
    combine(:weight => sum => :total_weight)
end
```

Which is again equivalent to this:

```julia
result = begin
    local var"##1" = dropmissing(df)
    local var"##2" = filter(r -> r.weight < 6, var"##1")
    local var"##3" = groupby(var"##2", :group)
    println("There are $(length(var"##3")) groups after step 3.")
    local var"##4" = combine(var"##3", :weight => sum => :total_weight)
end
```

## Nested Chains

The `@chain` macro replaces all underscores in the following block, unless it encounters another `@chain` macrocall.
In that case, the only underscore that is still replaced by the outer macro is the first argument of the inner `@chain`.
You can use this, for example, in combination with the `@aside` macro if you need to process a side result further.

```julia
@chain df begin
    dropmissing
    filter(r -> r.weight < 6, _)
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

