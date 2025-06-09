import Base
using Distributions
using Random
using SparseArrays
using Test
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


# There are agents located on a 2D board.
# The state is a checkerboard. Each plaquette in the checkerboard
# is 0 or contains an individual identified by an integer.
# An individual has a health state.
mutable struct PhysicalState
    board::TrackedVector{Square}
    agent::TrackedVector{Agent}
    # The tracked_vector is 1D but the board is 2D so we have to save conversion.
    board_dim::CartesianIndices{2, Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}}

    function PhysicalState(board::AbstractArray)
        linboard = TrackedVector{Square}(undef, length(board))
        for (i, val) in enumerate(board)
            linboard[i] = Square(val, 1.0)
        end
        location = findall(x -> x != 0, board)
        agent = TrackedVector{Agent}(undef, length(loc))
        for (i, loc) in enumerate(location)
            agent[i] = Agent(Healthy, loc, 0.0)
        end
        new(linboard, location, CartesianIndices(board))
    end
end


function move_in_direction(physical, agent, direction)
    oldboardidx = physical.board_dim[physical.loc[agent]]
    physical.loc[agent] += DirectionDelta[direction]
    newboardidx = physical.board_dim[physical.loc[agent]]
    physical.board[oldboardidx].occupant = 0
    physical.board[newboardidx].occupant = agent
end


"""
Whether two individuals are adjacent.
"""
function isadjacent(physical::PhysicalState, inda, indb)
    loca = physical.loc[inda]
    locb = physical.loc[indb]
    return loca == locb || any(
        x -> locb == loca + x,
        values(DirectionDelta)
    )
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function changed(physical::PhysicalState)
    places = Set{Tuple}()
    for field in [f for f in fieldnames(physical) if isa(f, TrackedVector)]
        union!(places, changed(getproperty(physical, field)))
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
    for field in [f for f in fieldnames(physical) if isa(f, TrackedVector)]
        union!(places, gotten(getproperty(physical, field)))
    end
    return places
end

"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function resetread(physical::PhysicalState)
    for field in [f for f in fieldnames(physical) if isa(f, TrackedVector)]
        reset_gotten!(getproperty(physical, field))
    end
    return physical
end


"""
The arrays in a PhysicalState record that they have been modified.
This function erases the record of modifications.
"""
function accept(physical::PhysicalState)
    for field in [f for f in fieldnames(physical) if isa(f, StepArray)]
        reset_tracking!(getproperty(physical, field))
    end
    return physical
end

#######
"""
This type will be used by a macro called `@react` to generate events.
```
@react tomove board[loc] begin
    @generate direction = keys(DirectionDelta)
    @if begin
        agent = board[loc]
        agent > 0 &&
        board[loc + direction] == 0 &&
        checkbounds(board, loc + direction)
    end
    @action MoveTransition(agent, direction)
end
```
I can think of another version of this:
```
@react tomove begin
    @match board[loc].occupant
    @generate [
        (:MoveTransition, board[loc], direction)
        for direction in keys(DirectionDelta)
        ]
    end
    @if (event, agent, direction) begin
        agent > 0 &&
        board[loc + direction] == 0 &&
        checkbounds(board, loc + direction)
    end
end
```

"""


####### transitions
abstract type BoardTransition end

"""
A dynamic generator of events. This looks at a changed place in the 
physical state and generates clock keys for events that could
depend on that place.

@when agentat(loc) && available(loc+direction) => (:move, loc, direction)

"""

function move_match_place(place_key)
    array_name, index_value, struct_value... = place_key
    # We don't match struct_value here, but we could.
    if array_name == :board
        return index_value
    else
        return nothing
    end
end


function tomove_enabled(physical, event_key)
    board = getproperty(physical, :board)
    health = getproperty(physical, :health)

    sym_should_enable = begin
        agent = board[loc]
        agent > 0 &&
            board[loc + direction] == 0 &&
            checkbounds(board, loc + direction)
    end
end


