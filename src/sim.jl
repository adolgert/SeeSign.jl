import Base
using Distributions
using Random
using SparseArrays
using Test
using Logging
using CompetingClocks


# They can move in any of four directions.
@enum Direction NoDirection Up Left Down Right
const DirectionDelta = Dict(
    Up => CartesianIndex(-1, 0),
    Left => CartesianIndex(0, -1),
    Down => CartesianIndex(1, 0),
    Right => CartesianIndex(0, 1),
    );
const DirectionOpposite = Dict(
    Up => Down, Down => Up, Left => Right, Right => Left
)

@enum Health NoHealth Healthy Sick Dead
@enum HealthEvent NoEvent Infect Recover Die

const PlaceKey = Tuple
# The last element is an int here but can be a direction.
const ClockKey = Tuple
export run

@tracked_struct Square begin
    occupant::Int
    resistance::Float64
end


@tracked_struct Agent begin
    health::Health
    loc::CartesianIndex{2}
    birthtime::Float64
end

const BoardIndices = CartesianIndices{2, Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}}

# There are agents located on a 2D board.
# The state is a checkerboard. Each plaquette in the checkerboard
# is 0 or contains an individual identified by an integer.
# An individual has a health state.
mutable struct PhysicalState
    board::TrackedVector{Square}
    agent::TrackedVector{Agent}
    # The tracked_vector is 1D but the board is 2D so we have to save conversion.
    board_dim::BoardIndices

    function PhysicalState(board::AbstractArray)
        linboard = TrackedVector{Square}(undef, length(board))
        for (i, val) in enumerate(board)
            linboard[i] = Square(val, 1.0)
        end
        location = findall(x -> x != 0, board)
        agent = TrackedVector{Agent}(undef, length(location))
        for (i, loc) in enumerate(location)
            agent[i] = Agent(Healthy, loc, 0.0)
        end
        new(linboard, agent, CartesianIndices(board))
    end
end


function isconsistent(physical::PhysicalState)
    # Check that the board is consistent with the agents.
    seen_agents = Set{Int}()
    for square in eachindex(physical.board)
        if physical.board[square].occupant != 0
            agent_idx = physical.board[square].occupant
            if agent_idx in seen_agents
                @error "Inconsistent board: square $square has occupant $agent_idx but it was already seen"
                return false
            end
            push!(seen_agents, agent_idx)
            agent_loc = physical.agent[agent_idx].loc
            if agent_loc != physical.board_dim[square]
                @error "Inconsistent board: square $square has occupant $agent_idx at location $agent_loc but should be at $(physical.board_dim[square])"
                return false
            end
        end
    end
    @assert seen_agents == Set(1:length(physical.agent))
    return true
end


"""
Iterate over all tracked vectors in the physical state.
"""
function over_tracked(fcallback::Function, physical::PhysicalState)
    for field_symbol in fieldnames(PhysicalState)
        member = getproperty(physical, field_symbol)
        if isa(member, TrackedVector)
            fcallback(field_symbol, member)
        end
    end
end


function move_agent(physical, agentidx, destination)
    old_loc = physical.agent[agentidx].loc
    old_board_idx = LinearIndices(physical.board_dim)[old_loc]
    new_board_idx = LinearIndices(physical.board_dim)[destination]
    
    physical.board[old_board_idx].occupant = 0
    physical.agent[agentidx].loc = destination
    physical.board[new_board_idx].occupant = agentidx
end


function move_in_direction(physical, agentidx, direction)
    newloc = physical.agent[agentidx].loc + DirectionDelta[direction]
    move_agent(physical, agentidx, newloc)
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function changed(physical::PhysicalState)
    places = Set{Tuple}()
    over_tracked(physical) do fieldname, member
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
    over_tracked(physical) do fieldname, member
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
    over_tracked(physical) do _, member
        reset_gotten!(member)
    end
    return physical
end


"""
The arrays in a PhysicalState record that they have been modified.
This function erases the record of modifications.
"""
function accept(physical::PhysicalState)
    over_tracked(physical) do _, member
        reset_tracking!(member)
    end
    return physical
end

#######
"""
This type will be used by a macro called `@react` to generate events.
```
@react tomove(physical) begin
    @match changed(physical.board[loc].occupant)
    @generate direction ∈ keys(DirectionDelta)
    @if begin
        agent = physical.board[loc].occupant
        agent > 0 &&
        physical.board[loc + direction] == 0 &&
        checkbounds(physical.board, loc + direction)
    end
    @action MoveTransition(agent, direction)
end
```
"""


