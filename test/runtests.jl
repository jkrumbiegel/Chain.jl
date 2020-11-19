using PipelessPipes
using Test

@testset "PipelessPipes.jl" begin
    x = [1, 2, 3]
    y = @_ x begin
        sum(_)
    end
    @test y == sum(x)

    z = @_ x begin
        _ .* 3
        sum(_)
    end
    @test z == sum(x .* 3)

    zz = @_ x begin
        _ .* 3
        @assert sum(__) / length(__) == 6 # this doesn't change anything
        sum(_)
    end
    @test zz == z
end
