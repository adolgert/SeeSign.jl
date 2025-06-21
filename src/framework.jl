using Logging
using Random
using CompetingClocks: SSA, CombinedNextReaction, enable!, disable!, next, Xoshiro
using Distributions



########## The Simulation Finite State Machine (FSM)

mutable struct SimulationFSM{State,Sampler,CK}
    physical::State
    sampler::Sampler
    event_rules::Vector{EventGenerator}
    event_event_rules::Vector{EventEventGenerator}
    immediate_rules::Vector{ImmediateEventGenerator}
    when::Float64
    rng::Xoshiro
    depnet::DependencyNetwork{CK}
    enabled_events::Dict{CK,SimTransition}
    enabling_times::Dict{CK,Float64}
    observer
end


"""
    SimulationFSM(physical_state, sampler, trans_rules, seed; observer=nothing)

Create a simulation.

The `physical_state` is of type `PhysicalState`. The sampler is of type
`CompetingClocks.SSA`. The `trans_rules` are a list of type `SimTransition`.
The seed is an integer seed for a `Xoshiro` random number generator. The
observer is a callback with the signature:

```
observer(physical, when::Float64, event::SimTransition, changed_places::Set{Tuple})
```

The `changed_places` argument is a set-like object with tuples that are keys that
represent which places were changed.
"""
function classify_transition_rules(trans_rules)
    event_rules = EventGenerator[]
    event_event_rules = EventEventGenerator[]
    immediate_rules = ImmediateEventGenerator[]
    not_good_rule = []
    
    for transition in trans_rules
        for rule in generators(transition)
            if isa(rule, EventGenerator)
                push!(event_rules, rule)
            elseif isa(rule, EventEventGenerator)
                push!(event_event_rules, rule)
            elseif isa(rule, ImmediateEventGenerator)
                push!(immediate_rules, rule)
            else
                push!(not_good_rule, rule)
            end
        end
    end
    
    if !isempty(not_good_rule)
        @error "Could not classify as a place rule or an event rule: $(length(not_good_rule))"
        for rule in not_good_rule
            @error "offending rule: $rule"
        end
        @assert isempty(not_good_rule)
    end
    
    return (;event_rules, event_event_rules, immediate_rules)
end

function SimulationFSM(physical, sampler::SSA{CK}, trans_rules, seed; observer=nothing) where {CK}
    rules = classify_transition_rules(trans_rules)
    
    if isnothing(observer)
        observer = (args...) -> nothing
    end
    return SimulationFSM{typeof(physical),typeof(sampler),CK}(
        physical,
        sampler,
        rules.event_rules,
        rules.event_event_rules,
        rules.immediate_rules,
        0.0,
        Xoshiro(seed),
        DependencyNetwork{CK}(),
        Dict{CK,SimTransition}(),
        Dict{CK,Float64}(),
        observer,
    )
end

function checksim(sim::SimulationFSM)
    @assert keys(sim.enabled_events) == keys(sim.depnet.event)
end


function rate_reenable(sim::SimulationFSM, event, clock_key)
    first_enable = sim.enabling_times[clock_key]
    reads_result = capture_state_reads(sim.physical) do
        reenable(event, sim.sampler, sim.physical, first_enable, sim.when, sim.rng)
    end
    return reads_result.reads
end

function generate_new_events(sim::SimulationFSM, changed_places, fired_event)
    new_events = Tuple{SimTransition,Set{Tuple}}[]
    
    # Process place-based rules
    for place in changed_places
        for rule_func in sim.event_rules
            gen = transition_generate_event(rule_func, sim.physical, place, keys(sim.enabled_events))
            isnothing(gen) && continue
            for evtidx in eachindex(gen.create)
                event = gen.create[evtidx]
                push!(new_events, (event, gen.depends[evtidx]))
            end
        end
    end
    
    # Process event-event rules (rules that trigger on events rather than places)
    for evt_rule_func in sim.event_event_rules
        gen = transition_generate_event(evt_rule_func, sim.physical, fired_event, keys(sim.enabled_events))
        isnothing(gen) && continue
        for evtidx in eachindex(gen.create)
            event = gen.create[evtidx]
            push!(new_events, (event, gen.depends[evtidx]))
        end
    end
    
    return new_events
end

