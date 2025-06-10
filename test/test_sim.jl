using Test
using SeeSign

@testset "Simulation Tests" begin
    using SeeSign
    @testset "Run the sim" begin
        SeeSign.run(10)
    end
end