####### transitions
abstract type BoardTransition end

"""
A dynamic generator of events. This looks at a changed place in the 
physical state and generates clock keys for events that could
depend on that place.
"""
function tomove_generate_event(physical, place_key, existing_events)
    # In this function, a variabled name that starts with `sym_` will be
    # generated by a macro, so it will be replaced with a unique name.

    # Select based on the place key.
    sym_array_name, sym_index_value, sym_struct_value... = place_key
    if sym_array_name != :board || sym_struct_value != (:occupant,)
        return nothing
    end
    # loc comes from matching the place key.
    loc_linear = sym_index_value
    loc_cartesian = physical.board_dim[loc_linear]

    # Not sure where to define this type BoardTransition.
    sym_create = BoardTransition[]
    sym_depends = Set{PlaceKey}[]
    sym_enabled = Function[]

    # Create the set of generative elements. We will do a for-loop over
    # these, but we need to insert code into the for-loop.
    # The top of the for-loop comes from the @generate macro.
    for direction in keys(DirectionDelta)
        # Inserted code at beginning.
        resetread(physical)

        # Now comes the code block from @if.
        sym_should_enable = begin
            agent = physical.board[loc_linear].occupant
            new_loc = loc_cartesian + DirectionDelta[direction]
            if checkbounds(Bool, physical.board_dim, new_loc)
                new_loc_linear = LinearIndices(physical.board_dim)[new_loc]
                agent > 0 &&
                  physical.board[new_loc_linear].occupant == 0
            else
                false
            end
        end

        # Inserted code at ending.
        if sym_should_enable
            input_places = wasread(physical)
            
            # This constructor call comes from the @action macro.
            transition = MoveTransition(agent, direction)

            # Then back to the inserted code.
            clock_key(transition) in existing_events && continue
            # The point of this is to make a new transition.
            push!(sym_create, transition)
            # That transition depends on the input places just read during @if.
            push!(sym_depends, input_places)
            # And we need to be able to disable the transition if
            # the @if condition is no longer true, so save that function.
            # Capture the current values in the closure
            let loc_linear_capture = loc_linear, direction_capture = direction
                push!(sym_enabled, function(physical)
                    # This will capture place and the generated variables.
                    loc_cartesian_capture = physical.board_dim[loc_linear_capture]
                    sym_should_enable = begin
                        agent = physical.board[loc_linear_capture].occupant
                        new_loc = loc_cartesian_capture + DirectionDelta[direction_capture]
                        if checkbounds(Bool, physical.board_dim, new_loc)
                            new_loc_linear = LinearIndices(physical.board_dim)[new_loc]
                            agent > 0 &&
                                physical.board[new_loc_linear].occupant == 0
                        else
                            false
                        end
                    end
                    return sym_should_enable
                end)
            end
        end
    end
    if isempty(sym_create)
        return nothing
    else
        return (create=sym_create, depends=sym_depends, enabled=sym_enabled)
    end
end


struct MoveTransition <: BoardTransition
    who::Int
    direction::Direction
end


clock_key(mt::MoveTransition) = ClockKey((:MoveTransition, mt.who, mt.direction))


function enable(tn::MoveTransition, sampler, physical, when, rng)
    enable!(sampler, clock_key(tn), Weibull(1.0), when, when, rng)
    return nothing
end


# Firing also transitions enabled -> disabled.
function fire!(tn::MoveTransition, physical)
    move_in_direction(physical, tn.who, tn.direction)
    return nothing
end


mutable struct SimulationFSM{Sampler}
    physical::PhysicalState
    sampler::Sampler
    when::Float64
    rng::Xoshiro
    # What is enabled.
    enabled_events::Dict{ClockKey,BoardTransition}
    # Given a place that changed, what events should be checked for updates.
    listen_places::Dict{PlaceKey,Set{ClockKey}}
    # Given an event, upon which places does it depend?
    event_enablers::Dict{ClockKey,Set{PlaceKey}}
    # For an event, how do we check if it is enabled?
    event_enabled::Dict{ClockKey,Function}
end


function SimulationFSM(physical, sampler, seed)
    return SimulationFSM{typeof(sampler)}(
        physical,
        sampler,
        0.0,
        Xoshiro(seed),
        Dict{ClockKey,BoardTransition}(),
        Dict{PlaceKey,ClockKey}(),
        Dict{ClockKey,PlaceKey}(),
        Dict{ClockKey,Function}()
    )
