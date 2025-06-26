using ReTest
using SeeSign


@testset "Reliability smoke" begin
    using .ReliabilitySim
    is = ReliabilitySim.IndividualState(15, 10)
end


@testset "Reliability run" begin
    using .ReliabilitySim
    run_reliability(10)
end

