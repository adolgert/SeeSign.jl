

function modify(tn::MoveTransition, physical)
    false
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


# Firing also transitions enabled -> disabled.
function fire!(tn::InfectTransition, physical)
    physical.health[tn.target] = Sick
    return nothing
end


# A transition from enabled -> disabled.
function bdisable(tn::InfectTransition, physical)
    return !isadjacent(physical, tn.source, tn.target) ||
        physical.health[tn.target] != Healthy ||
        physical.health[tn.source] != Sick
end
