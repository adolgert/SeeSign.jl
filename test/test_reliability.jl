using ReTest
using SeeSign


@testset "Reliability smoke" begin
    using .ReliabilitySim
    is = ReliabilitySim.IndividualState(15, 10)
end


@testset "Reliability run" begin
    using .ReliabilitySim
    ci = continuous_integration()
    log_level = ci ? Logging.Error : Logging.Debug
    run_cnt = ci ? 10 : 1000

    with_logger(ConsoleLogger(stderr, log_level)) do
        run_reliability(10)
    end
end
