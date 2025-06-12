using SeeSign
using Test

@testset "SeeSign.jl" begin
    include("test_parse.jl")
    include("test_changed.jl")
    include("test_indexmath.jl")
    include("test_depnet.jl")
    include("test_tracked.jl")
    include("test_sim.jl")
end
