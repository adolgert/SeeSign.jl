using Logging

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
@generated function clock_key(transition::T) where T <: SimEvent
    type_symbol = QuoteNode(nameof(T))
    field_exprs = [:(transition.$field) for field in fieldnames(T)]
    return :($type_symbol, $(field_exprs...))
end

"""
    key_clock(key::Tuple)::SimEvent

Takes a tuple of the form (:symbol, arg, arg) and returns an instantiation
of the struct named by :symbol.
"""
@generated function key_clock(key::Tuple)
    type_symbol = key.parameters[1]
    if isa(type_symbol, Symbol)
        struct_type = eval(type_symbol)
        field_count = fieldcount(struct_type)
        field_exprs = [:(key[$(i+1)]) for i in 1:field_count]
        return :($struct_type($(field_exprs...)))
    else
        return :(error("First element of tuple must be a Symbol"))
    end
end
