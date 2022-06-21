# v0.5

**Breaking**: The `@chain` macro now creates a `begin` block, not a `let` block.
This means that variables that are assigned within the macro are available outside.
Technically, situations are imaginable where this could lead to overwritten variables if someone used large expressions with intermediate variable names in begin blocks spliced into the chain.
It is however quite unlikely for the normal way that `@chain` is intended to be used.

Additionally, it is now possible to use the syntax `variable = some_expression` to make use of the feature that variables can be exported.
The `some_expression` part is handled exactly like before.
This enables you to carry parts of a computation forward to a later step in the chain or outside of it:

```julia
@chain df begin
    transform(...)
    select(...)
    intermediate = subset(...)
    groupby(...)
    combine(...)
    join(intermediate)
end

@show intermediate
```