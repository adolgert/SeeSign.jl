using Test
using SeeSign
using Logging

@testset "Board from ascii image" begin
    ascii_image = """
        0 0 7 0 0 0 0 3 0 0
        0 0 0 0 0 0 0 0 0 6
        0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 9 2
        0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 5 0 0 0 1
        0 0 0 0 0 0 0 4 0 0
        0 0 0 0 0 8 0 0 0 0
        """
    arr = ascii_to_array(ascii_image)
    @test size(arr) == (9, 10)
    @test arr[1, 3] == 7
    @test arr[9, 1] == 0
    @test arr[9, 6] == 8
end

@testset "Board allowed moves correct" begin
    ascii_image = """
        0 0 7 0 0 0 0 3 0 0
        0 0 0 0 0 0 0 0 0 6
        0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 0 0 9 2
        0 0 0 0 0 0 0 0 0 0
        0 0 0 0 0 5 0 0 0 1
        0 0 0 0 0 0 0 4 0 0
        0 0 0 0 0 8 0 0 0 0
        0 0 0 0 0 0 0 0 0 0
        """
    arr = ascii_to_array(ascii_image)
    physical = SeeSign.BoardState(arr)
    moves = SeeSign.allowed_moves(physical)
end


@testset "Simulation Tests" begin
    with_logger(ConsoleLogger(stderr, Logging.Debug)) do
        SeeSign.run(1000)
    end
end