function enable_new_event!(sim::SimulationFSM, event, cond_deps)
    evtkey = clock_key(event)
    sim.enabled_events[evtkey] = event
    sim.enabling_times[evtkey] = sim.when
    
    reads_result = capture_state_reads(sim.physical) do
        enable(event, sim.sampler, sim.physical, sim.when, sim.rng)
    end
    rate_deps = reads_result.reads
    
    @debug "Evtkey $(evtkey) with enable deps $(cond_deps) rate deps $(rate_deps)"
    add_event!(sim.depnet, evtkey, cond_deps, rate_deps)
end


"""
    deal_with_changes(sim::SimulationFSM)

An event changed the state. This function modifies events
to respond to changes in state.
"""
function deal_with_changes(
    sim::SimulationFSM{State,Sampler,CK}, fired_event, changed_places
    ) where {State,Sampler,CK}
    # This function starts with enabled events. It ends with enabled events.
    # Let's look at just those events that depend on changed places.
    #                      Finish
    #                 Enabled     Disabled
    # Start  Enabled  re-enable   remove
    #       Disabled  create      nothing
    #
    # Sort for reproducibility run-to-run.
    clock_toremove = CK[]
    cond_affected = union((getplace(sim.depnet, cp).en for cp in changed_places)...)
    rate_affected = union((getplace(sim.depnet, cp).ra for cp in changed_places)...)

    for check_clock_key in sort(collect(cond_affected))
        event = sim.enabled_events[check_clock_key]
        reads_result = capture_state_reads(sim.physical) do
            precondition(event, sim.physical)
        end
        cond_result = reads_result.result
        cond_places = reads_result.reads

        if !cond_result
            push!(clock_toremove, check_clock_key)
        else
            # Every time we check an invariant after a state change, we must
            # re-calculate how it depends on the state. For instance,
            # A can move right. Then A moves down. Then A can still move
            # right, but its moving right now depends on a different space
            # to the right. This is because a "move right" event is defined
            # relative to a state, not on a specific set of places.
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
        cond_deps = getplace(sim.depnet, rate_clock_key).en
        add_event!(sim.depnet, rate_clock_key, cond_deps, rate_deps)
    end

    # Split the loop over changed_places so that the first part disables clocks
    # and the second part creates new ones. We do this because two clocks
    # can have the SAME key but DIFFERENT dependencies. For instance, "move left"
    # will depend on different board places after the piece has moved.
    disable_clocks!(sim, clock_toremove)

    new_events = generate_new_events(sim, changed_places, fired_event)
    for (event, dependencies) in new_events
        enable_new_event!(sim, event, dependencies)
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
    sim.when = when
    event = sim.enabled_events[what]
    
    changes_result = capture_state_changes(sim.physical) do
        fire!(event, sim.physical)
    end
    changed_places = changes_result.changes
    
    seen_immediate = SimTransition[]
    for immediate in sim.immediate_rules
        more_places = transition_immediate_event(immediate, sim.physical, what, seen_immediate)
        union!(changed_places, more_places)
    end
    sim.observer(sim.physical, when, event, changed_places)
    disable_clocks!(sim, [what])
    deal_with_changes(sim, event, changed_places)
end


"""
Initialize the simulation. You could call it as a do-function.
It is structured this way so that the simulation will record changes to the
physical state.
```
    initialize!(sim) do init_physical
        initialize!(init_physical, agent_cnt, sim.rng)
    end
```
"""
function initialize!(callback::Function, sim::SimulationFSM)
    changes_result = capture_state_changes(sim.physical) do
        callback(sim.physical)
    end
    deal_with_changes(sim, InitializeEvent(), changes_result.changes)
end


"""
    run(simulation, initializer, stop_condition)

Given a simulation, this initializes the physical state and generates a
trajectory from the simulation until the stop condition is met. The `initializer`
is a function whose argument is a physical state and returns nothing. The
stop condition is a function with the signature:

```
stop_condition(physical_state, step_idx, event::SimTransition, when)::Bool
```

The event and when passed into the stop condition are the event and time that are
about to fire but have not yet fired. This lets you enforce a stopping time that
is between events.
"""
function run(sim::SimulationFSM, initializer, stop_condition)
    step_idx = 0
    initialize!(initializer, sim)
    should_stop = stop_condition(sim.physical, step_idx, InitializeEvent(), sim.when)
    should_stop && return
    step_idx += 1
    while true
        (when, what) = next(sim.sampler, sim.when, sim.rng)
        if isfinite(when) && !isnothing(what)
            should_stop = stop_condition(sim.physical, step_idx, what, when)
            should_stop && break
            @debug "Firing $what at $when"
            fire!(sim, when, what)
        else
            @info "No more events to process after $step_idx iterations."
            break
        end
        step_idx += 1
    end
end
