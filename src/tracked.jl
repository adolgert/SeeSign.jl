"""
This module provides tools for tracking access to and changes of data structures.
It includes a macro for creating structs that track access and a vector type that
tracks changes to its elements.
"""

using MacroTools

export @tracked_struct, TrackedVector
export gotten, changed, reset_tracking!, reset_gotten!

"""
    @tracked_struct Name begin
        field1::Type1
        field2::Type2
        # ...
    end

Creates a struct that tracks when its fields are accessed or modified.
"""
macro tracked_struct(typename, body)
    @assert body.head == :block "Expected a block for struct body"
    
    fields = []
    for expr in body.args
        if expr isa LineNumberNode
            continue
        elseif expr isa Expr && expr.head == :(::)
            push!(fields, expr)
        end
    end
    
    fieldnames = [field.args[1] for field in fields]
    fieldtypes = [field.args[2] for field in fields]
    
    # Create the internal struct
    struct_def = quote
        mutable struct $(esc(typename))
            $(fields...)
            _container::Union{Nothing, Any}
            _index::Union{Nothing, Int}
            
            function $(esc(typename))($(map(esc, fieldnames)...))
                return new($(map(esc, fieldnames)...), nothing, nothing)
            end
        end
    end
    
    getprop_def = quote
        function Base.getproperty(obj::$(esc(typename)), field::Symbol)
            if field == :_container || field == :_index
                return getfield(obj, field)
            else
                # Notify container about access if available
                container = getfield(obj, :_container)
                index = getfield(obj, :_index)
                if container !== nothing && index !== nothing
                    push!(getfield(container, :_gotten), (index, field))
                end
                return getfield(obj, field)
            end
        end
    end
    
    setprop_def = quote
        function Base.setproperty!(obj::$(esc(typename)), field::Symbol, value)
            if field == :_container || field == :_index
                setfield!(obj, field, value)
            else
                # Notify container about change if available
                container = getfield(obj, :_container)
                index = getfield(obj, :_index)
                if container !== nothing && index !== nothing
                    push!(getfield(container, :_changed), (index, field))
                end
                setfield!(obj, field, value)
            end
        end
    end
    
    propnames_def = quote
        function Base.propertynames(obj::$(esc(typename)), private::Bool=false)
            if private
                return fieldnames($(esc(typename)))
            else
                return $(map(QuoteNode, fieldnames))
            end
        end
    end
    
    # Define equality comparison properly
    field_comparisons = [:(getfield(a, $(QuoteNode(fname))) == getfield(b, $(QuoteNode(fname)))) for fname in fieldnames]
    eq_expr = Expr(:&&, field_comparisons...)
    
    eq_def = quote
        function Base.:(==)(a::$(esc(typename)), b::$(esc(typename)))
            $eq_expr
        end
    end
    
    return quote
        $(struct_def)
        $(getprop_def)
        $(setprop_def)
        $(propnames_def)
        $(eq_def)
    end
end

"""
    TrackedVector{T}

A vector that tracks access and changes to its elements.
"""
struct TrackedVector{T} <: AbstractVector{T}
    data::Vector{T}
    _gotten::Set{Tuple}
    _changed::Set{Tuple}
    
    function TrackedVector{T}(::UndefInitializer, n::Integer) where T
        return new{T}(Vector{T}(undef, n), Set{Tuple}(), Set{Tuple}())
    end
    
    function TrackedVector{T}(v::Vector{T}) where T
        return new{T}(v, Set{Tuple}(), Set{Tuple}())
    end
end

# Implement AbstractArray interface
Base.size(v::TrackedVector) = size(v.data)
Base.getindex(v::TrackedVector, i::Integer) = begin
    push!(v._gotten, (i,))
    v.data[i]
end

Base.setindex!(v::TrackedVector, x, i::Integer) = begin
    push!(v._changed, (i,))
    v.data[i] = x
    
    # Set container reference in the element if applicable
    if hasfield(typeof(x), :_container)
        setfield!(x, :_container, v)
        setfield!(x, :_index, i)
    end
    x
end

# Track property access on elements
function Base.getproperty(v::TrackedVector, field::Symbol)
    if field in (:data, :_gotten, :_changed)
        return getfield(v, field)
    else
        error("Field $field not found in TrackedVector")
    end
end

function Base.setproperty!(v::TrackedVector, field::Symbol, value)
    if field in (:data, :_gotten, :_changed)
        setfield!(v, field, value)
    else
        error("Cannot set field $field in TrackedVector")
    end
end

# Track property access on elements
function Base.getproperty(obj::TrackedVector, i::Integer, field::Symbol)
    push!(obj._gotten, (i, field))
    getproperty(obj.data[i], field)
end

function Base.setproperty!(obj::TrackedVector, i::Integer, field::Symbol, value)
    push!(obj._changed, (i, field))
    setproperty!(obj.data[i], field, value)
end

"""
    gotten(obj)

Returns the set of fields that have been accessed.
"""
function gotten(obj::TrackedVector)
    return obj._gotten
end

"""
    changed(obj)

Returns the set of fields that have been modified.
"""
function changed(obj::TrackedVector)
    return obj._changed
end

"""
    reset_tracking!(obj)

Reset all tracking information.
"""
function reset_tracking!(obj::TrackedVector)
    empty!(obj._gotten)
    empty!(obj._changed)
    return obj
end

"""
    reset_gotten!(obj)

Reset the tracking of accessed fields.
"""
function reset_gotten!(obj::TrackedVector)
    empty!(obj._gotten)
    return obj
end

# Helper function to check if property exists
function hasproperty(obj, prop::Symbol)
    return prop in fieldnames(typeof(obj))
end

"""
    change(obj)

Returns the set of fields that have been modified. Alias for changed().
"""
function change(obj)
    return changed(obj)
end