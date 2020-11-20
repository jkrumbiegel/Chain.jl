using PipelessPipes
using Test


@testset "1" begin
    x = [1, 2, 3]
    y = @_ x begin
        sum
    end
    @test y == sum(x)

    z = @_ x begin
        *(3)
        sum
    end
    @test z == sum(x .* 3)

    zz = @_ x begin
        .*(3)
        @! @assert sum(_) / length(_) == 6 # this doesn't change anything
        @! 1 + 1 # this also doesn't do the _ insertion and doesn't change anything
        sum
    end
    @test zz == z

    zzz = @_ x begin
        _ .* 3
        sum
    end
    @test zzz == z
end

@testset "2" begin
    x = 1:4
    y = @_ x begin
        filter(isodd, _)
        map(-, _)
        sum
        _ ^ 2
    end
    @test y == 16
end