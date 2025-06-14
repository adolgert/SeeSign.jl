using Test
using SeeSign


@testset "Basic Dependency Network" begin
    EventKey = Tuple{Symbol,String}
    dn = DependencyNetwork{EventKey}()
    add_event!(dn, (:MoveIt, "left"),
        [(:board, 3, :occupant), (:board, 4, :occupant)],
        [(:board, 3, :occupant), (:board, 4, :rate)])
    add_event!(dn, (:MoveIt, "right"),
        [(:board, 4, :occupant), (:board, 5, :occupant)],
        [(:board, 4, :occupant), (:board, 5, :rate)])
    
    happened3 = getplace(dn, (:board, 3, :occupant))
    @test happened3.en == Set([(:MoveIt, "left")])
    @test happened3.ra == Set([(:MoveIt, "left")])
    happened4 = getplace(dn, (:board, 4, :occupant))
    @test happened4.en == Set([(:MoveIt, "left"), (:MoveIt, "right")])
    @test happened4.ra == Set([(:MoveIt, "right")])

    remove_event!(dn, [(:MoveIt, "left")])
    happened3 = getplace(dn, (:board, 3, :occupant))
    @test happened3.en == Set()
    @test happened3.ra == Set()
    happened4 = getplace(dn, (:board, 4, :occupant))
    @test happened4.en == Set([(:MoveIt, "right")])
    @test happened4.ra == Set([(:MoveIt, "right")])
    happened5 = getplace(dn, (:board, 5, :occupant))
    @test happened5.en == Set([(:MoveIt, "right")])
    @test happened5.ra == Set{EventKey}()
end


@testset "Basic DependencyNetwork with Tuple" begin
    EventKey = Tuple
    dn = DependencyNetwork{EventKey}()
    add_event!(dn, (:MoveIt, "left"),
        [(:board, 3, :occupant), (:board, 4, :occupant)],
        [(:board, 3, :occupant), (:board, 4, :rate)])
    add_event!(dn, (:MoveIt, "right"),
        [(:board, 4, :occupant), (:board, 5, :occupant)],
        [(:board, 4, :occupant), (:board, 5, :rate)])
    
    happened3 = getplace(dn, (:board, 3, :occupant))
    @test happened3.en == Set([(:MoveIt, "left")])
    @test happened3.ra == Set([(:MoveIt, "left")])
    happened4 = getplace(dn, (:board, 4, :occupant))
    @test happened4.en == Set([(:MoveIt, "left"), (:MoveIt, "right")])
    @test happened4.ra == Set([(:MoveIt, "right")])

    remove_event!(dn, [(:MoveIt, "left")])
    happened3 = getplace(dn, (:board, 3, :occupant))
    @test happened3.en == Set()
    @test happened3.ra == Set()
    happened4 = getplace(dn, (:board, 4, :occupant))
    @test happened4.en == Set([(:MoveIt, "right")])
    @test happened4.ra == Set([(:MoveIt, "right")])
    happened5 = getplace(dn, (:board, 5, :occupant))
    @test happened5.en == Set([(:MoveIt, "right")])
    @test happened5.ra == Set{EventKey}()
end


@testset "Remove Event with Set vs Array" begin
    EventKey = Tuple
    dn = DependencyNetwork{EventKey}()
    add_event!(dn, (:MoveTransition, 9, :Down),
        [(:board, 91, :occupant), (:board, 92, :occupant)],
        [])
    
    # Verify event is added
    happened91 = getplace(dn, (:board, 91, :occupant))
    @test (:MoveTransition, 9, :Down) in happened91.en
    
    # Test removing with Set (like in fire! function)
    remove_event!(dn, Set([(:MoveTransition, 9, :Down)]))
    
    # Verify event is removed
    happened91_after = getplace(dn, (:board, 91, :occupant))
    @test (:MoveTransition, 9, :Down) ∉ happened91_after.en
    @test haskey(dn.event, (:MoveTransition, 9, :Down)) == false
end
