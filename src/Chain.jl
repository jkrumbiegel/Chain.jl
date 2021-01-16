module Chain

export @chain

is_aside(x) = false
is_aside(x::Expr) = x.head == :macrocall && x.args[1] == Symbol("@aside")


insert_first_arg(symbol::Symbol, firstarg) = Expr(:call, symbol, firstarg)
insert_first_arg(any, firstarg) = error("Can't insert an argument to $any. Needs to be a Symbol or a call expression")

function insert_first_arg(e::Expr, firstarg)
    head = e.head
    args = e.args

    # f(a, b) --> f(firstarg, a, b)
    if head == :call && length(args) > 0
        if length(args) ≥ 2 && Meta.isexpr(args[2], :parameters)
            Expr(head, args[1:2]..., firstarg, args[3:end]...)
        else
            Expr(head, args[1], firstarg, args[2:end]...)
        end

    # @. somesymbol --> somesymbol.(firstarg)
    elseif head == :macrocall && length(args) == 3 && args[1] == Symbol("@__dot__") &&
            args[2] isa LineNumberNode && args[3] isa Symbol
        Expr(:., args[3], Expr(:tuple, firstarg))

    # @macro(a, b) --> @macro(firstarg, a, b)
    elseif head == :macrocall && args[1] isa Symbol && args[2] isa LineNumberNode
        Expr(head, args[1], args[2], firstarg, args[3:end]...)

    else
        error("Can't prepend first arg to expression $e that isn't a call.")
    end
end

function rewrite(expr, replacement)
    aside = is_aside(expr)
    if aside
        length(expr.args) != 3 && error("Malformed @aside macro")
        expr = expr.args[3] # 1 is macro symbol, 2 is LineNumberNode
    end

    had_underscore, new_expr = replace_underscores(expr, replacement)

    if !aside
        if !had_underscore
            new_expr = insert_first_arg(new_expr, replacement)
        end
        replacement = gensym()
        new_expr = Expr(Symbol("="), replacement, new_expr)
    end

    (new_expr, replacement)
end

rewrite(l::LineNumberNode, replacement) = (l, replacement)

function rewrite_chain_block(firstpart, block)
    if !(block isa Expr && block.head == :block)
        error("Second argument of @chain must be a begin / end block")
    end

    block_expressions = block.args
    isempty(block_expressions) && error("No expressions found in chain block.")

    rewritten_exprs = []
    replacement = firstpart

    for expr in block_expressions
        rewritten, replacement = rewrite(expr, replacement)
        push!(rewritten_exprs, rewritten)
    end

    result = Expr(:let, Expr(:block), Expr(:block, rewritten_exprs...))

    :($(esc(result)))
end

"""
    @chain(initial_value, block::Expr)

Rewrites a block expression to feed the result of each line into the next one.
The initial value is given by the first argument.

In all lines, underscores are replaced by the previous line's result.
If there are no underscores and the expression is a symbol, the symbol is rewritten
to a function call with the previous result as the only argument.
If there are no underscores and the expression is a function call or a macrocall,
the call has the previous result prepended as the first argument.

Example:

```
x = @chain [1, 2, 3] begin
    filter(!=(2), _)
    sqrt.(_)
    sum
end
x == sum(sqrt.(filter(!=(2), [1, 2, 3])))
```
"""
macro chain(initial_value, block::Expr)
    rewrite_chain_block(initial_value, block)
end

function rewrite_chain_block(block)
    if !(block isa Expr && block.head == :block)
        error("Only argument of single-argument @chain must be a begin / end block")
    end

    block_expressions = block.args
    isempty(block_expressions) && error("No expressions found in chain block.")

    # assign first line to first gensym variable
    firstvar = gensym()
    rewritten_exprs = []
    replacement = firstvar

    did_first = false
    for expr in block_expressions
        # could be and expression first or a LineNumberNode, so a bit convoluted
        # we just do the firstvar transformation for the first non LineNumberNode
        # we encounter
        if !(did_first || expr isa LineNumberNode)
            expr = Expr(Symbol("="), firstvar, expr)
            did_first = true
            push!(rewritten_exprs, expr)
            continue
        end

        rewritten, replacement = rewrite(expr, replacement)
        push!(rewritten_exprs, rewritten)
    end

    result = Expr(:let, Expr(:block), Expr(:block, rewritten_exprs...))

    :($(esc(result)))
end

"""
    @chain(block::Expr)

Rewrites a block expression to feed the result of each line into the next one.
The first line serves as the initial value and is not rewritten.

In all other lines, underscores are replaced by the previous line's result.
If there are no underscores and the expression is a symbol, the symbol is rewritten
to a function call with the previous result as the only argument.
If there are no underscores and the expression is a function call or a macrocall,
the call has the previous result prepended as the first argument.

Example:

```
x = @chain begin
    [1, 2, 3]
    filter(!=(2), _)
    sqrt.(_)
    sum
end
x == sum(sqrt.(filter(!=(2), [1, 2, 3])))
```
"""
macro chain(block::Expr)
    rewrite_chain_block(block)
end

function replace_underscores(expr::Expr, replacement)
    found_underscore = false

    # if a @chain macrocall is found, only its first arg can be replaced if it's an
    # underscore, otherwise the macro insides are left untouched
    if expr.head == :macrocall && expr.args[1] == Symbol("@chain")
        length(expr.args) != 4 && error("Malformed nested @chain macro")
        expr.args[2] isa LineNumberNode || error("Malformed nested @chain macro")
        arg3 = if expr.args[3] == Symbol("_")
            found_underscore = true
            replacement
        else
            expr.args[3]
        end
        newexpr = Expr(:macrocall, Symbol("@chain"), expr.args[2], arg3, expr.args[4])
    # for all other expressions, their arguments are checked for underscores recursively
    # and replaced if any are found
    else
        newargs = map(x -> replace_underscores(x, replacement), expr.args)
        found_underscore = any(first.(newargs))
        newexpr = Expr(expr.head, last.(newargs)...)
    end
    return found_underscore, newexpr
end

function replace_underscores(x, replacement)
    if x == Symbol("_")
        true, replacement
    else
        false, x
    end
end

end
