const ℤ = :__SINGLE_INTEGER_MATCH__
const ℤ⁺ = :__MULTIPLE_INTEGER_MATCH__

function validate_pattern(pattern::Vector)
    for i in 1:(length(pattern)-1)
        if (pattern[i] === ℤ || pattern[i] === ℤ⁺) && 
           (pattern[i+1] === ℤ || pattern[i+1] === ℤ⁺) &&
           pattern[i] !== pattern[i+1]
            throw(ArgumentError("Cannot mix consecutive ℤ and ℤ⁺ patterns"))
        end
    end
end

function accessmatch(pattern::Vector, input::Tuple)
    validate_pattern(pattern)
    captures = Tuple{Int,Vararg{Int}}[]
    input_idx = 1
    
    for elem in pattern
        if input_idx > length(input)
            return nothing
        end
        
        if elem === ℤ
            # Consume exactly one integer
            if input_idx > length(input) || !isa(input[input_idx], Integer)
                return nothing
            end
            push!(captures, (input[input_idx],))
            input_idx += 1
        elseif elem === ℤ⁺
            # Consume one or more consecutive integers
            integers = Int[]
            while input_idx ≤ length(input) && isa(input[input_idx], Integer)
                push!(integers, input[input_idx])
                input_idx += 1
            end
            isempty(integers) && return nothing
            push!(captures, Tuple(integers))
        elseif isa(elem, Symbol)
            input[input_idx] === elem || return nothing
            input_idx += 1
        else
            throw(ArgumentError("Pattern must contain only symbols, ℤ, and ℤ⁺ but found $elem"))
        end
    end
    
    return input_idx > length(input) ? Tuple(captures) : nothing
end