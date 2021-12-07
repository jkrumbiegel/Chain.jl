module Chain

export @chain

is_aside(x) = false
is_aside(x::Expr) = x.head == :macrocall && x.args[1] == Symbol("@aside")


insert_first_arg(symbol::Symbol, firstarg) = Expr(:call, symbol, firstarg)
insert_first_arg(any, firstarg) = insertionerror(any)

function insertionerror(expr)
    error(
        """Can't insert a first argument into:
        $expr.

        First argument insertion works with expressions like these, where [Module.SubModule.] is optional:

        [Module.SubModule.]func
        [Module.SubModule.]func(args...)
        [Module.SubModule.]func(args...; kwargs...)
        [Module.SubModule.]@macro
        [Module.SubModule.]@macro(args...)
        @. [Module.SubModule.]func
        """
    )
end

is_moduled_symbol(x) = false
function is_moduled_symbol(e::Expr)
    e.head == :. &&
        length(e.args) == 2 &&
        (e.args[1] isa Symbol || is_moduled_symbol(e.args[1])) &&
        e.args[2] isa QuoteNode &&
        e.args[2].value isa Symbol
end

function insert_first_arg(e::Expr, firstarg)
    head = e.head
    args = e.args

    # Module.SubModule.symbol
    if is_moduled_symbol(e)
        Expr(:call, e, firstarg)

    # f(args...) --> f(firstarg, args...)
    elseif head == :call && length(args) > 0
        if length(args) ≥ 2 && Meta.isexpr(args[2], :parameters)
            Expr(head, args[1:2]..., firstarg, args[3:end]...)
        else
            Expr(head, args[1], firstarg, args[2:end]...)
        end

    # f.(args...) --> f.(firstarg, args...)
    elseif head == :. &&
            length(args) > 1 &&
            args[1] isa Symbol &&
            args[2] isa Expr &&
            args[2].head == :tuple

        Expr(head, args[1], Expr(args[2].head, firstarg, args[2].args...))

    # @. [Module.SubModule.]somesymbol --> somesymbol.(firstarg)
    elseif head == :macrocall &&
            length(args) == 3 &&
            args[1] == Symbol("@__dot__") &&
            args[2] isa LineNumberNode &&
            (is_moduled_symbol(args[3]) || args[3] isa Symbol)

        Expr(:., args[3], Expr(:tuple, firstarg))

    # @macro(args...) --> @macro(firstarg, args...)
    elseif head == :macrocall &&
        (is_moduled_symbol(args[1]) || args[1] isa Symbol) &&
        args[2] isa LineNumberNode

        if args[1] == Symbol("@__dot__")
            error("You can only use the @. macro and automatic first argument insertion if what follows is of the form `[Module.SubModule.]func`")
        end

        if length(args) >= 3 && args[3] isa Expr && args[3].head == :parameters
            # macros can have keyword arguments after ; as well
            Expr(head, args[1], args[2], args[3], firstarg, args[4:end]...)
        else
            Expr(head, args[1], args[2], firstarg, args[3:end]...)
        end

    else
        insertionerror(e)
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
    pushfirst!(block.args, firstpart)
    rewrite_chain_block(block)
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
    if !(block.head == :block)
        block = Expr(:block, block)
    end
    rewrite_chain_block(initial_value, block)
end

"""
    @chain(initial_value, args...)

Rewrites a series of argments, either expressions or symbols, to feed the result
of each line into the next one. The initial value is given by the first argument.

In all arguments, underscores are replaced by the argument's result.
If there are no underscores and the argument is a symbol, the symbol is rewritten
to a function call with the previous result as the only argument.
If there are no underscores and the argument is a function call or a macrocall,
the call has the previous result prepended as the first argument.

Example:

```
x = @chain [1, 2, 3] filter(!=(2), _) sqrt.(_) sum

x == sum(sqrt.(filter(!=(2), [1, 2, 3])))
```
"""
macro chain(initial_value, args...)
    rewrite_chain_block(initial_value, Expr(:block, args...))
end

function rewrite_chain_block(block)
    block_expressions = block.args
    isempty(block_expressions) && error("No expressions found in chain block.")

    reconvert_docstrings!(block_expressions)

    # assign first line to first gensym variable
    firstvar = gensym()
    rewritten_exprs = []
    replacement = firstvar

    did_first = false
    for expr in block_expressions
        # could be an expression first or a LineNumberNode, so a bit convoluted
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

    result = Expr(:let, Expr(:block), Expr(:block, rewritten_exprs..., replacement))

    :($(esc(result)))
end

# if a line in a chain is a string, it can be parsed as a docstring
# for whatever is on the following line. because this is unexpected behavior
# for most users, we convert all docstrings back to separate lines.
function reconvert_docstrings!(args::Vector)
    docstring_indices = findall(args) do arg
        (arg isa Expr
            && arg.head == :macrocall
            && length(arg.args) == 4
            && arg.args[1] == GlobalRef(Core, Symbol("@doc")))
    end
    # replace docstrings from back to front because this leaves the earlier indices intact
    for i in reverse(docstring_indices)
        e = args[i]
        str = e.args[3]
        nextline = e.args[4]
        splice!(args, i:i, [str, nextline])
    end
    args
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
