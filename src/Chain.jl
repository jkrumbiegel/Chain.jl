module Chain

export @chain

is_aside(x) = false
is_aside(x::Expr) = x.head == :macrocall && x.args[1] == Symbol("@aside")


insert_first_arg(symbol::Symbol, firstarg) = Expr(:call, symbol, firstarg)
insert_first_arg(any, firstarg) = error("Can't insert an argument to $any. Needs to be a Symbol or a call expression")
function insert_first_arg(expr::Expr, firstarg)
    if expr.head == :call && length(expr.args) > 1
        Expr(expr.head, expr.args[1], firstarg, expr.args[2:end]...)
    else
        error("Can't prepend first arg to expression $expr that isn't a call.")
    end
end

function rewrite(expr, replacement)
    aside = is_aside(expr)
    if aside
        expr = expr.args[3] # 1 is macro symbol, 2 is LineNumberNode
    end

    had_underscore = false
    new_expr = postwalk(expr) do ex
        if ex == Symbol("_")
            had_underscore = true
            replacement
        else
            ex
        end
    end

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

macro chain(firstpart, block)
    if !(block isa Expr && block.head == :block)
        error("Second argument must be a begin / end block")
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

## copied from MacroTools in order to avoid dependency

walk(x, inner, outer) = outer(x)
walk(x::Expr, inner, outer) = outer(Expr(x.head, map(inner, x.args)...))

"""
    postwalk(f, expr)
Applies `f` to each node in the given expression tree, returning the result.
`f` sees expressions *after* they have been transformed by the walk.
"""
postwalk(f, x) = walk(x, x -> postwalk(f, x), f)

end
