# This Julia file explores how to use z3 to query arrays.
#
# Let's start with an example.
struct Agent
    health::Int
    age::Float64
end

struct ExampleWorld
    board::Array{Int,2}
    agent::Array{Agent,1}
end

# Now I want to use Z3 to assert facts about this ExampleWorld.
# 1. The extent of the board is 1:12 in i and 1:12 in j.
# 2. The agents range from 1 to 10.
# 3. The value at each board position is either 0 or the index of the agent.
# 4. Two agents are neighbors if they are adjacent on the board.
#
using Z3


"""
    adjacency_rule(adj_i, adj_j, i, j)

Creates a Z3 expression that represents adjacency conditions for coordinates.
Two cells are adjacent if they differ by 1 in exactly one dimension.

# Arguments
- `adj_i`: Z3 variable representing the i-coordinate to check for adjacency
- `adj_j`: Z3 variable representing the j-coordinate to check for adjacency
- `i`: Integer reference i-coordinate
- `j`: Integer reference j-coordinate

# Returns
- Z3 expression representing the adjacency condition
"""
function adjacency_rule(adj_i, adj_j, i, j)
    # Define each condition for adjacency
    eq_i_plus_1 = adj_i == IntVal(i + 1)  # i+1
    eq_j = adj_j == IntVal(j)          # same j
    
    eq_i_minus_1 = adj_i == IntVal(i - 1) # i-1
    # same j already defined
    
    eq_i = adj_i == IntVal(i)          # same i
    eq_j_plus_1 = adj_j == IntVal(j + 1) # j+1
    
    # same i already defined
    eq_j_minus_1 = adj_j == IntVal(j - 1) # j-1
    
    # Combine the comparisons for each direction
    down_cond = And([eq_i_plus_1, eq_j])
    up_cond = And([eq_i_minus_1, eq_j])
    right_cond = And([eq_i, eq_j_plus_1])
    left_cond = And([eq_i, eq_j_minus_1])
    
    return Or([down_cond, up_cond, right_cond, left_cond])
end

# This function takes as input the (i,j) coordinate on the board
# and uses a *Z3 rule about adjacency* to generate all coordinates
# that are adjacent and still within the extent of the board.

"""
    adjacent_coordinates(i::Int, j::Int, board_size::Tuple{Int,Int})

This function takes as input the (i,j) coordinate on the board
and uses a *Z3 rule about adjacency* to generate all coordinates
that are adjacent and still within the extent of the board.

# Arguments
- `i::Int`: The row index of the coordinate
- `j::Int`: The column index of the coordinate
- `board_size::Tuple{Int,Int}`: The size of the board as (rows, columns)

# Returns
- Vector of tuples representing valid adjacent coordinates
"""
function adjacent_coordinates(i::Int, j::Int, board_size::Tuple{Int,Int})
    # Define variables for adjacent coordinates
    adj_i = IntVar("adj_i")
    adj_j = IntVar("adj_j")
    uno = IntVal(1)
    
    # Define board size constraints
    rows, cols = board_size
    # Use Z3 comparison functions for constraints
    # Create bounds manually since operators are not overloaded
    ge_i = Z3.Expr(adj_i.ctx, Z3.Libz3.Z3_mk_ge(Z3.ref(adj_i.ctx), Z3.as_ast(adj_i), Z3.as_ast(IntVal(1))))
    le_i = Z3.Expr(adj_i.ctx, Z3.Libz3.Z3_mk_le(Z3.ref(adj_i.ctx), Z3.as_ast(adj_i), Z3.as_ast(IntVal(rows))))
    ge_j = Z3.Expr(adj_j.ctx, Z3.Libz3.Z3_mk_ge(Z3.ref(adj_j.ctx), Z3.as_ast(adj_j), Z3.as_ast(IntVal(1))))
    le_j = Z3.Expr(adj_j.ctx, Z3.Libz3.Z3_mk_le(Z3.ref(adj_j.ctx), Z3.as_ast(adj_j), Z3.as_ast(IntVal(cols))))
    
    in_bounds = And([ge_i, le_i, ge_j, le_j])
    
    # Use the helper function to create the adjacency rule
    adj_rules = adjacency_rule(adj_i, adj_j, i, j)
    
    # Combine constraints
    constraints = And([in_bounds, adj_rules])
    
    # Create a solver and add the constraints
    solver = Solver()
    add(solver, constraints)
    
    # Find all valid adjacent coordinates
    adjacent_coords = Tuple{Int,Int}[]
    
    while check(solver) == Z3.CheckResult(:sat)
        m = model(solver)
        
        # Extract and parse model string to get values
        model_str = unsafe_string(Z3.Libz3.Z3_model_to_string(Z3.ref(m.ctx), m.model))
        
        # Parse the model string to extract values
        # Format is typically: "adj_i -> X\nadj_j -> Y\n" where X, Y are integers
        # Use regex to extract
        i_match = match(r"adj_i\s+->\s+(\d+)", model_str)
        j_match = match(r"adj_j\s+->\s+(\d+)", model_str)
        
        if i_match !== nothing && j_match !== nothing
            i_val = parse(Int, i_match.captures[1])
            j_val = parse(Int, j_match.captures[1])
            
            push!(adjacent_coords, (i_val, j_val))
            
            # Add a blocking clause to find the next solution
            block = Not(And([adj_i == IntVal(i_val), adj_j == IntVal(j_val)]))
            add(solver, block)
        else
            # If we can't parse the values, break to avoid infinite loop
            @warn "Could not parse model values"
            break
        end
    end
    
    return adjacent_coords
end
