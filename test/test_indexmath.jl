using Test
using Z3
include("../src/indexmath.jl")  # For standalone testing

@testset "Index Math Tests" begin
    @testset "adjacent_coordinates" begin
        # Test case 1: Central position on a 5x5 board
        center_coords = adjacent_coordinates(3, 3, (5, 5))
        @test length(center_coords) == 4
        @test (2, 3) in center_coords  # Up
        @test (4, 3) in center_coords  # Down
        @test (3, 2) in center_coords  # Left
        @test (3, 4) in center_coords  # Right
        
        # Test case 2: Corner position (top-left) on a 5x5 board
        corner_coords = adjacent_coordinates(1, 1, (5, 5))
        @test length(corner_coords) == 2
        @test (2, 1) in corner_coords  # Down
        @test (1, 2) in corner_coords  # Right
        
        # Test case 3: Edge position on a 5x5 board
        edge_coords = adjacent_coordinates(1, 3, (5, 5))
        @test length(edge_coords) == 3
        @test (1, 2) in edge_coords  # Left
        @test (1, 4) in edge_coords  # Right
        @test (2, 3) in edge_coords  # Down
        
        # Test case 4: Another edge position on a 5x5 board
        edge_coords2 = adjacent_coordinates(3, 5, (5, 5))
        @test length(edge_coords2) == 3
        @test (2, 5) in edge_coords2  # Up
        @test (4, 5) in edge_coords2  # Down
        @test (3, 4) in edge_coords2  # Left
        
        # Test case 5: Bottom-right corner on a 5x5 board
        br_corner_coords = adjacent_coordinates(5, 5, (5, 5))
        @test length(br_corner_coords) == 2
        @test (4, 5) in br_corner_coords  # Up
        @test (5, 4) in br_corner_coords  # Left
        
        # Test case 6: Single-cell board (1x1)
        tiny_board_coords = adjacent_coordinates(1, 1, (1, 1))
        @test length(tiny_board_coords) == 0
        
        # Test case 7: Rectangular board (non-square)
        rect_coords = adjacent_coordinates(2, 2, (3, 5))
        @test length(rect_coords) == 4
        @test (1, 2) in rect_coords  # Up
        @test (3, 2) in rect_coords  # Down
        @test (2, 1) in rect_coords  # Left
        @test (2, 3) in rect_coords  # Right
    end
end

# If this file is being run directly, execute the tests
if abspath(PROGRAM_FILE) == @__FILE__
    @testset "Run test_indexmath.jl directly" begin
        include("test_indexmath.jl")
    end
end