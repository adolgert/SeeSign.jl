import Base
using Distributions
using Logging

# Symbol for positive integer wildcard in event generation patterns - imported from regex_tuples.jl

# This will simulate agents moving on a board and infecting each other.

export DirectionDelta, DirectionOpposite, MoveTransition

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
    @assert seen_agents == Set(eachindex(physical.agent))
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
    
    @assert physical.board[old_board_idx].occupant == agentidx
    physical.board[old_board_idx].occupant = 0
    physical.agent[agentidx].loc = destination
    @assert physical.board[new_board_idx].occupant == 0
    physical.board[new_board_idx].occupant = agentidx
end


function move_in_direction(physical, agentidx, direction)
    newloc = physical.agent[agentidx].loc + DirectionDelta[direction]
    move_agent(physical, agentidx, newloc)
end

isneighbor(loca, locb) = sum(x^2 for x in (loca-locb).I) == 1

"""
Given the integer index into the linear board vector, return an iterator
over the linear indices of neighbors that are in bounds.
"""
function neighbor_lin(physical, boardlin)
    ci = physical.board_dim[boardlin]
    li = LinearIndices(physical.board_dim)
    return (li[ci + DirectionDelta[direction]] 
            for direction in keys(DirectionDelta) 
            if checkbounds(Bool, physical.board_dim, ci + DirectionDelta[direction]))
end


####### transitions
abstract type BoardTransition <: SimTransition end

struct MoveTransition <: BoardTransition
    who::Int  # An agent index.
    direction::Direction  # Direction that agent will move.
end

function precondition(mt::MoveTransition, physical)
    checkbounds(Bool, physical.agent, mt.who) || return false
    who_loc = physical.agent[mt.who].loc
    neighbor_loc = who_loc + DirectionDelta[mt.direction]
    checkbounds(Bool, physical.board_dim, neighbor_loc) || return false
    neighbor_lin = LinearIndices(physical.board_dim)[neighbor_loc]
    physical.board[neighbor_lin].occupant == 0
end

function generators(::Type{MoveTransition})
    return [
        EventGenerator{MoveTransition}(
            [:agent, ℤ, :loc],
            # An agent moved, and now there are new moves available to that agent.
            # The place we watch is the location of an agent.
            function agent_moved_gen(f::Function, physical, agent_who)
                agent_loc = physical.agent[agent_who].loc
                for direction in keys(DirectionDelta)
                    if checkbounds(
                        Bool, physical.board_dim, agent_loc + DirectionDelta[direction]
                    )
                        f(MoveTransition(agent_who, direction))
                    end
                end
            end,
        ),
        EventGenerator{MoveTransition}(
            [:board, ℤ, :occupant],
            # The neighbor of an agent got out of its way, so now the agent can move.
            # The place we watch is a board space that was previously occupied.
            function neighbor_moved_gen(f::Function, physical, board_lin)
                board_loc = physical.board_dim[board_lin]
                li = LinearIndices(physical.board_dim)
                for direction in keys(DirectionDelta)
                    move_loc = board_loc + DirectionDelta[direction]
                    if checkbounds(Bool, physical.board_dim, move_loc)
                        move_lin = li[move_loc]
                        who = physical.board[move_lin].occupant
                        move_direction = DirectionOpposite[direction]
                        f(MoveTransition(who, move_direction))
                    end
                end
            end,
        ),
    ]
end



"""
This function decides the rate of the transition, but whether the transition
is enabled was already decided by the @condition in the macro. That same
@condition will be used to disable the transition.
"""
function enable(tn::MoveTransition, sampler, physical, when, rng)
    enable!(sampler, clock_key(tn), Weibull(1.0), when, when, rng)
    return nothing
end

function reenable(tn::MoveTransition, sampler, physical, first_enabled, curtime, rng)
    @debug "Reenable $tn"
    enable!(sampler, clock_key(tn), Weibull(1.0), first_enabled, curtime, rng)
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




struct InfectTransition <: BoardTransition
    infectious::Int
    susceptible::Int
end


function precondition(it::InfectTransition, physical)
    return physical.agent[it.infectious].health == Sick &&
        physical.agent[it.susceptible].health == Healthy &&
        isneighbor(physical.agent[it.infectious].loc, physical.agent[it.susceptible].loc)
