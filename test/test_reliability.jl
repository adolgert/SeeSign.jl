using ReTest
using SeeSign


@testset "Reliability smoke" begin
    using .ReliabilitySim
    is = ReliabilitySim.IndividualState(15, 10)
end

