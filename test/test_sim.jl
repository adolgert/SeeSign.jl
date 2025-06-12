using Test
using SeeSign
using Logging

@testset "Simulation Tests" begin
    with_logger(ConsoleLogger(stderr, Logging.Debug)) do
        SeeSign.run(10)
    end
end
