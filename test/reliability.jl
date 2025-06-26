module ReliabilitySim
using SeeSign
using CompetingClocks
using SeeSign: ClockKey
export run_reliability

using Distributions
@enum Activity ready working broken
# const ready = 1
# const working = 2
# const broken = 3

@tracked_struct Individual begin
    state::Activity
    work_age::Float64
    started_working_time::Float64
end

struct IndividualParams
    done_dist::LogUniform
    fail_dist::LogNormal
    repair_dist::Weibull
end

mutable struct IndividualState <: PhysicalState
    actors::TrackedVector{Individual}
    params::Vector{IndividualParams}
    workers_max::Int
    start_time::Float64
end

function IndividualState(actor_cnt, crew_size)
    done_rate = LogUniform(.8, 0.99) # Gamma(9.0, 0.2)
    break_rate = LogNormal(1.5, 0.4)
    repair_rate = Weibull(1.0, 2.0)
    p = IndividualParams(done_rate, break_rate, repair_rate)
    params = Vector{IndividualParams}(undef, actor_cnt)
    fill!(params, p)
    actors = TrackedVector{Individual}(undef, actor_cnt)
    for i in 1:actor_cnt
        actors[i] = Individual(ready, 0.0, 0.0)
    end
    return IndividualState(actors, params, crew_size, 0.0)
end

worker_cnt(physical::IndividualState) = length(physical.actors)

struct StartDay <: SimEvent end

precondition(event::StartDay, physical) = true

function generators(::Type{StartDay})
    return [
        EventGenerator(
            ToEvent,
            [:StartDay],
            function last_fired(f::Function, physical)
                f(StartDay())
            end
        )
    ]
end

function enable(evt::StartDay, sampler, physical, when, rng)
    desired_time = floor(when) + physical.start_time
    interval = desired_time - when
    enable!(sampler, clock_key(evt), Dirac(interval), when, when, rng)
end

function fire!(evt::StartDay, physical, when, rng)
    crew_cnt = 0
    for car in eachindex(physical.actors)
        if physical.actors[car].state == ready
            physical.actors[car].state = working
            physical.actors[car].started_working_time = when
            crew_cnt += 1
            if crew_cnt == physical.crew_size
                break
            end
        end
    end
end

struct EndDay <: SimEvent
    actor_idx::Int
end

precondition(evt::EndDay, physical) = physical.actors[evt.actor_idx].state == working

function generators(::Type{EndDay})
    return [
        EventGenerator(
            ToPlace,
            [:actors,  ℤ, :state],
            function started_working(f::Function, physical, actor)
                f(EndDay(actor))
            end
        )
    ]
end

function enable(evt::EndDay, sampler, physical, when, rng)
    enable!(sampler, clock_key(evt), physical.params[evt.actor_idx].done_dist, when, when, rng)
end

function fire!(evt::EndDay, physical, when, rng)
    physical.actors[evt.actor_idx].state = ready
    started_work = physical.actors[evt.actor_idx].started_working_time
    physical.actors[evt.actor_idx].work_age += when - started_work
end


struct Break <: SimEvent
    actor_idx::Int
end

precondition(evt::Break, physical) = physical.actors[evt.actor_idx].state == working

function generators(::Type{Break})
    return [
        EventGenerator(
            ToPlace,
            [:actors,  ℤ, :state],
            function started_working(f::Function, physical, actor)
                f(Break(actor))
            end
        )
    ]
end

function enable(evt::Break, sampler, physical, when, rng)
    started_ago = when - physical.params[evt.actor_idx].work_age
    enable!(sampler, clock_key(evt), physical.params[evt.actor_idx].fail_dist, started_ago, when, rng)
end

function fire!(evt::Break, physical, when, rng)
    physical.actors[evt.actor_idx].state = broken
    started_work = physical.actors[evt.actor_idx].started_working_time
    physical.actors[evt.actor_idx].work_age += when - started_work
end

struct Repair <: SimEvent
    actor_idx::Int
end

precondition(evt::Repair, physical) = physical.actors[evt.actor_idx].state == broken

function generators(::Type{Repair})
    return [
        EventGenerator(
            ToPlace,
            [:actors,  ℤ, :state],
            function started_working(f::Function, physical, actor)
                f(Repair(actor))
            end
        )
    ]
end

function enable(evt::Repair, sampler, physical, when, rng)
    enable!(sampler, clock_key(evt), physical.params[evt.actor_idx].repair_dist, when, when, rng)
end

function fire!(evt::Repair, physical, when, rng)
    physical.actors[evt.actor_idx].state = ready
    physical.actors[evt.actor_idx].work_age = 0.0
end

function initialize!(physical::PhysicalState, rng)
    for idx in eachindex(physical.actors)
        # This is a warm start to the problem.
        physical.actors[idx].work_age = rand(rng, Uniform(0, 10))
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


function run_reliability(days)
    agent_cnt = 15
    Sampler = CombinedNextReaction{ClockKey,Float64}
    physical = IndividualState(agent_cnt, 10)
    included_transitions = [
        StartDay,
        EndDay,
        Break,
        Repair
    ]
    sim = SimulationFSM(
        physical,
        Sampler(),
        included_transitions,
        2947223
    )
    initializer = function(init_physical)
        initialize!(init_physical, sim.rng)
    end
    # Stop-condition is called after the next event is chosen but before the
    # next event is fired. This way you can stop at an end time between events.
    stop_condition = function(physical, step_idx, event, when)
        return when > days
    end
    SeeSign.run(sim, initializer, stop_condition)
end

end
