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

const PlaceKey = Tuple{Symbol,CartesianIndex{2}}
# The last element is an int here but can be a direction.
const ClockKey = Tuple{Int,CartesianIndex{2},Int}
export run

# There are agents located on a 2D board.
# The state is a checkerboard. Each plaquette in the checkerboard
# is 0 or contains an individual identified by an integer.
# An individual has a health state.
mutable struct PhysicalState
    board::StepArray{Int,2}
    health::StepArray{Health,1}
    loc::Vector{CartesianIndex{2}}
    function PhysicalState(board::AbstractArray, health)
        loc = findall(x -> x != 0, board)
        new(StepArray(board), StepArray(health), loc)
    end
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
    places = Tuple{Symbol,CartesianIndex}[]
    for field in [f for f in fieldnames(physical) if isa(f, StepArray)]
        board = getproperty(physical, field)
        for ij in findall(x -> x, changed(board))
            push!(places, (field, ij))
        end
    end
    return places
end


"""
The arrays in a PhysicalState record that they have been modified.
This function erases the record of modifications.
"""
function accept(physical::PhysicalState)
    for field in [f for f in fieldnames(physical) if isa(f, StepArray)]
        accept(getproperty(physical, field))
    end
    return physical
end

####### transitions
abstract type BoardTransition end

"""
A dynamic generator of events. This looks at a changed place in the 
physical state and generates clock keys for events that could
depend on that place.
"""
function move_generate_event(physical, place)
    create = ClockKey[]
    array_name, location = place
    board = getproperty(physical, array_name)
    agent = board[location]
    if agent == 0
        for (direction, move) in DirectionDelta
            neighbor_loc = location + move
            neighbor = board[neighbor_loc]
            if neighbor != 0
                push!(create, (neighbor, neighbor_loc, DirectionOpposite[direction]))
            end
        end
    else
        return [(agent, location, Int(direction)) for direction in keys(DirectionDelta)]
    end
    return create
end


struct MoveTransition <: BoardTransition
    who::Int
    location::CartesianIndex{2}
    direction::Direction
end


clock_key(mt::MoveTransition) = ClockKey(mt.who, mt.location, mt.direction)


function check_places(physical, tn::MoveTransition)
    return PlaceKey[(:board, tn.location), (:board, tn.location + tn.direction)]
end


function enable(tn::MoveTransition, sampler, physical, when, rng)
    should = checkbounds(physical.board, tn.location + tn.direction) &&
        physical.board[tn.location] == tn.who &&
        physical.board[tn.location + tn.direction] == 0
    if should
        enable!(sampler, clock_key(tn), Weibull(1.0), when, when, rng)
    end
    return should
end


function modify(tn::MoveTransition, physical)
    false
end


# A transition from enabled -> disabled.
function bdisable(tn::MoveTransition, physical)
    return physical.board[tn.location + tn.direction] != 0
end


# Firing also transitions enabled -> disabled.
function fire!(tn::MoveTransition, physical)
    physical.board[tn.location] = 0
    newloc = tn.location + tn.direction
    physical.board[newloc] = tn.who
    physical.loc[tn.who] = newloc
    return nothing
end


struct InfectTransition <: BoardTransition
    source::Int
    target::Int
    health::Health
end


clock_key(mt::InfectTransition) = ClockKey(mt.source, CartesianIndex(mt.target, 0), mt.health)

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
    listen_places::Dict{PlaceKey,ClockKey}
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
    create_events = Set{ClockKey}()
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
