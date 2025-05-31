# This uses higher-order functions, which are functions of functions,
# to find assignments in a function.


"""
This function takes a function `f` that returns `nothing` and creates
a new function that returns a list of the indices of the elements
that are assigned to in `f`.
"""
# This uses higher-order functions, which are functions of functions,
# to find assignments in a function.


"""
    track_assignments(f::Function)

This function takes a function `f` that returns `nothing` and creates
a new function that returns a list of the indices of the elements
that are assigned to in `f`.

It uses code introspection to analyze the function for array assignments
without having to execute it with a proxy object.
"""
function track_assignments(f::Function)
    # Get the lowered code representation of the function
    lowered_code = Base.code_lowered(f, (Vector{Any},))[1]
    
    # Create a new function that analyzes the assignments
    function tracked_function(x)
        indices = Set{Int}()
        
        # Create a copy so original input remains untouched
        local_x = copy(x)
        
        # Create a custom function to track assignments
        function assign_tracker(idx, val)
            push!(indices, idx)
            local_x[idx] = val
            return val
        end
        
        # Define a custom getindex method just for tracking
        function tracked_getindex(arr, idx)
            return arr[idx]
        end
        
        # Run the actual function with the real array
        f(local_x)
        
        # Extract indices from tracked operations
        return sort(collect(indices))
    end
    
    # Analyze the function body to detect array assignments
    function analyze_assignments()
        indices = Set{Int}()
        for stmt in lowered_code.code
            # Look for expressions like x[i] = v
            if isa(stmt, Expr) && stmt.head == :(=) && 
               isa(stmt.args[1], Expr) && stmt.args[1].head == :ref
                # This is an array assignment expression
                # Check if it's an integer literal index
                ref_expr = stmt.args[1]
                if length(ref_expr.args) >= 2 && isa(ref_expr.args[2], Int)
                    push!(indices, ref_expr.args[2])
                end
            end
        end
        return sort(collect(indices))
    end
    
    # If we can determine the indices statically, return them directly
    static_indices = analyze_assignments()
    if !isempty(static_indices)
        return _ -> static_indices
    end
    
    # Otherwise, fall back to the dynamic tracking approach
    return tracked_function
end


# Define a custom array type to track assignments
struct TrackedArray{T} <: AbstractArray{T,1}
    data::Array{T,1}
    indices::Set{Int}
    original::Array{T,1}
end

# Implement array interface
Base.size(a::TrackedArray) = size(a.data)
Base.getindex(a::TrackedArray, i::Int) = a.data[i]
Base.setindex!(a::TrackedArray, v, i::Int) = begin
    push!(a.indices, i)  # Record the assignment
    a.data[i] = v
    a.original[i] = v    # Update original array
    v
end


function track_with_proxy(f::Function)
    # Create a proxy array that records assignments
    proxy = let indices=indices, original=x
        proxy = similar(original)
        copy!(proxy, original)
        
        # Create the tracked array
        TrackedArray(proxy, indices, original)        
    end
    
    # Run the function with our proxy
    f(proxy)
    
    # Return the sorted list of indices that were modified
    return sort(collect(indices))
end
