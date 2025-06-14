import Base
using Distributions
using Logging

# This will simulate agents moving on a board and infecting each other.

export DirectionDelta, DirectionOpposite

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

# They have health states.
@enum Health NoHealth Healthy Sick Dead
@enum HealthEvent NoEvent Infect Recover Die

const PlaceKey = Tuple
# The last element is an int here but can be a direction.
const ClockKey = Tuple
export run

# This is a square on the board.
# The @tracked macro will let us see changes to the fields
# so we can update the bipartite graph of Places and Transitions.
@tracked_struct Square begin
    occupant::Int
    resistance::Float64
end


# Everything we know about an agent.
@tracked_struct Agent begin
    health::Health
    loc::CartesianIndex{2}
    birthtime::Float64
end

export ascii_to_array

"""
For testing, convert an ASCII image of a board into a 2D array of integers.
"""
function ascii_to_array(ascii_image::String)::Array{Int,2}
    lines = split(strip(ascii_image), '\n')
    rows = length(lines)
    cols = length(split(strip(lines[1])))
    
    result = zeros(Int, rows, cols)
    for (i, line) in enumerate(lines)
        values = parse.(Int, split(strip(line)))
        result[i, :] = values
    end
    return result
end


const BoardIndices = CartesianIndices{2, Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}}

# There are agents located on a 2D board.
# The state is a checkerboard. Each plaquette in the checkerboard
# is 0 or contains an individual identified by an integer.
# An individual has a health state.
mutable struct BoardState <: PhysicalState
    board::TrackedVector{Square}
    agent::TrackedVector{Agent}
    # The tracked_vector is 1D but the board is 2D so we have to save conversion.
    board_dim::BoardIndices

    function BoardState(board::AbstractArray)
        linboard = TrackedVector{Square}(undef, length(board))
        for (i, val) in enumerate(board)
            linboard[i] = Square(val, 1.0)
        end
        location::Vector{CartesianIndex{2}} = findall(x -> x != 0, board)
        agent = TrackedVector{Agent}(undef, length(location))
        for foundidx in eachindex(location)
            loc = location[foundidx]
            agentidx = board[loc]
            agent[agentidx] = Agent(Healthy, loc, 0.0)
        end
        new(linboard, agent, CartesianIndices(board))
    end
end

"""
Pretty print the board state.
"""
function Base.show(io::IO, state::BoardState)
    println(io, "BoardState")
    infected = [
        agentidx for agentidx in eachindex(state.agent)
            if state.agent[agentidx].health == Sick
            ]
    println(io, "Infected agents: ", infected)
    ci = state.board_dim
    li = LinearIndices(ci)
    for rowidx in axes(ci, 1)
        occ = [string(state.board[li[rowidx, colidx]].occupant)
                for colidx in axes(ci, 2)
                ]
        println(io, join(occ, " "))
    end
end


