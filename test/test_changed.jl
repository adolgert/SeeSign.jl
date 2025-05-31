using Test
using SeeSign

@testset "StepArray Tests" begin
    @testset "Basic StepArray Creation and Access" begin
        # Create a simple 1D array using UndefInitializer and copy!
        original = [1, 2, 3, 4, 5]
        step_arr = StepArray{Int,1}(undef, 5)
        copy!(step_arr, original)
        accept(step_arr)
        
        # Test that we can read the original values
        @test step_arr[1] == 1
        @test step_arr[3] == 3
        @test step_arr[5] == 5
        
        # Test size and length
        @test size(step_arr) == size(original)
        @test length(step_arr) == length(original)
    end
    
    @testset "StepArray Modification Tracking" begin
        # Create test array using UndefInitializer and copy!
        original = [10, 20, 30, 40, 50]
        step_arr = StepArray{Int,1}(undef, 5)
        copy!(step_arr, original)
        accept(step_arr)
        
        # Initially, nothing should be changed
        @test !any(changed(step_arr))
        
        # Modify some elements
        step_arr[1] = 100  # Change first element
        step_arr[3] = 300  # Change third element
        # Leave elements 2, 4, 5 unchanged
        
        # Check that modified elements are detected
        changes = changed(step_arr)
        @test changes[1] == true   # Element 1 was changed
        @test changes[2] == false  # Element 2 was not changed
        @test changes[3] == true   # Element 3 was changed
        @test changes[4] == false  # Element 4 was not changed
        @test changes[5] == false  # Element 5 was not changed
        
        # Check that new values are correct
        @test step_arr[1] == 100
        @test step_arr[2] == 20   # Unchanged
        @test step_arr[3] == 300
        @test step_arr[4] == 40   # Unchanged
        @test step_arr[5] == 50   # Unchanged
        
        # Check previous values
        @test previous_value(step_arr, 1) == 10  # Original value
        @test previous_value(step_arr, 3) == 30  # Original value
        @test previous_value(step_arr, 2) == 20  # Should be same as current (unchanged)
    end
    
    @testset "Accept Function" begin
        # Create test array using UndefInitializer and copy!
        original = [1, 2, 3]
        step_arr = StepArray{Int,1}(undef, 3)
        copy!(step_arr, original)
        accept(step_arr)
        
        # Modify an element
        step_arr[2] = 99
        @test changed(step_arr)[2] == true
        
        # Accept changes
        accept(step_arr)
        
        # After accept, nothing should be marked as changed
        @test !any(changed(step_arr))
        
        # But the new value should still be there
        @test step_arr[2] == 99
    end
    
    @testset "2D Array Support" begin
        # Create a 2D array using UndefInitializer and copy!
        original = [1 2 3; 4 5 6]
        step_arr = StepArray{Int,2}(undef, 2, 3)
        copy!(step_arr, original)
        accept(step_arr)
        
        # Test basic access
        @test step_arr[1, 1] == 1
        @test step_arr[2, 3] == 6
        
        # Test modification
        step_arr[1, 2] = 99
        step_arr[2, 1] = 88
        
        # Check changes
        changes = changed(step_arr)
        @test changes[1, 1] == false
        @test changes[1, 2] == true   # Modified
        @test changes[1, 3] == false
        @test changes[2, 1] == true   # Modified
        @test changes[2, 2] == false
        @test changes[2, 3] == false
        
        # Check values
        @test step_arr[1, 2] == 99
        @test step_arr[2, 1] == 88
        @test step_arr[1, 1] == 1  # Unchanged
    end
    
    @testset "Iteration Support" begin
        original = [10, 20, 30]
        step_arr = StepArray{Int,1}(undef, 3)
        copy!(step_arr, original)
        accept(step_arr)
        
        # Test that we can iterate
        collected = collect(step_arr)
        @test collected == [10, 20, 30]
        
        # Test iteration after modification
        step_arr[2] = 999
        collected_after = collect(step_arr)
        @test collected_after == [10, 999, 30]
        
        # Test with for loop
        values = []
        for val in step_arr
            push!(values, val)
        end
        @test values == [10, 999, 30]
    end
    
    @testset "Multiple Modifications" begin
        original = [1, 2, 3, 4]
        step_arr = StepArray{Int,1}(undef, 4)
        copy!(step_arr, original)
        accept(step_arr)
        
        # Modify the same element multiple times
        step_arr[1] = 100
        @test step_arr[1] == 100
        @test changed(step_arr)[1] == true
        
        step_arr[1] = 200
        @test step_arr[1] == 200
        @test changed(step_arr)[1] == true  # Still marked as changed
        
        # The previous value should still be the original
        @test previous_value(step_arr, 1) == 1
    end
end