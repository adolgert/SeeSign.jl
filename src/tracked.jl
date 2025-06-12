"""
This module provides tools for tracking access to and changes of data structures.
It includes a macro for creating structs that track access and a vector type that
tracks changes to its elements.

There are two approaches to tracking changes to elements of a vector.

 1. Each element of the vector contains a pointer to the owning vector
    and notifies it when there was a change.

 2. The vector trackes which elements were read and, when asked what
    changed, checkes each element that was read to see if it was also
    modified.
    
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
            _gotten::Set{Symbol}
            _changed::Set{Symbol}
            
            function $(esc(typename))($(map(esc, fieldnames)...))
                return new($(map(esc, fieldnames)...), nothing, nothing, Set{Symbol}(), Set{Symbol}())
            end
        end
    end
    
    getprop_def = quote
        function Base.getproperty(obj::$(esc(typename)), field::Symbol)
            if field in (:_container, :_index, :_gotten, :_changed)
                return getfield(obj, field)
            else
                push!(getfield(obj, :_gotten), field)
                return getfield(obj, field)
            end
        end
    end
    
    setprop_def = quote
        function Base.setproperty!(obj::$(esc(typename)), field::Symbol, value)
            if field in (:_container, :_index, :_gotten, :_changed)
                setfield!(obj, field, value)
            else
                push!(getfield(obj, :_changed), field)
                setfield!(obj, field, value)
            end
        end
    end
    
    propnames_def = quote
        function Base.propertynames(obj::$(esc(typename)), private::Bool=false)
            if private
                return fieldnames($(esc(typename)))
            else
                return $(fieldnames)
            end
        end
    end
    
    # Define equality comparison properly  
    field_comparisons = [:(getproperty(a, $(QuoteNode(fname))) == getproperty(b, $(QuoteNode(fname)))) for fname in fieldnames]
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
    _accessed::Set{Int}
    
    function TrackedVector{T}(::UndefInitializer, n::Integer) where T
        return new{T}(Vector{T}(undef, n), Set{Int}())
    end
    
    function TrackedVector{T}(v::Vector{T}) where T
        return new{T}(v, Set{Int}())
    end
end

# Implement AbstractArray interface
Base.size(v::TrackedVector) = size(v.data)
Base.getindex(v::TrackedVector{T}, i::Integer) where T = begin
    push!(v._accessed, i)
    element = v.data[i]
    if hasfield(typeof(element), :_container)
        setfield!(element, :_container, v)
        setfield!(element, :_index, i)
    end
    element
end

Base.setindex!(v::TrackedVector{T}, x, i::Integer) where T = begin
    v.data[i] = x
    if hasfield(typeof(x), :_container)
        setfield!(x, :_container, v)
        setfield!(x, :_index, i)
    end
    x
end

# Track property access on elements
function Base.getproperty(v::TrackedVector, field::Symbol)
    if field in (:data, :_accessed)
        return getfield(v, field)
    else
        error("Field $field not found in TrackedVector")
    end
end

function Base.setproperty!(v::TrackedVector, field::Symbol, value)
    if field in (:data, :_accessed)
        setfield!(v, field, value)
    else
        error("Cannot set field $field in TrackedVector")
    end
end

"""
    gotten(obj)

Returns the set of fields that have been accessed.
"""
function gotten(obj::TrackedVector)
    result = Set{Tuple}()
    for i in obj._accessed
        element = obj.data[i]
        if hasfield(typeof(element), :_gotten) && getfield(element, :_gotten) !== nothing
            for field in getfield(element, :_gotten)
                push!(result, (i, field))
            end
        end
    end
    result
end

"""
    changed(obj)

Returns the set of fields that have been modified.
"""
function changed(obj::TrackedVector)
    result = Set{Tuple}()
    for i in obj._accessed
        element = obj.data[i]
        if hasfield(typeof(element), :_changed) && getfield(element, :_changed) !== nothing
            for field in getfield(element, :_changed)
                push!(result, (i, field))
            end
        end
    end
    result
end

"""
    reset_tracking!(obj)

Reset all tracking information.
"""
function reset_tracking!(obj::TrackedVector)
    empty!(obj._accessed)
    for element in obj.data
        if hasfield(typeof(element), :_gotten) && getfield(element, :_gotten) !== nothing
            empty!(getfield(element, :_gotten))
        end
        if hasfield(typeof(element), :_changed) && getfield(element, :_changed) !== nothing
            empty!(getfield(element, :_changed))
        end
    end
    obj
end

"""
    reset_gotten!(obj)

Reset the tracking of accessed fields.
"""
function reset_gotten!(obj::TrackedVector)
    for element in obj.data
        if hasfield(typeof(element), :_gotten) && getfield(element, :_gotten) !== nothing
            empty!(getfield(element, :_gotten))
        end
    end
    obj
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