end


function generators(::Type{InfectTransition})
    return [
        EventGenerator{InfectTransition}(
            [:board, ℤ, :occupant],
            # Somebody showed up in this board location.
            function discordant_arrival(f::Function, physical, board_lin)
                mover = physical.board[board_lin].occupant
                mover > 0 || return
                mover_health = physical.agent[mover].health
                li = LinearIndices(physical.board_dim)
                board_loc = physical.board_dim[board_lin]
                for direction in keys(DirectionDelta)
                    # Beside them
                    neighbor_loc = board_loc + DirectionDelta[direction]
                    if checkbounds(Bool, physical.board_dim, neighbor_loc)
                        neighbor_lin = li[neighbor_loc]
                        neighbor = physical.board[neighbor_lin].occupant
                        # Was another agent.
                        if neighbor > 0
                            neighbor_health = physical.agent[neighbor].health
                            pair = [(mover_health, mover), (neighbor_health, neighbor)]
                            # They will sort into Health before Infectious
                            sort!(pair)
                            f(InfectTransition(pair[2][2], pair[1][2]))
                        end
                    end
                end
            end,
        ),
        EventGenerator{InfectTransition}(
            [:agent, ℤ, :health],
            # Without anybody moving, two agents next to each other could have one become
            # infected or one recover from infected to susceptible so that it could again
            # become infected. Our job in this generator is to observe two neighboring
            # agents, sort them according to health, and present them to the invariant
            # for infection.
            function sick_in_place(f::Function, physical, sicko)
                sick_health = physical.agent[sicko].health
                sick_loc = physical.agent[sicko].loc
                for direction in keys(DirectionDelta)
                    neighbor_loc = sick_loc + DirectionDelta[direction]
                    if checkbounds(Bool, physical.board_dim, neighbor_loc)
                        neighbor_lin = LinearIndices(physical.board_dim)[neighbor_loc]
                        neighbor = physical.board[neighbor_lin].occupant
                        if neighbor > 0
                            neighbor_health = physical.agent[neighbor].health
                            both = [(sick_health, sicko), (neighbor_health, neighbor)]
                            sort!(both)
                            f(InfectTransition(both[2][2], both[1][2]))
                        end
                    end
                end
            end,
        ),
    ]
end

function enable(tn::InfectTransition, sampler, physical, when, rng)
    enable!(sampler, clock_key(tn), Exponential(1.0), when, when, rng)
    return nothing
end

function reenable(tn::InfectTransition, sampler, physical, firstenabled, curtime, rng)
    # For exponential distributions, we don't care when it was first enabled.
    enable!(sampler, clock_key(tn), Exponential(1.0), curtime, curtime, rng)
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
    enabled = keys(sim.enabled_events)
    if allowed_events != enabled
        should_be_enabled = setdiff(allowed_events, enabled)
        should_be_disabled = setdiff(enabled, allowed_events)
        if !isempty(should_be_enabled) || !isempty(should_be_disabled)
            @show sim.physical

            if !isempty(should_be_enabled)
                @show "Should be enabled but aren't: $(should_be_enabled)"
            end
            if !isempty(should_be_disabled)
                @show "Are enabled but shouldn't be: $(should_be_disabled)"
            end
            @assert isempty(should_be_enabled) && isempty(should_be_disabled)
        end
    end
end


function run(event_count)
    Sampler = CombinedNextReaction{ClockKey,Float64}
    agent_cnt = 9
    raw_board = zeros(Int, 4, 4)
    for i in 1:agent_cnt
        raw_board[i] = i
    end
    physical = BoardState(raw_board)
    included_transitions = [
        MoveTransition,
        InfectTransition
    ]
    sim = SimulationFSM(
        physical,
        Sampler(),
        included_transitions,
        2947223
    )
    initializer = function(init_physical)
        initialize!(init_physical, agent_cnt, sim.rng)
    end
    stop_condition = function(physical, step_idx, event, when)
        @debug "Firing $what at $when"
        @assert isconsistent(physical) "The initial physical state is inconsistent"
        return step_idx >= event_count
    end
    run(sim, initializer, stop_condition)
end
