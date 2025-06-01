import Base
using Distributions
using Random
using SparseArrays
using Test
using CompetingClocks


# They can move in any of four directions.
@enum Direction Up Left Down Right
const DirectionDelta = Dict(
    Up => CartesianIndex(-1, 0),
    Left => CartesianIndex(0, -1),
    Down => CartesianIndex(1, 0),
    Right => CartesianIndex(0, 1),
    );
const DirectionOpposite = Dict(
    Up => Down, Down => Up, Left => Right, Right => Left
)

const PlaceKey = Tuple{Symbol,CartesianIndex{2}}
const ClockKey = Tuple{Int,CartesianIndex{2},Direction}
export run

# The state is a checkerboard. Each plaquette in the checkerboard
# is 0 or contains an individual identified by an integer.
mutable struct PhysicalState
    board::StepArray{Int,2}
    function PhysicalState(board::AbstractArray)
        sa = StepArray{Int,2}(undef, size(board))
        copy!(sa, board)
        accept(sa)
        new(sa)
    end
end


function changed(physical::PhysicalState)
    places = Tuple{Symbol,CartesianIndex}[]
    for ij in findall(x -> x, changed(physical.board))
        push!(places, (:board, ij))
    end
    return places
end


function accept(physical::PhysicalState)
    accept(physical.board)
    return physical
end


function place_generate_event(physical, place)
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
        return [(agent, location, direction) for direction in keys(DirectionDelta)]
    end
    return create
end


struct MoveTransition
    who::Int
    location::CartesianIndex{2}
    direction::Direction
end


clock_key(mt::MoveTransition) = ClockKey(mt.who, mt.location, mt.direction)


function check_places(tn::MoveTransition)
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
    physical.board[tn.location + tn.direction] = tn.who
    return nothing
end


mutable struct SimulationFSM{Sampler}
    physical::PhysicalState
    sampler::Sampler
    when::Float64
    rng::Xoshiro
    enabled_events::Dict{ClockKey,MoveTransition}
    listen_places::Dict{PlaceKey,ClockKey}
end


function SimulationFSM(physical, sampler, seed)
    return SimulationFSM{typeof(sampler)}(
        physical,
        sampler,
        0.0,
        Xoshiro(seed),
        Dict{ClockKey,MoveTransition}(),
        Dict{PlaceKey,ClockKey}()
    )
end


function deal_with_changes(sim::SimulationFSM)
    create_events = Set{ClockKey}()
    for place in changed(sim.physical)
        if place ∈ keys(listen_places)
            for clock_key in listen_places[place]
                if bdisable(clock_key, sim.physical)
                    disable!(sim.sampler, clock_key, sim.when)
                    for listen in check_places(clock_key)
                        filter!(ck -> ck != clock_key, listen_places[listen])
                    end
                    if empty(listen_places[place])
                        delete!(listen_places, place)
                    end
                    delete!(enabled_events, clock_key)
                # elseif modify(clock_key, sim.physical)
                end
            end
        else
            mt = MoveTransition(clock_key(place)...)
            listen_places[place] = mt
        end
        union!(create_events, place_generate_event(physical, place))
    end
    setdiff!(create_events, keys(enabled_events))
    for clock_key in create_events
        mt = MoveTransition(clock_key...)
        if enable(mt, sim.sampler, sim.physical, sim.when, sim.rng)
            enabled_events[clock_key] = mt
            for listen in check_places(mt)
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
    physical = PhysicalState(zeros(Int, 100, 100))
    sim = SimulationFSM(
        physical,
        Sampler(),
        2947223
    )
    initialize!(sim.physical, 9, sim.rng)
    deal_with_changes(sim)
    for i in 1:event_count
        (when, what) = next(sim.sampler, sim.when, sim.rng)
        if isfinite(when) && !isnothing(what)
            sim.when = when
            fire!(sim.physical, what)
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
