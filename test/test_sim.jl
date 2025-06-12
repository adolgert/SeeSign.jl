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


@testset "tomove_generate_event" begin
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
    place_idx = LinearIndices(arr)[1, 3]
    place = (:board, place_idx, :occupant)
    result = SeeSign.tomove_generate_event(physical, place, Set{SeeSign.ClockKey}())

    move_cnt = 3
    clock_key = [SeeSign.clock_key(event) for event in result.create]
    @test length(Set(clock_key)) == move_cnt
    @test length(result.create) == move_cnt
    for event in result.create
        @test isa(event, SeeSign.MoveTransition)
        @test event.who == 7
    end
    @test length(result.depends) == move_cnt
    for dep in result.depends
        @test (:board, place_idx, :occupant) ∈ dep
        @test length(dep) == 2
    end
    @test length(result.enabled) == move_cnt
    for enabling in result.enabled
        @test enabling(physical)
    end

    ## Modify the board by putting another piece in the way.
    physical.board[LinearIndices(arr)[1, 4]].occupant = 13
    # Then one of the enabling functions should be false.
    @test sum([enabling(physical) for enabling in result.enabled]) == move_cnt - 1
end


@testset "Simulation Tests" begin
    with_logger(ConsoleLogger(stderr, Logging.Debug)) do
        SeeSign.run(10)
    end
end
