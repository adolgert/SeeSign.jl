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
    allowed = SeeSign.allowed_moves(physical)
    Left, Right, Up, Down = (SeeSign.Left, SeeSign.Right, SeeSign.Up, SeeSign.Down)
    for move in [
        (7, Left), (7, Down), (7, Right), (3, Left), (3, Down), (3, Right),
        (6, Up), (6, Left), (6, Down)
    ]
        @test (:MoveTransition, move...) in allowed
    end
    for move in [
        (7, Up), (3, Up), (6, Right), (9, Right), (2, Right), (2, Left),
    ]
        @test (:MoveTransition, move...) ∉ allowed
    end
end


@testset "Simulation Tests" begin
    with_logger(ConsoleLogger(stderr, Logging.Debug)) do
        SeeSign.run(1000)
    end
end
