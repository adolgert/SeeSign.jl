using Logging

export PhysicalState, changed, wasread, resetread, accept

"""
`PhysicalState` is an abstract type from which to inherit the state of a simulation.
A `PhysicalState` should put all mutable values, the values upon which events
depend, into `TrackedVector` objects. For instance:

```
@tracked_struct Square begin
    occupant::Int
    resistance::Float64
end


# Everything we know about an agent.
@tracked_struct Agent begin
    health::Health
    loc::CartesianIndex{2}
end

mutable struct BoardState <: PhysicalState
    board::TrackedVector{Square}
    agent::TrackedVector{Agent}
end
```

The `PhysicalState` may contain other properties, but those defined with
`TrackedVectors` are used to compute the next event in the simulation.
"""
abstract type PhysicalState end

"""
    isconsistent(physical_state)

A simulation in debug mode will assert `isconsistent(physical_state)` is true.
Override this to verify the physical state of your simulation.
"""
isconsistent(::PhysicalState) = true

"""
Iterate over all tracked vectors in the physical state.
"""
function over_tracked_physical_state(fcallback::Function, physical::T) where {T <: PhysicalState}
    for field_symbol in fieldnames(T)
        member = getproperty(physical, field_symbol)
        if isa(member, TrackedVector)
            fcallback(field_symbol, member)
        end
    end
end


"""
Return a list of changed places in the physical state.
A place for this state is a tuple of a symbol and the Cartesian index.
The symbol is the name of the array within the PhysicalState.
"""
function changed(physical::PhysicalState)
    places = Set{Tuple}()
    over_tracked_physical_state(physical) do fieldname, member
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
    over_tracked_physical_state(physical) do fieldname, member
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
    over_tracked_physical_state(physical) do _, member
        reset_gotten!(member)
    end
    return physical
end


"""
The arrays in a PhysicalState record that they have been modified.
This function erases the record of modifications.
"""
function accept(physical::PhysicalState)
    over_tracked_physical_state(physical) do _, member
        reset_tracking!(member)
    end
    return physical
end


"""
    capture_state_changes(f::Function, physical_state)

The callback function `f` will modify the physical state. This function
records which parts of the state were modified. The callback should have
no arguments and may return a result.
"""
function capture_state_changes(f::Function, physical)
    accept(physical)
    result = f()
    changes = changed(physical)
    return (;result, changes)
end


"""
    capture_state_reads(f::Function, physical_state)

The callback function `f` will read the physical state. This function
records which parts of the state were read. The callback should have
no arguments and may return a result.
"""
function capture_state_reads(f::Function, physical)
    resetread(physical)
    result = f()
    reads = wasread(physical)
    return (;result, reads)
end
