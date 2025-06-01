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
    modified::Vector{CartesianIndex{N}}
end


function StepArray{T,N}(_::UndefInitializer, dims...) where {T,N}
    return StepArray{T,N}(
        [Array{T,N}(undef, dims...), Array{T,N}(undef, dims...)],
        ones(Int, dims...),
        CartesianIndex{N}[]
        )
end


# When a client sets a value, move the index to the other array and add 3.
function Base.setindex!(arr::StepArray, val, i...)
    idx = CartesianIndex(i)
    if idx ∉ arr.modified
        # First modification - store the original value
        push!(arr.modified, idx)
        # Keep the previous value in the other array for history
        curr_idx = arr.which[i...]
        other_idx = 3 - curr_idx
        # Do not modify the previous array if this is the first modification
        arr.which[i...] = other_idx
        arr.v[other_idx][i...] = val
    else
        # Already modified - just update the current array
        arr.v[arr.which[i...]][i...] = val
    end
    return val
end


Base.getindex(arr::StepArray, i...) = arr.v[arr.which[i...]][i...]


# This function erases the marker that indicates recent changes.
accept(arr::StepArray) = (empty!(arr.modified); arr)

# Required AbstractArray interface methods
Base.size(arr::StepArray) = size(arr.which)

# Optional but recommended AbstractArray interface methods
Base.length(arr::StepArray) = length(arr.which)
Base.IndexStyle(::Type{<:StepArray}) = IndexCartesian()

Base.similar(arr::StepArray) = StepArray(similar(arr.v[:,:,1]))
Base.similar(arr::StepArray, ::Type{S}) where S = StepArray(similar(arr.v[:,:,1], S))
Base.similar(arr::StepArray, ::Type{S}, dims::Dims) where S = StepArray(Array{S}(undef, dims))

"""
    changed(arr::StepArray)

"""
changed(arr::StepArray) = arr.modified


"""
    previous_value(arr::StepArray, i...)

Get the previous value at index i before it was changed.
Returns the current value if the element hasn't been changed.
"""
function previous_value(arr::StepArray, i...)
    idx = CartesianIndex(i...)
    # If this index has been modified, return original value
    if idx in arr.modified
        # Current version is in arr.which[i...], previous is in the other slot
        other_idx = 3 - arr.which[i...]
        return arr.v[other_idx][i...]
    else
        # Not modified, so both versions are the same
        return arr.v[arr.which[i...]][i...]
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