"""
Double-check the board state.
"""
function isconsistent(physical::BoardState)
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
Because the array of board squares is 1D but the board is 2D, there is translation
when you move an agent.
"""
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


####### transitions
abstract type BoardTransition <: SimTransition end

"""
A dynamic generator of events. This looks at a changed place in the 
physical state and generates clock keys for events that could
depend on that place.
"""
@react tomove(physical) begin
    @onevent changed(physical.board[loc].occupant)
    @generate direction ∈ keys(DirectionDelta)
    @condition begin
        agent = physical.board[loc].occupant
        loc_cartesian = physical.board_dim[loc]
        new_loc = loc_cartesian + DirectionDelta[direction]
        if checkbounds(Bool, physical.board_dim, new_loc)
            new_loc_linear = LinearIndices(physical.board_dim)[new_loc]
            agent > 0 &&
            physical.board[new_loc_linear].occupant == 0
        else
            false
        end
    end
    @action MoveTransition(agent, direction)
end


"""
This is the case where a neighbor couldn't move because it was blocked
but now the space is free and it can move.
"""
@react tospace(physical) begin
    @onevent changed(physical.board[space].occupant)
    @generate direction ∈ keys(DirectionDelta)
    @condition begin
            neighbor = physical.board[space].occupant
            loc_cartesian = physical.board_dim[space]
            mover_loc = loc_cartesian + DirectionDelta[direction]
            if neighbor == 0 && checkbounds(Bool, physical.board_dim, mover_loc)
                mover_loc_linear = LinearIndices(physical.board_dim)[mover_loc]
                mover = physical.board[mover_loc_linear].occupant
                move_direction = DirectionOpposite[direction]
                mover > 0
            else
                false
            end
        end
    @action MoveTransition(mover, move_direction)
end


export MoveTransition, clock_key, enable, fire!, allowed_moves


struct MoveTransition <: BoardTransition
    who::Int
    direction::Direction
end


clock_key(mt::MoveTransition) = ClockKey((:MoveTransition, mt.who, mt.direction))


"""
This function decides the rate of the transition, but whether the transition
is enabled was already decided by the @condition in the macro. That same
@condition will be used to disable the transition.
"""
function enable(tn::MoveTransition, sampler, physical, when, rng)
    enable!(sampler, clock_key(tn), Weibull(1.0), when, when, rng)
    return nothing
end


# Firing also transitions enabled -> disabled.
function fire!(tn::MoveTransition, physical)
    move_in_direction(physical, tn.who, tn.direction)
    return nothing
end


"""
For debugging, list every allowed movement transition.
"""
function allowed_moves(physical)
    moves = Vector{ClockKey}()
    for agent_idx in eachindex(physical.agent)
        loc = physical.agent[agent_idx].loc
        loc_linear = LinearIndices(physical.board_dim)[loc]
        @assert physical.board[loc_linear].occupant == agent_idx
        for direction in keys(DirectionDelta)
            new_loc = loc + DirectionDelta[direction]
            if checkbounds(Bool, physical.board_dim, new_loc)
                new_loc_linear = LinearIndices(physical.board_dim)[new_loc]
                if physical.board[new_loc_linear].occupant == 0
                    push!(moves, ClockKey((:MoveTransition, agent_idx, direction)))
                end
            end
        end
    end
    return moves
end


"""
I found writing the @condition macro to be complicated, so I wrote a helper
function. The trick with the @condition macro is that it will run inside
a begin-end block, so there is no way to short-circuit the evalutation. You can
write code like that, but it gets complicated. This macro uses short-cicuiting
to make it easier.
"""
function sick_movement(physical, who_agent, direction)
    who_health = physical.agent[who_agent].health
    neighbor_cart_loc = physical.agent[who_agent].loc + DirectionDelta[direction]
    checkbounds(Bool, physical.board_dim, neighbor_cart_loc) || return (false, 0, 0)

    neighbor_loc_linear = LinearIndices(physical.board_dim)[neighbor_cart_loc]
    neighbor_agent = physical.board[neighbor_loc_linear].occupant
    neighbor_agent > 0 || return (false, 0, 0)
    neighbor_health = physical.agent[neighbor_agent].health
    healths = [(who_health, who_agent), (neighbor_health, neighbor_agent)]
    sort!(healths)
    if healths[1][1] == Healthy && healths[2][1] == Sick
        # Susceptible moves next to infected.
        # The susceptible agent becomes infected.
        move_agent(physical, who_agent, neighbor_cart_loc)
        physical.agent[who_agent].health = Sick
        return (true, healths[1][2], healths[2][2])
    else
        return (false, 0, 0)
    end
end


"""
Let's add a process for susceptible-infected.
There are two cases to handle that have to do with movement.
1. Susceptible moves next to infected.
2. Infected moves next to susceptible.
"""
@react toencroach(physical) begin
    @onevent changed(physical.agent[who].loc)
    @generate direction ∈ keys(DirectionDelta)
    @condition begin
            agent = physical.board[who].occupant
            if agent > 0
                result, susceptible, infectious = sick_movement(physical, agent, direction)
                result
            else
                false
            end
        end
    @action InfectTransition(infectious, susceptible)
end



"""
This is the case where a neighbor didn't move but became infected in place
and can therefore now infect a neighbor.
"""
@react tosickfriend(physical) begin
    @onevent changed(physical.agent[who].health)
    @generate direction ∈ keys(DirectionDelta)
    @condition begin
            health = physical.agent[who].health
            neighbor_cart_loc = physical.agent[who].loc + DirectionDelta[direction]
            if health == Sick && checkbounds(Bool, physical.board_dim, neighbor_cart_loc)
                neighbor_loc_linear = LinearIndices(physical.board_dim)[neighbor_cart_loc]
                neighbor = physical.board[neighbor_loc_linear].occupant
                if neighbor > 0
                    neighbor_health = physical.agent[neighbor].health
                    # If the neighbor is susceptible, then it can become infected.
                    neighbor_health == Healthy
                else
                    false
                end
            else
                false
            end
        end
    @action InfectTransition(who, neighbor)
end



struct InfectTransition <: BoardTransition
    infectious::Int
    susceptible::Int
end

clock_key(it::InfectTransition) = ClockKey((:InfectTransition, it.infectious, it.susceptible))

function enable(tn::InfectTransition, sampler, physical, when, rng)
    enable!(sampler, clock_key(tn), Exponential(1.0), when, when, rng)
    return nothing
end

function fire!(it::InfectTransition, physical)
    physical.agent[it.susceptible].health = Sick
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


"""
For debugging, look at every allowed infection.
"""
function allowed_infects(physical)
    infects = Vector{ClockKey}()
    for agent_idx in eachindex(physical.agent)
        if physical.agent[agent_idx].health == Sick
            loc = physical.agent[agent_idx].loc
            for direction in keys(DirectionDelta)
                neighbor_loc = loc + DirectionDelta[direction]
                if checkbounds(Bool, physical.board_dim, neighbor_loc)
                    neighbor_loc_linear = LinearIndices(physical.board_dim)[neighbor_loc]
                    neighbor_agent = physical.board[neighbor_loc_linear].occupant
                    if neighbor_agent > 0 && physical.agent[neighbor_agent].health == Healthy
                        push!(infects, ClockKey((:InfectTransition, agent_idx, neighbor_agent)))
                    end
                end
            end
        end
    end
    return infects
end


"""
More debugging, check that all events are correct.
"""
function check_events(sim)
    moves = allowed_moves(sim.physical)
    infects = allowed_infects(sim.physical)
    allowed_events = union(moves, infects)
    if allowed_events != keys(sim.enabled_events)
        not_enabled = setdiff(allowed_events, keys(sim.enabled_events))
        not_allowed = setdiff(keys(sim.enabled_events), allowed_events)
        if !isempty(not_enabled)
            @error "Should be enabled $(not_enabled)"
        end
        if !isempty(not_allowed)
            @error "Should be allowed $(not_allowed)"
        end
        @show sim.physical
        @assert isempty(not_enabled) && isempty(not_allowed)
    end
end


function run(event_count)
    Sampler = CombinedNextReaction{ClockKey,Float64}
    agent_cnt = 9
    raw_board = zeros(Int, 10, 10)
    for i in 1:agent_cnt
        raw_board[i] = i
    end
    physical = BoardState(raw_board)
    event_rules = [
        tomove_generate_event,
        tospace_generate_event,
        toencroach_generate_event,
        tosickfriend_generate_event
    ]
    sim = SimulationFSM(
        physical,
        Sampler(),
        event_rules,
        2947223
    )
    initialize!(sim.physical, agent_cnt, sim.rng)
    @assert isconsistent(sim.physical) "The initial physical state is inconsistent"
    deal_with_changes(sim)
    check_events(sim)
    @assert isconsistent(sim.physical)
    for i in 1:event_count
        (when, what) = next(sim.sampler, sim.when, sim.rng)
        if isfinite(when) && !isnothing(what)
            @debug "Firing $what at $when"
            fire!(sim, when, what)
            @assert isconsistent(sim.physical)
        else
            @info "No more events to process after $i iterations."
            break
        end
        check_events(sim)
    end
end
