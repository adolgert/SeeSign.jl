export DependencyNetwork, add_event!, remove_event!, getplace
using Base

const DNPlaceKey = Tuple{Symbol,Int64,Symbol}
DoubleEdge{T} = @NamedTuple{en::Set{T}, ra::Set{T}}

Base.zero(::Type{DoubleEdge{T}}) where {T} = (en=Set{T}(), ra=Set{T}())


"""
This is a multi-graph from places to events.
It is a multi-graph because there can be two kinds of edges from the
same place to the same event: an enabling edge and a rate edge.
The graph is mutable, too, so you can add and remove events which adds
and removes edges from the graph.
"""
struct DependencyNetwork{E}
    place::Dict{DNPlaceKey,DoubleEdge{E}}
    event::Dict{E,DoubleEdge{DNPlaceKey}}

    DependencyNetwork{E}() where {E} = new(
        Dict{DNPlaceKey,DoubleEdge{E}}(),
        Dict{E,DoubleEdge{DNPlaceKey}}()
    )
end


function add_event!(net::DependencyNetwork{E}, evtkey, enplaces, raplaces) where {E}
    # Create the reverse mapping for this event
    en_place_set = Set{DNPlaceKey}(enplaces)
    ra_place_set = Set{DNPlaceKey}(raplaces)
    net.event[evtkey] = (en=en_place_set, ra=ra_place_set)
    
    # Add enabling edges
    for place in enplaces
        if haskey(net.place, place)
            push!(net.place[place].en, evtkey)
        else
            en_set = Set{E}([evtkey])
            ra_set = Set{E}()
            net.place[place] = (en=en_set, ra=ra_set)
        end
    end
    
    # Add rate edges
    for place in raplaces
        if haskey(net.place, place)
            push!(net.place[place].ra, evtkey)
        else
            en_set = Set{E}()
            ra_set = Set{E}([evtkey])
            net.place[place] = (en=en_set, ra=ra_set)
        end
    end
end


function remove_event!(net::DependencyNetwork{E}, evtkeys) where {E}
    for evtkey in evtkeys
        # Get the places this event depends on
        if haskey(net.event, evtkey)
            event_deps = net.event[evtkey]
            
            # Remove from enabling places
            for place in event_deps.en
                if haskey(net.place, place)
                    delete!(net.place[place].en, evtkey)
                    # Clean up empty place entries if both sets are empty
                    if isempty(net.place[place].en) && isempty(net.place[place].ra)
                        delete!(net.place, place)
                    end
                end
            end
            
            # Remove from rate places
            for place in event_deps.ra
                if haskey(net.place, place)
                    delete!(net.place[place].ra, evtkey)
                    # Clean up empty place entries if both sets are empty
                    if isempty(net.place[place].en) && isempty(net.place[place].ra)
                        delete!(net.place, place)
                    end
                end
            end
            
            # Remove the event from the event dictionary
            delete!(net.event, evtkey)
        end
    end
end


getplace(net::DependencyNetwork{E}, place) where E = get(
    net.place, place, zero(DoubleEdge{E})
    )
