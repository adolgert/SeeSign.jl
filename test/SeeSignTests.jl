
module SeeSignTests
using SeeSign
using ReTest

continuous_integration() = get(ENV, "CI", "false") == "true"

# Include test files directly at module level so @testset blocks are properly registered
include("test_parse.jl")
include("test_regex_tuples.jl")
include("test_changed.jl")
include("test_depnet.jl")
include("test_generators.jl")
include("test_tracked.jl")
include("test_events.jl")
include("test_physical.jl")
include("test_sim.jl")

retest(args...; kwargs...) = ReTest.retest(args...; kwargs...)

end
