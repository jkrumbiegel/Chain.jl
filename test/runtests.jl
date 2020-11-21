using Chain
using Test


@testset "1" begin
    x = [1, 2, 3]
    y = @chain x begin
        sum
    end
    @test y == sum(x)

    z = @chain x begin
        *(3)
        sum
    end
    @test z == sum(x .* 3)

    zz = @chain x begin
        .*(3)
        @! @assert sum(_) / length(_) == 6 # this doesn't change anything
        @! 1 + 1 # this also doesn't do the _ insertion and doesn't change anything
        sum
    end
    @test zz == z

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