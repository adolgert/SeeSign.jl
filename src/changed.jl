using Base: Base

"""
    StepArray(arr)

You have an array and want to compare the current value with the previous value.
This creates a double of the array so that memory use is optimized.
"""
struct StepArray{T,N} <: AbstractArray{T,N}
    v::Array{Array{T,N},1}
    # The extra array is a set of integers to point to which of the two
    # arrays is the current one.
    which::Array{Int,N}
end


function StepArray{T,N}(_::UndefInitializer, dims...) where {T,N}
    return StepArray{T,N}([Array{T,N}(undef, dims...), Array{T,N}(undef, dims...)], ones(Int, dims...))
end


# When a client sets a value, move the index to the other array and add 3.
function Base.setindex!(arr::StepArray, val, i...)
    j = arr.which[i...]
    j <= 2 && (j = 3 - j)
    arr.which[i...] = j + 3
    arr.v[j % 3][i...] = val
    return val
end


Base.getindex(arr::StepArray, i...) = arr.v[arr.which[i...] % 3][i...]


# This function erases the marker that indicates recent changes.
accept(arr::StepArray) = (arr.which .%= 3; arr)

# Required AbstractArray interface methods
Base.size(arr::StepArray) = size(arr.which)

# Optional but recommended AbstractArray interface methods
Base.length(arr::StepArray) = length(arr.which)
Base.IndexStyle(::Type{<:StepArray}) = IndexCartesian()

# Additional useful methods
Base.similar(arr::StepArray) = StepArray(similar(arr.v[:,:,1]))
Base.similar(arr::StepArray, ::Type{S}) where S = StepArray(similar(arr.v[:,:,1], S))
Base.similar(arr::StepArray, ::Type{S}, dims::Dims) where S = StepArray(Array{S}(undef, dims))

# Methods to check which values have changed
"""
    changed(arr::StepArray)

Returns a BitArray indicating which elements have been changed since the last call to accept().
"""
function changed(arr::StepArray)
    return arr.which .> 3
end


"""
    previous_value(arr::StepArray, i...)

Get the previous value at index i before it was changed.
Returns the current value if the element hasn't been changed.
"""
function previous_value(arr::StepArray, i...)
    j = arr.which[i...]
    if j <= 2
        return arr.v[j][i...]
    else
        return arr.v[3 - (j % 3)][i...]
    end
end


"""
    iterate(arr::StepArray, [state])

Enables iteration over a StepArray, allowing it to be used in for loops
and with other iteration functions like map, filter, etc.
"""
function Base.iterate(arr::StepArray, state=1)
    if state > length(arr)
        return nothing
    else
        # Convert linear index to cartesian for proper indexing
        idx = CartesianIndices(arr)[state]
        return (arr[idx], state + 1)
    end
end
