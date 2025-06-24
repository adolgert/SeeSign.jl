using ReTest
using SeeSign

@testset "Event stuff" begin
    using SeeSign
    struct GoEvent <: SimEvent end
    struct StopEvent <: SimEvent
        when::Int
    end
    struct BounceEvent <: SimEvent
        when::Int
        howhigh::String
    end
    abstract type FlyEvent <: SimEvent end
    struct FloatEvent <: FlyEvent
        when::Int
        who::Symbol
        kind::Char
    end

    go = GoEvent()
    @assert clock_key(go) == (:GoEvent,)
    @assert key_clock(clock_key(go)) == go
end
