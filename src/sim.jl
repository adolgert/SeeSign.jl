import Base
using Distributions
using Logging

# Symbol for positive integer wildcard in event generation patterns - imported from regex_tuples.jl

# This will simulate agents moving on a board and infecting each other.

export MoveTransition

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
    loc::Int  # Points to the relevant square.
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
    geom::BoardGeometry

    function BoardState(board::AbstractArray)
        agent_cnt = length(findall(x -> x != 0, board))
        agent = TrackedVector{Agent}(undef, agent_cnt)
        linboard = TrackedVector{Square}(undef, length(board))
        for (i, val) in enumerate(board)
            linboard[i] = Square(val, 1.0)
            if val > 0
                if val <= agent_cnt
                    agent[val] = Agent(Healthy, i, 0.0)
                else
                    @error "Expected the board to have agents from 1 to $(agent_cnt), found $val"
                end
            end
        end
        new(linboard, agent, BoardGeometry(size(board)))
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
    ci = state.geom.cartesian_indices
    li = state.geom.linear_indices
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
            if agent_loc != square
                @error "Inconsistent board: square $square has occupant $agent_idx at location $agent_loc but should be at $square"
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
    @assert physical.board[old_loc].occupant == agentidx
    physical.board[old_loc].occupant = 0
    physical.agent[agentidx].loc = destination
    @assert physical.board[destination].occupant == 0
    physical.board[destination].occupant = agentidx
end


function move_in_direction(physical, agentidx, direction)
    newloc = neighbor_in_direction(physical.geom, physical.agent[agentidx].loc, direction)
    move_agent(physical, agentidx, newloc)
end


####### transitions
abstract type BoardTransition <: SimEvent end

struct MoveTransition <: BoardTransition; who::Int; direction::Direction; end

function precondition(mt::MoveTransition, physical)
    checkbounds(Bool, physical.agent, mt.who) || return false
    who_loc = physical.agent[mt.who].loc
    neighbor_loc = neighbor_in_direction(physical.geom, who_loc, mt.direction)
    isnothing(neighbor_loc) && return false
    physical.board[neighbor_loc].occupant == 0
end

function generators(::Type{MoveTransition})
    return [
        EventGenerator(
            ToPlace,
            [:agent, ℤ, :loc],
            # An agent moved, and now there are new moves available to that agent.
            # The place we watch is the location of an agent.
            function(f::Function, physical, agent_who)
                agent_loc = physical.agent[agent_who].loc
                for direction in valid_directions(physical.geom, agent_loc)
                    f(MoveTransition(agent_who, direction))
                end
            end,
        ),
        EventGenerator(
            ToPlace,
            [:board, ℤ, :occupant],
            # The neighbor of an agent got out of its way, so now the agent can move.
            # The place we watch is a board space that was previously occupied.
            function(f::Function, physical, board_lin)
                for beside in neighbors(physical.geom, board_lin)
                    reverse = direction_between(physical.geom, beside, board_lin)
                    f(MoveTransition(physical.board[beside].occupant, reverse))
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
function enable(tn::MoveTransition, physical, when)
    return (Weibull(1.0), when)
end

function reenable(tn::MoveTransition, physical, first_enabled, curtime)
    @debug "Reenable $tn"
    return (Weibull(1.0), first_enabled)
end


# Firing also transitions enabled -> disabled.
function fire!(tn::MoveTransition, physical, when, rng)
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
        @assert physical.board[loc].occupant == agent_idx
        for direction in valid_directions(physical.geom, loc)
            new_loc = neighbor_in_direction(physical.geom, loc, direction)
            if physical.board[new_loc].occupant == 0
                push!(moves, ClockKey((:MoveTransition, agent_idx, direction)))
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
        are_neighbors(
            physical.geom,
            physical.agent[it.infectious].loc,
            physical.agent[it.susceptible].loc
            )
end


function generators(::Type{InfectTransition})
    return [
        EventGenerator(
            ToPlace,
            [:board, ℤ, :occupant],
            # Somebody showed up in this board location.
            function discordant_arrival(f::Function, physical, board_lin)
                mover = physical.board[board_lin].occupant
                mover > 0 || return
                for loc in neighbors(physical.geom, physical.agent[mover].loc)
                    next_door = physical.board[loc].occupant
                    if next_door > 0
                        # The precondition will sort out if any of these applies.
                        f(InfectTransition(mover, next_door))
                        f(InfectTransition(next_door, mover))
                    end
                end
            end,
        ),
        EventGenerator(
            ToPlace,
            [:agent, ℤ, :health],
            # Without anybody moving, two agents next to each other could have one become
            # infected or one recover from infected to susceptible so that it could again
            # become infected. Our job in this generator is to observe two neighboring
            # agents, sort them according to health, and present them to the invariant
            # for infection.
            function sick_in_place(f::Function, physical, sicko)
                sick_health = physical.agent[sicko].health
                sick_loc = physical.agent[sicko].loc
                for next_door in neighbors(physical.geom, sick_loc)
                    friend = physical.board[next_door].occupant
                    if friend > 0
                        f(InfectTransition(sicko, friend))
                        f(InfectTransition(friend, sicko))
                    end
                end
            end,
        ),
    ]
end

function enable(tn::InfectTransition, physical, when)
    return (Exponential(1.0), when)
end

function reenable(tn::InfectTransition, physical, firstenabled, curtime)
    # For exponential distributions, we don't care when it was first enabled.
    return (Exponential(1.0), curtime)
end

function fire!(it::InfectTransition, physical, when, rng)
    physical.agent[it.susceptible].health = Sick
end


function initialize!(physical::PhysicalState, individuals::Int, rng)
    for ind_idx in 1:individuals
        loc = random_position(physical.geom, rng)
        while physical.board[loc].occupant != 0
            loc = random_position(physical.geom, rng)
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
            for neighbor_loc in neighbors(physical.geom, loc)
                neighbor_agent = physical.board[neighbor_loc].occupant
                if neighbor_agent > 0 && physical.agent[neighbor_agent].health == Healthy
                    push!(infects, ClockKey((:InfectTransition, agent_idx, neighbor_agent)))
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


struct TrajectoryEntry
    event::Tuple
    when::Float64
end

struct TrajectorySave
    trajectory::Vector{TrajectoryEntry}
    TrajectorySave() = new(Vector{TrajectoryEntry}())
end

function observe(te::TrajectoryEntry, physical, when, event, changed_places)
    @debug "Firing $event at $when"
    push!(te.trajectory, TrajectoryEntry(clock_key(event), when))
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
    # Stop-condition is called after the next event is chosen but before the
    # next event is fired. This way you can stop at an end time between events.
    stop_condition = function(physical, step_idx, event, when)
        @assert isconsistent(physical) "The initial physical state is inconsistent"
        return step_idx >= event_count
    end
    run(sim, initializer, stop_condition)
end