function tomove_generate_event(physical, place)
    # Select based on the place key.
    array_name, index_value, struct_value... = place_key
    # We don't match struct_value here, but we could.
    if array_name != :board
        return nothing
    end
    loc = index_value

    # Turn every StepArray from the physical into a local variable.
    board = getproperty(physical, :board)
    health = getproperty(physical, :health)

    # Not sure where to define this type BoardTransition.
    sym_create = BoardTransition[]
    sym_depends = Set{PlaceKey}[]

    # Create the set of generative elements. We will do a for-loop over
    # these, but we need to insert code into the for-loop.
    sym_generated = [
        (:MoveTransition, board[loc], direction)
        for direction in keys(DirectionDelta)
        ]
    for sym_generate in sym_generated
        # Inserted code at beginning.
        clear_reads(physical)

        # Now comes the code block.
        (event, agent, direction) = sym_generate
        sym_should_enable = begin
            agent > 0 &&
                board[loc + direction] == 0 &&
                checkbounds(board, loc + direction)
        end

        # Inserted code at ending.
        if sym_should_enable
            input_places = places_gotten(physical)
            
            # This constructor call comes from the @action macro.
            transition = MoveTransition(agent, direction)

            # Then back to the inserted code.
            push!(sym_create, transition)
            push!(sym_depends, input_places)
        end
    end
    if isempty(sym_create)
        return nothing
    else
        return sym_create, sym_depends
    end
end


struct MoveTransition <: BoardTransition
    who::Int
    direction::Direction
end


clock_key(mt::MoveTransition) = ClockKey(:MoveTransition, mt.who, mt.direction)


function enable(tn::MoveTransition, sampler, physical, when, rng)
    enable!(sampler, clock_key(tn), Weibull(1.0), when, when, rng)
    return nothing
end


# This is generated by the macro, as well.
function disable(tn::MoveTransition, physical)
    # Turn every StepArray from the physical into a local variable.
    board = getproperty(physical, :board)
    health = getproperty(physical, :health)

    (event, agent, direction) = clock_key(tn)
    sym_should_enable = begin
        agent > 0 &&
            board[loc + direction] == 0 &&
            checkbounds(board, loc + direction)
    end
    return !sym_should_enable
end


function modify(tn::MoveTransition, physical)
    false
end


# Firing also transitions enabled -> disabled.
function fire!(tn::MoveTransition, physical)
    move_in_direction(physical, tn.who, tn.direction)
    return nothing
end


struct InfectTransition <: BoardTransition
    source::Int
    target::Int
    health::Health
end


clock_key(mt::InfectTransition) = ClockKey(:InfectTransition, mt.source, mt.target, mt.health)


function health_generate_event(physical, place)
    create = ClockKey[]
    array_name, location = place
    if array_name == :board
        agent = physical.board[location]
        if agent > 0
            agent_health = physical.health[agent]
            for delta in values(DirectionDelta)
                neighbor = physical.board[location + delta]
                neighbor_health = physical.health[neighbor]
                if agent_health == Sick && neighbor_health == Healthy
                    push!(create, (agent, CartesianIndex(neighbor, 0), Infect))
                elseif agent_health == Health && neighbor_health == Sick
                    push!(create, (neighbor, CartesianIndex(agent, 0), Infect))
                end
            end
        end
    elseif array_name == :health
        agent = location[1]
        if physical.health[agent] == Sick
            for delta in values(DirectionDelta)
                neighbor_loc = physical.loc[agent] + delta
                neighbor = physical.board[neighbor_loc]
                if neighbor != 0 && physical.health[neighbor] == Healthy
                    push!(create, (agent, neighbor_loc, Infect))
                end
            end
        end
    end
    return create
end

function check_places(physical, tn::InfectTransition)
    return PlaceKey[
        (:board, physical.loc[tn.source]), (:board, physical.loc[tn.target]),
        (:health, tn.source), (:health, tn.target)
        ]
end


function enable(tn::InfectTransition, sampler, physical, when, rng)
    should = physical.health[tn.source] == Sick &&
        physical.health[tn.target] == Healthy
    if should
        enable!(sampler, clock_key(tn), Exponential(1.0), when, when, rng)
    end
    return should
