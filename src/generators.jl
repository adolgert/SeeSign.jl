import Logging

##### Helpers for events

export EventGenerator, generators

"""
    EventGenerator{TransitionType}(matchstr, generator::Function)

When an event fires, it changes the physical state. The simulation observes which
parts of the physical state changed and sends those parts to this `EventGenerator`.
The `EventGenerator` is a rule that matches changes to the physical state and creates
`SimTransition` that act on that physical state.

The `matchstr` is a list of symbols `(array_name, ℤ, struct_member)`. The ℤ represents
the integer index within the array. For instance, if we simulated chess, it might
be `(:board, ℤ, :piece)`.

The generator is a callback that the simulation uses to determine which events
need to be enabled given recent changes to the state of the board. Its signature
is:

```
    callback_function(f::Function, physical_state, indices...)
```

Here the indices are the integer index that matches the ℤ above. This callback
function should look at the physical state and call `f(transition)` where
`transition` is an instance of `SimTransition`.
"""
struct EventGenerator{T}
    matchstr::Vector{Symbol}
    generator::Function
end

genmatch(eg::EventGenerator, place_key) = accessmatch(eg.matchstr, place_key)
(eg::EventGenerator)(f::Function, physical, indices...) = eg.generator(f, physical, indices...)



export EventEventGenerator


"""
    EventEventGenerator{TransitionType}(matchstr, generator::Function)

This generator reacts to the last event fired instead of `EventGenerator` which
reacts to the last places modified. In this case, the `matchstr` is a vector
with one entry, the symbol version of the transition type it matches. For
a transition called `MoveTransition` it would be `matchstr=[:MoveTransition]`.

The generator is a callback function whose signature is:


```
    callback_function(f::Function, physical_state, event_members...)
```

This callback function is passed arguments that are the members of the instance
of the transition it matched.
"""
struct EventEventGenerator
    matchstr::Vector{Symbol}
    generator::Function
end

genmatch(eg::EventEventGenerator, event_key) = (event_key[1] == eg.matchstr[1] ? (event_key[2:end],) : nothing)
(eg::EventEventGenerator)(f::Function, physical, indices...) = eg.generator(f, physical, indices...)


function transition_generate_event(gen, physical, place_key, existing_events)
    match_result = genmatch(gen, place_key)
    isnothing(match_result) && return nothing
    # @debug "matched $place_key"
    
    # Extract the first captured integer from the ℤ⁺ pattern
    sym_index_value = match_result[1][1]

    sym_create = SimTransition[]
    sym_depends = Set{Tuple}[]

    gen(physical, sym_index_value) do transition
        # @debug "Direction $direction"
        resetread(physical)
        if precondition(transition, physical)
            input_places = wasread(physical)
            if clock_key(transition) ∉ existing_events
                push!(sym_create, transition)
                push!(sym_depends, input_places)
            end
        end
    end
    if isempty(sym_create)
        return nothing
    else
        return (create=sym_create, depends=sym_depends)
    end
end


struct ImmediateEventGenerator
    matchstr::Vector{Symbol}
    generator::Function
end

genmatch(eg::ImmediateEventGenerator, event_key) = (event_key[1] == eg.matchstr[1] ? (event_key[2:end],) : nothing)
(eg::ImmediateEventGenerator)(f::Function, physical, indices...) = eg.generator(f, physical, indices...)


function transition_immediate_event(gen::ImmediateEventGenerator, physical, place_key, existing_events)
    match_result = genmatch(gen, place_key)
    isnothing(match_result) && return nothing
    # Extract the first captured integer from the ℤ⁺ pattern
    sym_index_value = match_result[1][1]

    changed_places = Set{Tuple}()
    gen(physical, sym_index_value) do transition
        # @debug "Direction $direction"
        if transition ∉ existing_events && precondition(transition, physical)
            push!(existing_events, transition)
            ans = capture_state_changes(physical) do
                fire!(transition, physical)
            end
            push!(changed_places, ans.changes)
        end
    end
    return changed_places
end


"""
    generators(::Type{SimTransition})::Vector{Union{EventGenerator,EventEventGenerator}}

Every transition in the simulation needs generators that notice changes to state
or events fired and create the appropriate transitions. Implement a `generators`
function as part of the interface of each transition.
"""
generators(::Type{SimTransition}) = Union{EventGenerator,EventEventGenerator}[]
