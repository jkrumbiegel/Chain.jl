module PipelessPipes

export @_

function get_unblocked_parts(x, exprs = Any[])
    if x isa Expr && x.head == :block
        for arg in x.args
            exprs = get_unblocked_parts(arg, exprs)
        end
    else
        push!(exprs, x)
    end
    exprs
end

macro _(df, block)
    if !(block isa Expr && block.head == :block)
        error("Second argument must be a begin / end block")
    end

    unblocked_parts = get_unblocked_parts(block)

    newexprs = []
    lastsym = df
    for part in unblocked_parts
        if part isa LineNumberNode
            push!(newexprs, part)
            continue
        end
        need_new_variable = false
        newexpr = postwalk(part) do expr
            if expr == Symbol("_")
                need_new_variable = true
                lastsym
            elseif expr == Symbol("__")
                lastsym
            else
                expr
            end
        end
        if need_new_variable
            newsym = gensym()
            push!(newexprs, Expr(Symbol("="), newsym, newexpr))
            lastsym = newsym
        else
            push!(newexprs, newexpr)
        end
    end
    result = Expr(:let, Expr(:block), Expr(:block, newexprs...))

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
