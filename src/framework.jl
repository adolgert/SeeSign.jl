using Logging
using Random
using CompetingClocks: SSA, CombinedNextReaction, enable!, disable!, next, Xoshiro
using Distributions

macro react(func_sig, body)
    # Parse function signature: name(physical)
    func_name = func_sig.args[1]
    physical_param = func_sig.args[2]
    
    # Parse the body to extract @onevent, @generate, @condition, @action
    macro_exprs = Dict{String, Any}()
    
    for stmt in body.args
        if isa(stmt, Expr) && stmt.head == :macrocall
            macro_name = string(stmt.args[1])
            if macro_name in ["@onevent", "@generate", "@condition", "@action"]
                macro_exprs[macro_name] = stmt.args[3]
            end
        end
    end
    
    onevent_expr = get(macro_exprs, "@onevent", nothing)
    generate_expr = get(macro_exprs, "@generate", nothing)
    condition_expr = get(macro_exprs, "@condition", nothing)
    action_expr = get(macro_exprs, "@action", nothing)
    
    # Validate all required parts are present
    if isnothing(onevent_expr) || isnothing(generate_expr) || isnothing(condition_expr) || isnothing(action_expr)
        error("@react macro requires @onevent, @generate, @condition, and @action")
    end
    
    # Parse @onevent changed(physical.field[index].subfield)
    # Extract the field access pattern to determine filtering logic
    changed_expr = onevent_expr.args[2]  # The argument to changed()
    
    # Parse @generate var ∈ collection
    loop_var = generate_expr.args[2]
    loop_collection = generate_expr.args[3]
    
    # Generate unique variable names
    sym_create = gensym("create")
    sym_depends = gensym("depends") 
    sym_enabled = gensym("enabled")
    sym_enable_clock = gensym("enable_clock")
    sym_array_name = gensym("array_name")
    sym_index_value = gensym("index_value")
    sym_struct_value = gensym("struct_value")
    
    # Extract field access pattern for filtering
    field_parts = extract_field_pattern(changed_expr)
    array_name = field_parts.array
    index_var = field_parts.index_var
    field_name = field_parts.field
    
    # Generate the function
    func_name_generate = Symbol(string(func_name) * "_generate_event")
    
    quote
        function $(func_name_generate)($(physical_param), place_key, existing_events)
            # Parse place key
            $(sym_array_name), $(sym_index_value), $(sym_struct_value)... = place_key
            
            # Filter based on the @onevent pattern
            if $(sym_array_name) != $(QuoteNode(array_name)) || $(sym_struct_value) != ($(QuoteNode(field_name)),)
                return nothing
            end
            
            # The index variable from @onevent becomes available
            $(index_var) = $(sym_index_value)
            
            # Initialize collections
            $(sym_create) = []
            $(sym_depends) = []
            $(sym_enabled) = []
            
            # Generate loop
            for $(loop_var) in $(loop_collection)
                # Track reads
                resetread($(physical_param))
                
                # Execute condition block
                $(sym_enable_clock) = $(condition_expr)
                
                # If enabled, create the event
                if $(sym_enable_clock)
                    input_places = wasread($(physical_param))
                    
                    # Create transition from @action
                    transition = $(action_expr)
                    
                    # Create enable function closure
                    enable_func = let $(index_var) = $(sym_index_value), $(loop_var) = $(loop_var)
                        function($(physical_param),)
                            $(condition_expr)
                        end
                    end
                    
                    # Skip if already exists
                    clock_key(transition) in existing_events && continue
                    
                    # Add to collections
                    push!($(sym_create), transition)
                    push!($(sym_depends), input_places)
                    push!($(sym_enabled), enable_func)
                end
            end
            
            # Return result
            if isempty($(sym_create))
                return nothing
            else
                return (create=$(sym_create), depends=$(sym_depends), enabled=$(sym_enabled))
            end
        end
    end |> esc
end

function extract_field_pattern(expr)
    # Parse expressions like physical.board[loc].occupant or physical.agent[who].health
    # Return (array=:board, index_var=:loc, field=:occupant)
    
    if expr.head == :(.)
        # Get the field name (rightmost part)
        field_name = expr.args[2].value
        
        # Get the array access part
        array_access = expr.args[1]
        if array_access.head == :ref
            # physical.board[loc] -> array=:board, index_var=:loc
            array_part = array_access.args[1]
            index_var = array_access.args[2]
            array_name = array_part.args[2].value  # physical.board -> :board
            
            return (array=array_name, index_var=index_var, field=field_name)
        end
    end
    
    error("Could not parse @onevent expression: $expr")
end

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
    sym_enabled = Function[]

    gen(physical, sym_index_value) do mover, direction
        # @debug "Direction $direction"
        resetread(physical)
        if precondition(T, physical, mover, direction)
            input_places = wasread(physical)
            transition = T(physical, mover, direction)
            if clock_key(transition) ∉ existing_events
                push!(sym_create, transition)
                push!(sym_depends, input_places)
                let mover = mover, direction = direction
                    push!(sym_enabled, function(physical)
                        precondition(T, physical, mover, direction)
                    end)
                end
            end
        end
    end
    if isempty(sym_create)
        return nothing
    else
        return (create=sym_create, depends=sym_depends, enabled=sym_enabled)
    end
end


########## The Simulation Finite State Machine (FSM)

abstract type SimTransition end

generators(::Type{SimTransition}) = EventGenerator[]


struct EventData
    # The Event object itself.
    event::SimTransition
    # A function that returns true if the event is enabled.
    enable::Function
end


mutable struct SimulationFSM{State,Sampler,CK}
    physical::State
    sampler::Sampler
    event_rules::Vector{EventGenerator}
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
    @assert keys(sim.enabled_events) == keys(sim.depnet.event)
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
            if !enable_func(sim.physical) # Only argument is the physical state.
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
        for rule_func in sim.event_rules
            gen = transition_generate_event(rule_func, sim.physical, place, keys(sim.enabled_events))
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
    isempty(clock_keys) && return
    @debug "Disable clock $(clock_keys)"
    for clock_done in clock_keys
        disable!(sim.sampler, clock_done, sim.when)
        delete!(sim.enabled_events, clock_done)
    end
    remove_event!(sim.depnet, clock_keys)
end


function fire!(sim::SimulationFSM, when, what)
    @debug "Firing $(what)"
    sim.when = when
    whatevent = sim.enabled_events[what]
    fire!(whatevent.event, sim.physical)
    disable_clocks!(sim, [what])
    deal_with_changes(sim)
end
