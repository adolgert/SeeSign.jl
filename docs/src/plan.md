# Plan
 
## Current Features
 
1. Rule-based events
1. Sampling methods
1. Dirac delta function times (for ODEs)
1. Deterministic
   * Ferret out uses of Set that cause randomization.
1. Re-enabling of events
1. Rules that depend on events instead of just states.
   * Macro and struct for event(key)
1. Observers on events
1. Observers of state changes
 
## Immediate Features
 
1. Immediate events

## Future features

1. Importance sampling
1. Pregeneration of all rule-based events.
1. Transactional firing (for estimation of derivatives)
1. HMC sampling from trajectories


## Example Simulations

 1. Movement and infection.
 1. Move, infect, age, birth.
 1. Policy-driven movement.
 1. Queuing model.
 1. Chemical equations.
 1. Drone search pattern with geometry.
 1. HMC for house-to-house infestation.
 1. Job shop problem.
 1. Cars driving on a map.

## Example Uses of Simulations

 1. Hook into standard Julia analysis tools.
 1. Sampling rare events.
 1. Parameter fitting to world data.
 1. Optimization of parameters to minimize a goal function.
 1. HMC on trajectories to find a most likely event stream.
 1. POMDP

 ## Performance Questions

 1. How stable can I make the type system in the running simulation? It uses Events in places and tuples in others.
 1. The TrackedEntry needs to be timed and gamed.
 1. Could the TrackedEntry be an N-dimensional array? Could each entry be an array? A dictionary?
 1. Can the main simulation look over the keys to determine types before it instantiates?
 1. The depnet is absolutely wrong for the current main loop. It might be closer to right for another mainloop. Should try various implementations.
 1. Measure performance with profiling. Look for the memory leaks.
