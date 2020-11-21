module Chain

export @chain

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

is_excepted(x) = false
is_excepted(x::Expr) = x.head == :macrocall && x.args[1] == Symbol("@!")


insert_first_arg(symbol::Symbol, firstarg) = Expr(:call, symbol, firstarg)
insert_first_arg(any, firstarg) = error("Can't insert an argument to $any. Needs to be a Symbol or a call expression")
function insert_first_arg(expr::Expr, firstarg)
    if expr.head == :call && length(expr.args) > 1
        Expr(expr.head, expr.args[1], firstarg, expr.args[2:end]...)
    else
        error("Can't prepend first arg to expression $expr that isn't a call.")
    end
end


macro chain(firstpart, block)
    if !(block isa Expr && block.head == :block)
        error("Second argument must be a begin / end block")
    end

    unblocked_parts = get_unblocked_parts(block)

    newexprs = []
    lastsym = firstpart

    for part in unblocked_parts
        if part isa LineNumberNode
            push!(newexprs, part)
            continue
        end
        had_underscore = false
        part_is_excepted = is_excepted(part)
        if part_is_excepted
            part = part.args[3] # 1 is macro symbol, 2 is LineNumberNode
        end
        newexpr = postwalk(part) do expr
            if expr == Symbol("_")
                had_underscore = true
                lastsym
            else
                expr
            end
        end

        arg_prepended = false
        if !(had_underscore || part_is_excepted)
            newexpr = insert_first_arg(newexpr, lastsym)
            arg_prepended = true
        end

        if (had_underscore || arg_prepended) && !part_is_excepted
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
