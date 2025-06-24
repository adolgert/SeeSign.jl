using ReTest
using SeeSign

module TestSidewalk
    using SeeSign
    export Square, SidewalkState
    @tracked_struct Square begin
        occupant::Int
        resistance::Float64
    end
    mutable struct SidewalkState <: PhysicalState
        sidewalk::TrackedVector{Square}
        other::Int
        blah::String
    end

    function SidewalkState()
        square_cnt = 10
        sidewalk = TrackedVector{Square}(undef, square_cnt)
        for i in eachindex(sidewalk)
            sidewalk[i] = Square(0, 0.2)
        end
        SidewalkState(sidewalk, 24, "hi there")
    end
end

@testset "PhysicalState" begin
    using .TestSidewalk
    physical = SidewalkState()
    sidewalk = physical.sidewalk
    @assert isconsistent(physical)
    all_val_cnt = length(sidewalk) * length(propertynames(first(sidewalk)))
    @assert isempty(SeeSign.changed(sidewalk))
    @assert isempty(changed(physical))

    for touch in eachindex(sidewalk)
        sidewalk[touch].occupant = touch
        sidewalk[touch].resistance = 6.3
    end
    physical_vals = SeeSign.changed(physical)
    @assert length(physical_vals) == all_val_cnt
end
