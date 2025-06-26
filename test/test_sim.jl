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


@testset "event_generator_for_agent_movement" begin
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
    
    # Test that event generators are properly configured
    gens = SeeSign.generators(SeeSign.MoveTransition)
    @test length(gens) == 2  # One for agent movement, one for board space changes
    
    # The first generator watches for agent location changes
    agent_gen = gens[1]
    @test agent_gen.matchstr == [:agent, ℤ, :loc]
    @test SeeSign.matches_place(agent_gen)
    
    # Test generating events when agent 7 moves
    generated_events = SeeSign.SimEvent[]
    agent_gen.generator(physical, 7) do event
        push!(generated_events, event)
    end
    
    # Agent 7 at position (1,3) can move in 3 directions (not up because it's at the edge)
    move_cnt = 3
    @test length(generated_events) == move_cnt
    
    # Check that all generated events are valid MoveTransitions for agent 7
    for event in generated_events
        @test isa(event, SeeSign.MoveTransition)
        @test event.who == 7
        @test event.direction in [SeeSign.Left, SeeSign.Down, SeeSign.Right]
    end
    
    # Verify all generated moves satisfy preconditions
    for event in generated_events
        @test SeeSign.precondition(event, physical)
    end
    
    # Test the second generator (board occupancy changes)
    board_gen = gens[2]
    @test board_gen.matchstr == [:board, ℤ, :occupant]
    @test SeeSign.matches_place(board_gen)
    
    # Modify the board by putting another piece in the way (at position (1,4))
    physical.board[LinearIndices(arr)[1, 4]].occupant = 13
    
    # Regenerate events for agent 7
    generated_events2 = SeeSign.SimEvent[]
    agent_gen.generator(physical, 7) do event
        push!(generated_events2, event)
    end
    
    # Now agent 7 should only be able to move in 2 directions (blocked to the right)
    valid_moves = [event for event in generated_events2 if SeeSign.precondition(event, physical)]
    @test length(valid_moves) == move_cnt - 1
end


@testset "Simulation Tests" begin
    ci = continuous_integration()
    log_level = ci ? Logging.Error : Logging.Debug
    run_cnt = ci ? 10 : 1000
    with_logger(ConsoleLogger(stderr, log_level)) do
        SeeSign.run(run_cnt)
    end
end
