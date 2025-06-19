using Logging
using Random
using CompetingClocks: SSA, CombinedNextReaction, enable!, disable!, next, Xoshiro
using Distributions


####### The physical state is transactional.

export PhysicalState, changed, wasread, resetread, accept
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

##### Helpers for events

export EventGenerator, generators
struct EventGenerator{T}
    matchstr::Vector{Symbol}
    generator::Function
end

genmatch(eg::EventGenerator, place_key) = accessmatch(eg.matchstr, place_key)
(eg::EventGenerator)(f::Function, physical, indices...) = eg.generator(f, physical, indices...)


function transition_generate_event(gen::EventGenerator{T}, physical, place_key, existing_events) where T
    match_result = genmatch(gen, place_key)
    isnothing(match_result) && return nothing
    # @debug "matched $place_key"
    
    # Extract the first captured integer from the ℤ⁺ pattern
    sym_index_value = match_result[1][1]

    sym_create = T[]
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


########## The Simulation Finite State Machine (FSM)

abstract type SimTransition end


# clock_key makes an immutable hash from a possibly-mutable struct for use in Dict.
@generated function clock_key(transition::T) where T <: SimTransition
    type_symbol = QuoteNode(nameof(T))
    field_exprs = [:(transition.$field) for field in fieldnames(T)]
    return :($type_symbol, $(field_exprs...))
end

# Takes a tuple of the form (:symbol, arg, arg) and returns an instantiation
# of the struct named by :symbol.
@generated function key_clock(key::Tuple)
    type_symbol = key.parameters[1]
    if isa(type_symbol, Symbol)
        struct_type = eval(type_symbol)
        field_count = fieldcount(struct_type)
        field_exprs = [:(key[$(i+1)]) for i in 1:field_count]
        return :($struct_type($(field_exprs...)))
    else
        return :(error("First element of tuple must be a Symbol"))
    end
end


generators(::Type{SimTransition}) = EventGenerator[]


mutable struct SimulationFSM{State,Sampler,CK}
    physical::State
    sampler::Sampler
    event_rules::Vector{EventGenerator}
    when::Float64
    rng::Xoshiro
    depnet::DependencyNetwork{CK}
    enabled_events::Dict{CK,SimTransition}
    enabling_times::Dict{CK,Float64}
end


function SimulationFSM(physical, sampler::SSA{CK}, rules, seed) where {CK}
    return SimulationFSM{typeof(physical),typeof(sampler),CK}(
        physical,
        sampler,
        rules,
        0.0,
        Xoshiro(seed),
        DependencyNetwork{CK}(),
        Dict{CK,SimTransition}(),
        Dict{CK,Float64}(),
    )
end

function checksim(sim::SimulationFSM)
    @assert keys(sim.enabled_events) == keys(sim.depnet.event)
end

function rate_reenable(sim::SimulationFSM, event, clock_key)
    resetread(sim.physical)
    first_enable = sim.enabling_times[clock_key]
    reenable(event, sim.sampler, sim.physical, first_enable, sim.when, sim.rng)
    rate_deps = wasread(sim.physical)
    return rate_deps
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
    # Sort for reproducibility run-to-run.
    changed_places = changed(sim.physical)
    @debug "Changed places $changed_places"
    clock_toremove = CK[]
    cond_affected = union((getplace(sim.depnet, cp).en for cp in changed_places)...)
    rate_affected = union((getplace(sim.depnet, cp).ra for cp in changed_places)...)

    for check_clock_key in sort(collect(cond_affected))
        event = sim.enabled_events[check_clock_key]
        begin
            resetread(sim.physical)
            cond_result = precondition(event, sim.physical)
        end

        if !cond_result
            push!(clock_toremove, check_clock_key)
        else
            # Every time we check an invariant after a state change, we must
            # re-calculate how it depends on the state. For instance,
            # A can move right. Then A moves down. Then A can still move
            # right, but its moving right now depends on a different space
            # to the right. This is because a "move right" event is defined
            # relative to a state, not on a specific set of places.
            cond_places = wasread(sim.physical)
            if cond_places != getplace(sim.depnet, check_clock_key).en
                # Then you get new places.
                rate_deps = rate_reenable(sim, event, check_clock_key)
                add_event!(sim.depnet, check_clock_key, cond_places, rate_deps)
                if check_clock_key in rate_affected
                    delete!(rate_affected, check_clock_key)
                end
            end
        end
    end

    for rate_clock_key in sort(collect(rate_affected))
        event = sim.enabled_events[rate_clock_key]
        rate_deps = rate_reenable(sim, event, rate_clock_key)
        cond_affected = getplace(sim.depnet, place).en
        add_event!(sim.depnet, check_clock_key, cond_affected, rate_deps)
    end

    # Split the loop over changed_places so that the first part disables clocks
    # and the second part creates new ones. We do this because two clocks
    # can have the SAME key but DIFFERENT dependencies. For instance, "move left"
    # will depend on different board places after the piece has moved.
    disable_clocks!(sim, clock_toremove)

    for place in changed_places
        for rule_func in sim.event_rules
            gen = transition_generate_event(rule_func, sim.physical, place, keys(sim.enabled_events))
            isnothing(gen) && continue
            for evtidx in eachindex(gen.create)
                event = gen.create[evtidx]
                evtkey = clock_key(event)
                sim.enabled_events[evtkey] = event
                sim.enabling_times[evtkey] = sim.when

                begin
                    resetread(sim.physical)
                    enable(event, sim.sampler, sim.physical, sim.when, sim.rng)
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
    isempty(clock_keys) && return
    @debug "Disable clock $(clock_keys)"
    for clock_done in clock_keys
        disable!(sim.sampler, clock_done, sim.when)
        delete!(sim.enabled_events, clock_done)
        delete!(sim.enabling_times, clock_done)
    end
    remove_event!(sim.depnet, clock_keys)
end


function fire!(sim::SimulationFSM, when, what)
    @debug "Firing $(what)"
    sim.when = when
    fire!(sim.enabled_events[what], sim.physical)
    disable_clocks!(sim, [what])
    deal_with_changes(sim)
end
