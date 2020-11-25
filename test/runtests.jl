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

@testset "invalid invocations" begin
    # just one argument
    @test_throws LoadError eval(quote
        @chain [1, 2, 3]
    end)

    # no begin block
    @test_throws LoadError eval(quote
        @chain [1, 2, 3] sum
    end)

    # empty
    @test_throws LoadError eval(quote
        @chain [1, 2, 3] begin
        end
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