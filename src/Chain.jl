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

macro chain(firstpart, block)
    rewrite_chain_block(firstpart, block)
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
