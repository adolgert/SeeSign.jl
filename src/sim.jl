import Base
using Distributions
using Random
using SparseArrays
using Test
using CompetingClocks

mutable struct PhysicalState
    board::SparseMatrixCSC{Int64, Int64}
end

# They can move in any of four directions.
@enum Direction Up Left Down Right
const DirectionDelta = Dict(
    Up => CartesianIndex(-1, 0),
    Left => CartesianIndex(0, -1),
    Down => CartesianIndex(1, 0),
    Right => CartesianIndex(0, 1),
    );


mutable struct SimulationFSM{Sampler}
    physical::PhysicalState
    sampler::Sampler
    when::Float64
    rng::Xoshiro
end

const ClockKey = Tuple{Int,CartesianIndex{2},Direction}
export run


function run(event_count)
    Sampler = CombinedNextReaction{ClockKey,Float64}
    physical = PhysicalState(zeros(Int, 100, 100))
    sim = SimulationFSM{Sampler}(
        physical,
        Sampler(),
        0.0,
        Xoshiro(2947223)
    )
    initialize!(sim.physical, 9, sim.rng)
    current_events = allowed_moves(sim.physical)
    for event_id in current_events
        enable!(sim.sampler, event_id, Weibull(1.0), 0.0, 0.0, sim.rng)
    end

    for i in 1:event_count
        (when, what) = next(sim.sampler, sim.when, sim.rng)
        if isfinite(when) && !isnothing(what)
            sim.when = when
            move!(sim.physical, what)
            next_events = allowed_moves(sim.physical)
            for remove_event in setdiff(current_events, next_events)
                disable!(sim.sampler, remove_event, when)
            end
            for add_event in setdiff(next_events, current_events)
                enable!(sim.sampler, add_event, Weibull(1.0), when, when, sim.rng)
            end
            current_events = next_events
            @show (when, what)
        end
    end
end;

function allowed_moves(physical::PhysicalState)
    allowed = Set{ClockKey}()
    row, col, value = findnz(physical.board)
    for ind_idx in eachindex(value)
        location = CartesianIndex((row[ind_idx], col[ind_idx]))
        for (direction, offset) in DirectionDelta
            if checkbounds(Bool, physical.board, location + offset)
                if physical.board[location + offset] == 0
                    push!(allowed, (value[ind_idx], location, direction))
                end
            end
        end
    end
    return allowed
end;

function initialize!(physical::PhysicalState, individuals::Int, rng)
    physical.board .= 0
    dropzeros!(physical.board)
    locations = zeros(CartesianIndex{2}, individuals)
    for ind_idx in 1:individuals
        loc = rand(rng, CartesianIndices(physical.board))
        while physical.board[loc] != 0
            loc = rand(rng, CartesianIndices(physical.board))
        end
        locations[ind_idx] = loc
        physical.board[loc] = ind_idx
    end
end;


function move!(physical::PhysicalState, event_id)
    (individual, previous_location, direction) = event_id
    next_location = previous_location + DirectionDelta[direction]
    # This sets the previous board value to zero.
    SparseArrays.dropstored!(physical.board, previous_location.I...)
    physical.board[next_location] = individual
end;

