using ReTest
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
    @test place_idx == 21
    place = (:agent, 7, :loc)
    gens = generators(MoveTransition)
    result = SeeSign.transition_generate_event(gens[1], physical, place, Set{SeeSign.ClockKey}())
    @test !isnothing(result)

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
        @test (:board, place_idx, :occupant) ∉ dep
        @test place ∈ dep
        @test length(dep) == 2
        @debug "dep $dep"
        remaining = pop!(setdiff(dep, [place]))
        @debug "remaining $remaining"
        @test remaining[1] == :board
        @test remaining[3] == :occupant
    end
    @test length(result.create) == move_cnt
    for enable_idx in 1:move_cnt
        @test SeeSign.precondition(result.create[enable_idx], physical)
    end

    ## Modify the board by putting another piece in the way.
    physical.board[LinearIndices(arr)[1, 4]].occupant = 13
    # Then one of the enabling functions should be false.
    @test sum([SeeSign.precondition(enevt,physical) for enevt in result.create]) == move_cnt - 1
end


@testset "Simulation Tests" begin
    ci = continuous_integration()
    log_level = ci ? Logging.Error : Logging.Debug
    run_cnt = ci ? 10 : 1000
    with_logger(ConsoleLogger(stderr, log_level)) do
        SeeSign.run(run_cnt)
    end
end
