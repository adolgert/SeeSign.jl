using Logging

export SimEvent, InitializeEvent, clock_key, key_clock

"""
  SimEvent

This abstract type is the parent of all transitions in the system.
"""
abstract type SimEvent end

"""
InitializeEvent is a concrete transition type that represents the first event
in the system, initialization.
"""
struct InitializeEvent <: SimEvent end

"""
    clock_key(::SimEvent)::Tuple

All `SimEvent` objects are immutable structs that represent events but
don't carry any mutable state. A clock key is a tuple version of an event.
"""
@generated function clock_key(event::T) where T <: SimEvent
    type_symbol = QuoteNode(nameof(T))
    field_exprs = [:(event.$field) for field in fieldnames(T)]
    return :($type_symbol, $(field_exprs...))
end

"""
    key_clock(key::Tuple, event_dict::Dict{Symbol, DataType})::SimEvent

Takes a tuple of the form (:symbol, arg, arg) and a dictionary mapping symbols
to struct types, and returns an instantiation of the struct named by :symbol.
"""
function key_clock(key::Tuple, event_dict::Dict{Symbol, DataType})
    if !isa(key[1], Symbol)
        error("First element of tuple must be a Symbol")
    end
    
    type_symbol = key[1]
    if !haskey(event_dict, type_symbol)
        error("Type $type_symbol not found in event dictionary")
    end
    
    struct_type = event_dict[type_symbol]
    field_args = key[2:end]
    return struct_type(field_args...)
end