end


function modify(tn::InfectTransition, physical)
    false
end


# A transition from enabled -> disabled.
function bdisable(tn::InfectTransition, physical)
    return !isadjacent(physical, tn.source, tn.target) ||
        physical.health[tn.target] != Healthy ||
        physical.health[tn.source] != Sick
end


# Firing also transitions enabled -> disabled.
function fire!(tn::InfectTransition, physical)
    physical.health[tn.target] = Sick
    return nothing
end


mutable struct SimulationFSM{Sampler}
    physical::PhysicalState
    sampler::Sampler
    when::Float64
    rng::Xoshiro
    enabled_events::Dict{ClockKey,BoardTransition}
    listen_places::Dict{PlaceKey,Set{ClockKey}}
    event_enablers::Dict{ClockKey,Set{PlaceKey}}
end


function SimulationFSM(physical, sampler, seed)
    return SimulationFSM{typeof(sampler)}(
        physical,
        sampler,
        0.0,
        Xoshiro(seed),
        Dict{ClockKey,BoardTransition}(),
        Dict{PlaceKey,ClockKey}()
    )
end


function remove_event!(sim::SimulationFSM, clock_key::ClockKey)
    if clock_key in keys(sim.enabled_events)
        mt = sim.enabled_events[clock_key]
        for listen in check_places(sim.physical, mt)
            filter!(ck -> ck != clock_key, sim.listen_places[listen])
        end
        if empty(sim.listen_places[mt.location])
            delete!(sim.listen_places, mt.location)
        end
        delete!(sim.enabled_events, clock_key)
    end
end


"""
    deal_with_changes(sim::SimulationFSM)

An event changed the state. This function modifies events
to respond to changes in state.
"""
function deal_with_changes(sim::SimulationFSM)
    # The first job of this function is to create new events.
    create_events = Set{ClockKey}()
    # When it creates events, it also records the enabling rule for each event.
    # An enabling rule is an invariant defined on a set of places.
    for place in changed(sim.physical)
        # Each event recorded which places affect that event.
        if place ∈ keys(listen_places)
            for clock_key in listen_places[place]
                if bdisable(clock_key, sim.physical)
                    remove_event!(sim, clock_key)
                # elseif modify(clock_key, sim.physical)
                end
            end
        else
            mt = MoveTransition(clock_key(place)...)
            listen_places[place] = mt
        end
        union!(create_events, move_generate_event(physical, place))
        union!(create_events, health_generate_event(physical, place))
    end
    # Don't enable an event that is already enabled.
    setdiff!(create_events, keys(enabled_events))
    for clock_key in create_events
        mt = MoveTransition(clock_key...)
        if enable(mt, sim.sampler, sim.physical, sim.when, sim.rng)
            enabled_events[clock_key] = mt
            for listen in check_places(physical, mt)
                if listen ∉ keys(listen_places)
                    listen_places[listen] = ClockKey[]
                end
                push!(listen_places[listen], clock_key)
            end
        end
    end
    accept(sim.physical)
end


function run(event_count)
    Sampler = CombinedNextReaction{ClockKey,Float64}
    agent_cnt = 9
    physical = PhysicalState(zeros(Int, 100, 100), ones(Int, agent_cnt))
    sim = SimulationFSM(
        physical,
        Sampler(),
        2947223
    )
    initialize!(sim.physical, agent_cnt, sim.rng)
    deal_with_changes(sim)
    for i in 1:event_count
        (when, what) = next(sim.sampler, sim.when, sim.rng)
        if isfinite(when) && !isnothing(what)
            sim.when = when
            fire!(sim.physical, what)
            remove_event!(sim, what)
            deal_with_changes(sim)
        end
    end
end


function initialize!(physical::PhysicalState, individuals::Int, rng)
    for ind_idx in 1:individuals
        loc = rand(rng, CartesianIndices(physical.board))
        while physical.board[loc] != 0
            loc = rand(rng, CartesianIndices(physical.board))
        end
        locations[ind_idx] = loc
        physical.board[loc] = ind_idx
    end
end
