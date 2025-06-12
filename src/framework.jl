using Logging
using Random
using CompetingClocks

####### The physical state is transactional.

abstract type PhysicalState end

"""
Used for debugging.
"""
isconsistent(::PhysicalState) = true

"""
Iterate over all tracked vectors in the physical state.
"""
function over_tracked_physical_state(fcallback::Function, physical::T) where {T <: PhysicalState}
    for field_symbol in fieldnames(T)
        member = getproperty(physical, field_symbol)
        if isa(member, TrackedVector)
            fcallback(field_symbol, member)
        end
    end
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function changed(physical::PhysicalState)
    places = Set{Tuple}()
    over_tracked_physical_state(physical) do fieldname, member
        union!(places, [(fieldname, key...) for key in changed(member)])
    end
    return places
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function wasread(physical::PhysicalState)
    places = Set{Tuple}()
    over_tracked_physical_state(physical) do fieldname, member
        union!(places, [(fieldname, key...) for key in gotten(member)])
    end
    return places
end

"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function resetread(physical::PhysicalState)
    over_tracked_physical_state(physical) do _, member
        reset_gotten!(member)
    end
    return physical
end


"""
The arrays in a PhysicalState record that they have been modified.
This function erases the record of modifications.
"""
function accept(physical::PhysicalState)
    over_tracked_physical_state(physical) do _, member
        reset_tracking!(member)
    end
    return physical
end


########## The Simulation Finite State Machine (FSM)

abstract type SimTransition end

struct EventData
    # The Event object itself.
    event::SimTransition
    # A function that returns true if the event is enabled.
    enable::Function
end


mutable struct SimulationFSM{State,Sampler,CK}
    physical::State
    sampler::Sampler
    event_rules::Vector{Function}
    when::Float64
    rng::Xoshiro
    depnet::DependencyNetwork{CK}
    enabled_events::Dict{CK,EventData}
end


function SimulationFSM(physical, sampler::SSA{CK}, rules, seed) where {CK}
    return SimulationFSM{typeof(physical),typeof(sampler),CK}(
        physical,
        sampler,
        rules,
        0.0,
        Xoshiro(seed),
        DependencyNetwork{CK}(),
        Dict{CK,EventData}()
    )
end

function checksim(sim::SimulationFSM)
    sim_clocks = keys(sim.enabled_events)
    dep_clocks = keys(sim.depnet.event)
    @assert sim_clocks == dep_clocks
end


"""
    deal_with_changes(sim::SimulationFSM)

An event changed the state. This function modifies events
to respond to changes in state.
"""
function deal_with_changes(sim::SimulationFSM{State,Sampler,CK}) where {State,Sampler,CK}
    # This function starts with enabled events. It ends with enabled events.
    # Let's look at just those events that depend on changed places.
    #                      Finish
    #                 Enabled     Disabled
    # Start  Enabled  re-enable   remove
    #       Disabled  create      nothing
    #
    changed_places = changed(sim.physical)
    clock_toremove = Set{CK}()
    for place in changed_places
        depedges = getplace(sim.depnet, place)
        for clock_key in depedges.en
            enable_func = sim.enabled_events[clock_key].enable
            if !enable_func(sim.physical)
                push!(clock_toremove, clock_key)
            end
        end
    end
    # Split the loop over changed_places so that the first part disables clocks
    # and the second part creates new ones. We do this because two clocks
    # can have the SAME key but DIFFERENT dependencies. For instance, "move left"
    # will depend on different board places after the piece has moved.
    disable_clocks!(sim, clock_toremove)

    for place in changed_places
        # It's possible this should pass in the set of all existing events.
        for rule_func in sim.event_rules
            gen = rule_func(sim.physical, place, keys(sim.enabled_events))
            isnothing(gen) && continue
            for evtidx in eachindex(gen.create)
                event_data = EventData(gen.create[evtidx], gen.enabled[evtidx])
                evtkey = clock_key(event_data.event)
                sim.enabled_events[evtkey] = event_data

                begin
                    resetread(sim.physical)
                    enable(event_data.event, sim.sampler, sim.physical, sim.when, sim.rng)
                    rate_deps = wasread(sim.physical)
                end

                @debug "Evtkey $(evtkey) with enable deps $(gen.depends[evtidx]) rate deps $(rate_deps)"
                add_event!(sim.depnet, evtkey, gen.depends[evtidx], rate_deps)
            end
        end
    end
    accept(sim.physical)
    checksim(sim)
end


function disable_clocks!(sim::SimulationFSM, clock_keys)
    @debug "Disable clock $(clock_keys)"
    for clock_done in clock_keys
        disable!(sim.sampler, clock_done, sim.when)
        delete!(sim.enabled_events, clock_done)
    end
    remove_event!(sim.depnet, clock_keys)
end


function fire!(sim::SimulationFSM, when, what)
    sim.when = when
    whatevent = sim.enabled_events[what]
    fire!(whatevent.event, sim.physical)
    disable_clocks!(sim, [what])
    deal_with_changes(sim)
end
