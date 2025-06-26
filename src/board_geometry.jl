export DirectionDelta, DirectionOpposite

# They can move in any of four directions.
@enum Direction NoDirection Up Left Down Right
const DirectionDelta = Dict(
    Up => CartesianIndex(-1, 0),
    Left => CartesianIndex(0, -1),
    Down => CartesianIndex(1, 0),
    Right => CartesianIndex(0, 1),
    );
const DirectionOpposite = Dict(
    Up => Down, Down => Up, Left => Right, Right => Left
)

"""
BoardGeometry encapsulates the 2D structure of a board while exposing only
single-integer linear indices in its API. All 2D logic is handled internally.
"""
struct BoardGeometry
    cartesian_indices::CartesianIndices{2, Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}}
    linear_indices::LinearIndices{2, Tuple{Base.OneTo{Int64}, Base.OneTo{Int64}}}
    
    function BoardGeometry(rows::Int, cols::Int)
        ci = CartesianIndices((rows, cols))
        li = LinearIndices((rows, cols))
        new(ci, li)
    end
    
    function BoardGeometry(dims::Tuple{Int, Int})
        BoardGeometry(dims[1], dims[2])
    end
    
    function BoardGeometry(ci::CartesianIndices{2})
        li = LinearIndices(ci)
        new(ci, li)
    end
end


"""
Get the dimensions of the board as (rows, cols).
"""
dimensions(geom::BoardGeometry) = size(geom.cartesian_indices)


"""
Get the total number of board positions.
"""
Base.length(geom::BoardGeometry) = length(geom.linear_indices)


"""
Check if a linear index is valid for this board.
"""
Base.checkbounds(::Type{Bool}, geom::BoardGeometry, idx_lin::Int) = 
    checkbounds(Bool, geom.linear_indices, idx_lin)


"""
Get all linear indices of neighbors for a given position.
Returns an iterator over valid neighbor positions.
"""
function neighbors(geom::BoardGeometry, idx_lin::Int)
    ci = geom.cartesian_indices[idx_lin]
    return (geom.linear_indices[ci + DirectionDelta[direction]] 
            for direction in keys(DirectionDelta) 
            if checkbounds(Bool, geom.cartesian_indices, ci + DirectionDelta[direction]))
end


"""
Get the linear index of a neighbor in a specific direction.
Returns nothing if the neighbor would be out of bounds.
"""
function neighbor_in_direction(geom::BoardGeometry, idx_lin::Int, direction::Direction)
    ci = geom.cartesian_indices[idx_lin]
    neighbor_ci = ci + DirectionDelta[direction]
    if checkbounds(Bool, geom.cartesian_indices, neighbor_ci)
        return geom.linear_indices[neighbor_ci]
    else
        return nothing
    end
end


"""
Get all valid directions from a given position.
Returns an iterator over directions that lead to valid board positions.
"""
function valid_directions(geom::BoardGeometry, idx_lin::Int)
    ci = geom.cartesian_indices[idx_lin]
    return (direction 
            for direction in keys(DirectionDelta) 
            if checkbounds(Bool, geom.cartesian_indices, ci + DirectionDelta[direction]))
end


"""
Check if two positions are neighbors (adjacent horizontally or vertically).
"""
function are_neighbors(geom::BoardGeometry, idx_lin_a::Int, idx_lin_b::Int)
    ci_a = geom.cartesian_indices[idx_lin_a]
    ci_b = geom.cartesian_indices[idx_lin_b]
    diff = ci_b - ci_a
    return sum(x^2 for x in diff.I) == 1
end


"""
Get the direction from one position to its neighbor.
Returns nothing if positions are not neighbors.
"""
function direction_between(geom::BoardGeometry, from_idx_lin::Int, to_idx_lin::Int)
    if !are_neighbors(geom, from_idx_lin, to_idx_lin)
        return nothing
    end
    
    ci_from = geom.cartesian_indices[from_idx_lin]
    ci_to = geom.cartesian_indices[to_idx_lin]
    diff = ci_to - ci_from
    
    for (direction, delta) in DirectionDelta
        if delta == diff
            return direction
        end
    end
    
    return nothing
end


"""
Get a random valid position (linear index) on the board.
"""
function random_position(geom::BoardGeometry, rng)
    return rand(rng, 1:length(geom))
end


"""
Iterate over all linear indices in row-major order.
"""
Base.eachindex(geom::BoardGeometry) = eachindex(geom.linear_indices)


"""
For iteration support.
"""
Base.iterate(geom::BoardGeometry) = iterate(geom.linear_indices)
Base.iterate(geom::BoardGeometry, state) = iterate(geom.linear_indices, state)
