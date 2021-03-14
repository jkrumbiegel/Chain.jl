using Chain
using Test


@testset "1" begin
    x = [1, 2, 3]
    # one symbol
    y = @chain x begin
        sum
    end
    @test y == sum(x)

    # two expressions
    z = @chain x begin
        *(3)
        sum
    end
    @test z == sum(x .* 3)

    # interleaved expressions
    called = false
    zz = @chain x begin
        .*(3)
        @aside @assert sum(_) / length(_) == 6 # this doesn't change anything
        @aside called = true # this also doesn't do the _ insertion and doesn't change anything
        sum
    end
    @test zz == z
    @test called

    zzz = @chain x begin
        _ .* 3
        sum
    end
    @test zzz == z
end

@testset "2" begin
    x = 1:4
    y = @chain x begin
        filter(isodd, _)
        map(-, _)
        sum
        _ ^ 2
    end
    @test y == 16
end

@testset "nested begin" begin
    x = 1:5
    y = @chain x begin
        begin
            z = sum(_) + 3
            z - 7
        end
        sqrt
    end
    @test y == sqrt(sum(x) + 3 - 7)
end

@testset "no begin" begin
    x = [1, 2, 3]
    y = @chain x sum
    @test y == 6

    f() = 1
    y = @chain f() first
    @test y == 1

    y = @chain x sum(_) max(0, _) first
    @test y == 6
end

@testset "invalid invocations" begin
    # no begin with infix
    @test_throws LoadError eval(quote
        @chain 1 +(1)
    end)

    # no begin with anonymous function
    @test_throws LoadError eval(quote
        @chain 1 (t -> t + 1)()
    end)

    # no begin with sum
    @test_throws LoadError eval(quote
        @chain 1 (_ + 1)
    end)

    # just one argument
    @test_throws LoadError eval(quote
        @chain [1, 2, 3]
    end)

    # let block
    @test_throws LoadError eval(quote
        @chain [1, 2, 3] let
            sum
        end
    end)

    # variable defined in chain block doesn't leak out
    z = @chain [1, 2, 3] begin
        @aside inside_var = 5
        @aside @test inside_var == 5
        sum(_) + inside_var
    end
    @test z == 11
    @test_throws UndefVarError inside_var
end

@testset "nested chains" begin
    x = 1:5
    local z
    y = @chain x begin
        _ * 2
        @aside @chain _ begin
            sum(_)
            _ * 2
            @aside z = _
        end
        sum
    end
    @test y == sum(x * 2)
    @test z != x * 2
end

@testset "broadcast macro symbol" begin
    x = 1:5
    y = @chain x begin
        @. sin
        sum
    end
    @test y == sum(sin.(x))

    ## leave non-symbol invocations intact
    yy = @chain x begin
        @. sin(_)
        sum
    end
    @test yy == sum(sin.(x))
end

macro sin(exp)
    :(sin($(esc(exp))))
end

macro broadcastminus(exp1, exp2)
    :(broadcast(-, $(esc(exp1)), $(esc(exp2))))
end

@testset "splicing into macro calls" begin

    x = 1
    y = @chain x begin
        @sin
    end
    @test y == sin(x)

    y = @chain x begin
        @sin()
    end
    @test y == sin(x)

    xx = [1, 2, 3, 4]
    yy = @chain xx begin
        @broadcastminus(2.5)
    end
    @test yy == broadcast(-, xx, 2.5)

    xxx = [1, 2, 3, 4]
    yyy = @chain xxx begin
        @broadcastminus(2.5, _)
    end
    @test yyy == broadcast(-, 2.5, xxx)
end

@testset "single arg version" begin
    x = [1, 2, 3]

    xx = @chain begin
        x
    end
    @test xx == x

    # this has a different internal structure (one LineNumberNode missing I think)
    @test x == @chain begin
        x
    end

    @test sum(x) == @chain begin
        x
        sum
    end

    y = @chain begin
        x
        sum
    end
    @test y == sum(x)

    z = @chain begin
        x
        @. sqrt
        sum(_)
    end
    @test z == sum(sqrt.(x))

    @test sum == @chain begin
        sum
    end
end

@testset "invalid single arg versions" begin
    # empty
    @test_throws LoadError eval(quote
        @chain begin
        end
    end)

    # rvalue _ errors
    @test_throws ErrorException eval(quote
        @chain begin
            _
        end
    end)

    @test_throws ErrorException eval(quote
        @chain begin
            sum(_)
        end
    end)
end

@testset "handling keyword argments" begin
    f(a; kwarg) = (a, kwarg)
    @test (:a, :kwarg) == @chain begin
        :a
        f(kwarg = :kwarg)
    end
    @test (:a, :kwarg) == @chain begin
        :a
        f(; kwarg = :kwarg)
    end
end

# issue 13
@testset "no argument call" begin
    x = 1
    y = @chain x begin
        sin()
    end
    @test y == sin(x)
end

# issue 13
@testset "broadcasting calls" begin

    xs = [1, 2, 3]
    ys = @chain xs begin
        sin.()
    end
    @test ys == sin.(xs)

    add(x, y) = x + y

    zs = [4, 5, 6]
    sums = @chain xs begin
        add.(zs)
    end
    @test sums == add.(xs, zs)
end

# issue 16
@testset "empty chain" begin
    a = 2
    x = @chain a + 1 begin
    end
    @test x == 3

    y = @chain begin
        a + 1
    end
    @test y == 3
end

module LocalModule
    function square(xs)
        xs .^ 2
    end

    function power(xs, pow)
        xs .^ pow
    end

    add_one(x) = x + 1

    macro sin(exp)
        :(sin($(esc(exp))))
    end

    macro broadcastminus(exp1, exp2)
        :(broadcast(-, $(esc(exp1)), $(esc(exp2))))
    end

    module SubModule
        function square(xs)
            xs .^ 2
        end

        function power(xs, pow)
            xs .^ pow
        end

        add_one(x) = x + 1

        macro sin(exp)
            :(sin($(esc(exp))))
        end

        macro broadcastminus(exp1, exp2)
            :(broadcast(-, $(esc(exp1)), $(esc(exp2))))
        end
    end
end

@testset "Module qualification" begin

    using .LocalModule

    xs = [1, 2, 3]
    pow = 4
    y = @chain xs begin
        LocalModule.square
        LocalModule.power(pow)
        Base.sum
    end
    @test y == sum(LocalModule.power(LocalModule.square(xs), pow))

    y2 = @chain xs begin
        LocalModule.SubModule.square
        LocalModule.SubModule.power(pow)
        Base.sum
    end
    @test y == sum(LocalModule.SubModule.power(LocalModule.SubModule.square(xs), pow))

    y3 = @chain xs begin
        @. LocalModule.add_one
        @. LocalModule.SubModule.add_one
    end
    @test y3 == LocalModule.SubModule.add_one.(LocalModule.add_one.(xs))

    y4 = @chain xs begin
        LocalModule.@broadcastminus(2.5)
    end
    @test y4 == LocalModule.@broadcastminus(xs, 2.5)

    y5 = @chain xs begin
        LocalModule.SubModule.@broadcastminus(2.5)
    end
    @test y5 == LocalModule.SubModule.@broadcastminus(xs, 2.5)

    y6 = @chain 3 begin
        LocalModule.@sin
    end
    @test y6 == LocalModule.@sin(3)

    y7 = @chain 3 begin
        LocalModule.SubModule.@sin
    end
    @test y7 == LocalModule.SubModule.@sin(3)
end