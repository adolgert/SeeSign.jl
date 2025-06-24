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

    event_list = [GoEvent, StopEvent, BounceEvent, FloatEvent]
    event_dict = Dict(nameof(ename) => ename for ename in event_list)

    go = GoEvent()
    @assert clock_key(go) == (:GoEvent,)
    @assert key_clock((:GoEvent,), event_dict) == go
    @assert key_clock(clock_key(go), event_dict) == go

    stop = StopEvent(3)
    @assert key_clock(clock_key(stop), event_dict) == stop

    bounce = BounceEvent(7, "high")
    @assert key_clock(clock_key(bounce), event_dict) == bounce

    float = FloatEvent(-2, :brown, 'c')
    @assert key_clock(clock_key(float), event_dict) == float
end
