using ReTest
using SeeSign


@testset "Base smoke test for regex tuples" begin
    # This is a kind of regular expression. It matches tuples that contain
    # only symbols and integers. We can't use a normal string-based regular expression
    # but we can make a list of elements in the regular expression. There are three kinds
    # of search terms: exact match of a symbol, ℤ which matches exactly one integer,
    # or ℤ⁺ which matches one or more integers in the tuple.
    test_cases = [
        ([:board, ℤ, :location], (:board, 3, :location), ((3,),)),
        ([:boo, ℤ, :habit], (:boo, 5, :habit), ((5,),)),
        ([:boo, ℤ⁺, :habit], (:boo, 5, 7, :habit), ((5, 7),)),
        ([:board, ℤ, :location], (:board, 3, :folly), nothing),
        ([:board, ℤ, :location], (:peanuts, 3, :location), nothing),
        ([:agent, ℤ⁺], (:agent, 3, 4, 7), ((3, 4, 7),)),
    ]
    for (pattern, input, oracle) in test_cases
        match_result = accessmatch(pattern, input)
        @test match_result == oracle
    end
end

@testset "Edge cases and comprehensive tests" begin
    # Empty patterns and inputs
    @test accessmatch([], ()) == ()
    @test accessmatch([], (:a,)) === nothing
    
    # Just literals
    @test accessmatch([:a, :b], (:a, :b)) == ()
    @test accessmatch([:a, :b], (:a, :c)) === nothing
    
    # Just integers - single vs multiple
    @test accessmatch([ℤ], (42,)) == ((42,),)
    @test accessmatch([ℤ], (1, 2)) === nothing  # ℤ matches exactly one
    @test accessmatch([ℤ⁺], (1, 2, 3)) == ((1, 2, 3),)
    @test accessmatch([ℤ⁺], (:a,)) === nothing
    
    # Multiple captures now work with both ℤ and ℤ⁺
    
    # Integer at start
    @test accessmatch([ℤ⁺, :end], (1, 2, :end)) == ((1, 2),)
    @test accessmatch([ℤ, :end], (1, :end)) == ((1,),)
    
    # Integer at end  
    @test accessmatch([:start, ℤ⁺], (:start, 1, 2)) == ((1, 2),)
    @test accessmatch([:start, ℤ], (:start, 1)) == ((1,),)
    
    # Multiple integer captures
    @test accessmatch([:start, ℤ, :two, ℤ], (:start, 1, :two, 7)) == ((1,), (7,))
    @test accessmatch([:start, ℤ⁺, :two, ℤ⁺], (:start, 1, 2, :two, 7, 8)) == ((1, 2), (7, 8))
    
    # Consecutive ℤ patterns (same type only)
    @test accessmatch([ℤ, ℤ], (1, 2)) == ((1,), (2,))
    @test accessmatch([ℤ, ℤ, ℤ], (1, 2, 3)) == ((1,), (2,), (3,))
    @test accessmatch([ℤ, ℤ], (1, 2, 3)) === nothing  # Too many integers for two single ℤ
    
    # Mixed consecutive integer patterns should throw errors
    @test_throws ArgumentError accessmatch([ℤ⁺, ℤ], (1, 2, 3))
    @test_throws ArgumentError accessmatch([ℤ, ℤ⁺], (1, 2, 3))

    # Mixed types that should fail
    @test accessmatch([:a, ℤ, :b], (:a, "string", :b)) === nothing
    
    # Complex pattern  
    @test accessmatch([:prefix, ℤ⁺, :suffix], 
               (:prefix, 1, 2, 3, :suffix)) == ((1, 2, 3),)
    @test accessmatch([:prefix, ℤ, :suffix], 
               (:prefix, 1, :suffix)) == ((1,),)
end

