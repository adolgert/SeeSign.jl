using Test
using SeeSign


@testset "Find assignments in a function" begin
    @test_skip begin
        function write_value(board::AbstractVector, i::Int)
            board[i] = 1
            board[2i] = 1
        end

        state = zeros(10)
        result = SeeSign.high_order(write_value)(state, 6)
        @test Set(result) == Set([6, 12])
    end
end
