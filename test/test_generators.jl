using ReTest
using SeeSign


@testset "Generators" begin
    struct CauseEvent <: SimEvent end
    struct NullEvent <: SimEvent end
    struct MyState <: PhysicalState end

    physical = MyState()
    generators(::Type{NullEvent}) = [
        EventGenerator(ToEvent, [:CauseEvent], function(f::Function, physical)
            f(NullEvent())
        end),
        EventGenerator(ToPlace, [:board, :nomatter, :occupant], function(f::Function, physical, who)
            f(NullEvent())
        end)
    ]

    places = [(:board, 3, :occupant), (:board, 4, :speed)]
    searcher = GeneratorSearch(generators(NullEvent))
    event_list = SimEvent[]
    add_to_list = function(event)
        push!(event_list, event)
    end

    over_generated_events(add_to_list, searcher, physical, clock_key(CauseEvent()), [(:board, 3, :occupant)])
    @test length(event_list) == 2
end
