using SeeSign
using Test

@testset "SeeSign.jl" begin
    include("test_parse.jl")
    include("test_changed.jl")
end