end


function isconsistent(sim::SimulationFSM)
    isconsistent(sim.physical) || return false
    # enabled_events has all events by their keys.
    for clock_key in keys(sim.enabled_events)
        # It must have an entry in the functions.
        @assert clock_key in keys(sim.event_enabled) "Event $clock_key is not enabled"
        # It must have an entry in the enablers.
        @assert clock_key in keys(sim.event_enablers) "Event $clock_key is not enabled"
        places = sim.event_enablers[clock_key]
        for place in places
            @assert place in keys(sim.listen_places) "Event $clock_key depends on place $place but it is not being listened to"
            @assert clock_key in sim.listen_places[place] "Event $clock_key depends on place $place but it is not being listened to"
        end
    end
    for (place, listeners) in sim.listen_places
        for clock_key in listeners
            @assert place in sim.event_enablers[clock_key] "Place $place is being listened to by $clock_key but it is not an enabler of that event"
        end
    end
    return true
end


"""
    deal_with_changes(sim::SimulationFSM)

An event changed the state. This function modifies events
to respond to changes in state.
"""
function deal_with_changes(sim::SimulationFSM)
    # The first job of this function is to create new events.

    for place in changed(sim.physical)
        clocks_listening = get(sim.listen_places, place, Set{ClockKey}())
        for clock_key in clocks_listening
            if !sim.event_enabled[clock_key](sim.physical)
                remove_event!(sim, clock_key)
            # elseif modify(clock_key, sim.physical)
            end
        end
        # It's possible this should pass in the set of all existing events.
        gen = tomove_generate_event(sim.physical, place, clocks_listening)
        isnothing(gen) && continue
        for evtidx in eachindex(gen.create)
            add_event = gen.create[evtidx]
            evtkey = clock_key(add_event)
            enable(add_event, sim.sampler, sim.physical, sim.when, sim.rng)
            sim.enabled_events[evtkey] = add_event
            sim.event_enabled[evtkey] = gen.enabled[evtidx]
            for hear_place in gen.depends[evtidx]
                push!(get!(sim.listen_places, hear_place, Set{ClockKey}()), evtkey)
            end
            sim.event_enablers[evtkey] = gen.depends[evtidx]
        end
    end
    accept(sim.physical)
end



function remove_event!(sim::SimulationFSM, clock_key::ClockKey)
    if clock_key in keys(sim.enabled_events)
        mt = sim.enabled_events[clock_key]
        places_depended_on = get(sim.event_enablers, clock_key, Set{PlaceKey}())
        for listen_place in places_depended_on
            filter!(ck -> ck != clock_key, sim.listen_places[listen_place])
            if isempty(sim.listen_places[listen_place])
                delete!(sim.listen_places, listen_place)
            end
        end
        if !isempty(places_depended_on)
            delete!(sim.event_enablers, clock_key)
        end
        delete!(sim.enabled_events, clock_key)
    else
        @warn "Tried to remove an event that does not exist: $clock_key"
    end
end


function run(event_count)
    Sampler = CombinedNextReaction{ClockKey,Float64}
    agent_cnt = 9
    raw_board = zeros(Int, 10, 10)
    for i in 1:agent_cnt
        raw_board[i] = i
    end
    physical = PhysicalState(raw_board)
    sim = SimulationFSM(
        physical,
        Sampler(),
        2947223
    )
    initialize!(sim.physical, agent_cnt, sim.rng)
    @assert isconsistent(sim.physical) "The initial physical state is inconsistent"
    deal_with_changes(sim)
    @assert isconsistent(sim)
    for i in 1:event_count
        (when, what) = next(sim.sampler, sim.when, sim.rng)
        if isfinite(when) && !isnothing(what)
            sim.when = when
            whatevent = sim.enabled_events[what]
            fire!(whatevent, sim.physical)
            remove_event!(sim, what)
            deal_with_changes(sim)
            @assert isconsistent(sim)
        end
    end
end


function initialize!(physical::PhysicalState, individuals::Int, rng)
    for ind_idx in 1:individuals
        loc = rand(rng, physical.board_dim)
        board_idx = LinearIndices(physical.board_dim)[loc]
        while physical.board[board_idx].occupant != 0
            loc = rand(rng, physical.board_dim)
            board_idx = LinearIndices(physical.board_dim)[loc]
        end
        move_agent(physical, ind_idx, loc)
    end
end
