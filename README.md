# Octahack

An embeddable, precise and efficient modular music (or anything else you want) system. As the WIP name implies,
it's heavily inspired by Elektron's Octatrack, a ridiculously efficient hardware sampler/music workstation. This
library is designed quite differently, however. Essentially it's a digital modular rack, but designed to be
usable in a performance setting. The north star for this is to be able to build an entire set starting from a
totally blank slate.

This README is basically just a way for me to get all my thoughts out and organised, so it might get out-of-date
as the project evolves, but it will give a pretty decent overview of what I'm aiming for here.

## Concepts

We start with a rack. This has a number of inputs, corresponding to MIDI in and audio in, and a number of
outputs, corresponding to MIDI out, audio out, and cue out. The rack can contain a fixed number of components,
which can be expanded since a rack is also a component, although the maximum depth is fixed. The component set
is decided at compile-time and so no allocation is ever needed. We might want to allow users to control
sub-racks' input/output set, which would mean that more-complicated components could be built by the user out
of simpler ones and then abstracted away. You could even imagine a system of saving and loading these
more-complicated components, which I'll get to later.

Each component has inputs, outputs and parameters. The parameters are controllable centrally. This means that
sequencers can do parameter locks, we can implement something akin to the Octatrack's scene slider, and so forth.
We do want to allow controlling parameters via outputs of other components (the most immediately-obvious usecase
is an LFO component, but you can imagine all kinds of possibilities), but we also want to be able to control
parameters with physical knobs on a piece of hardware and connect them to scenes.

Speaking of scenes, these are collections of parameter values that can be interpolated between. Scenes don't
have to have every parameter set, and will fall through to the default if no value is found. We might want to
have some scene heirarchy of some kind, to allow multiple cross-fades at once. Ideally we'd allow all parameters
to be tied to a scene, but for some kinds of parameters interpolation doesn't make sense, and so it might be
better to just disallow tying these parameters to scenes entirely rather than trying to work out at what point
you should switch from one scene's value to the other's.

On top of having scenes to play with parameters mid-performance, we also have mutes. Mutes are connected to a
wiring or set of wirings, allowing the performer to disable a wire with the press of a button. This doesn't have
to be audio out - you could disable the gate wiring on an envelope generator while keeping any effect tails, or
have quick enable/disable access to an LFO's control of a parameter.

Components are written in Zig, and so the component set is just a Zig tagged union. This means that we can write
a generic UI that works for any component type and new components can be written outside of this library, while
still retaining real-time performance since it just gets compiled down to a single binary without allocation at
runtime. If you had some hardware supporting the Octahack system, you could write your own set of components for
it, compile it down and have the hardware interaction, UI, I/O wiring, scenes, parameter locks, sequencing, and
so forth just built in by default - you only have to write a set of functions that implement the actual signal
processing. Although this was designed with music in mind first, a good test of how extensible the system is
would be to try to build a piece of VJing hardware just by writing video-processing components instead of audio
ones.

I want to be able to save and load basically everything in the system - instead of having everything you can
save tied to a project, I want it to be possible to save and load at basically any level of granularity.
Sequences in the sequencer, racks, individual components with specific sets of parameters, and so forth. Then
it should be possible to load these in at runtime without having to have a clunky system of switching projects.
Ideally you should be able to have a bunch of sets saved, each representing a single track, and be able to load
them in in sequence, deciding the order on the fly, and fade between them similar to doing a DJ set except
with all the various tools for performance-time creative flair that the rest of the system is designed for.

I'm not currently 100% sure how the sequencer should work. Right now I would say the best thing to do would be to
just have a component that emits MIDI and gets special treatment in the UI, and then have a "MIDI splitter" that
can split a MIDI input into gate, CV 1..N, note and so forth outputs for a given channel. This would mean that
we can treat internal and external sequencing precisely equally, and sequence internally-generated audio and MIDI
out using the same system. You could even have multiple independent sequencers sequencing the same track. "Param
locks" could be expressed by wiring a parameter's value to the CV out of the MIDI splitter. How much of the
system we want to be MIDI-focussed isn't clear - f.e. we don't want to force a performer who wants to trigger a
recording to jump through the hoops of wiring up a "record gate" input to a MIDI keyboard just to trigger it, so
there should be easy ways to trigger most inputs when desired.

## Performance constraints

The fact that this is designed with playing live sets in mind gives us some constraints:

- No circular wiring: we don't want it to be possible to create an infinite loop. An easy and intuitive way to
  enforce this is to only allow wiring later components to earlier components in the rack, but another way is to
  execute left-to-right in the rack, saving the outputs, and so if an earlier component requests the output of a
  later one it'll simply get the value from the previous iteration.
- No mouse control: this is designed with the idea of being compiled to a free-standing OS for a piece of bespoke
  hardware, but even on a PC this should be 100% controllable with a MIDI controller (or, in a pinch, a
  keyboard).
- No "arrangement view": although we want to have a sequencer and to have this sequencer be a first-class citizen
  that is as easy-to-use as possible given the constraints, this is not and should not be designed to create a
  "fire and forget" song. Something like that is exactly what Ableton is for, this is more for the fuzzy middle
  between DJing, jamming and music production.
- Recording/looping etc is first-class: the sequencer should support recording MIDI and then manipulating it, and
  audio looping and general sampling should be as closely tied as possible. Anything you can do with samples
  should be possible with recordings from as early as the moment the recording is finished.
- Non-orthogonality: where convenience/speed and orthogonality are at odds, always choose convenience/speed. It's
  ok to have a steep learning curve, so long as someone who knows the system can get up-and-running from nothing
  fast enough for performance without having to load pre-made elements if they don't want to.

### Some random ideas without another specific place

At some point we might want to assign each output a cost, calculating the total cost of the audio out, cue 
out and MIDI out by traversing the wires and setting a maximum allowable cost.

Maybe we could have a "component arena", where racks point into this arena instead of containing their component
list inline. This would mean that we could limit the maximum number of components globally instead of limiting
depth, and since instead of Octatrack-style tracks we have racks you could choose to trade-off a single
more-complicated rack for many less-complicated ones.

How do we deal with files? It'd be good to have a slot system like the Octatrack does, but since we have a
unified sequencer we need to have some way to have MIDI control which slot we use. Perhaps we could have a
"drumkit" component with many gate inputs, and a MIDI drumkit component could emit different gate outputs
depending on which note was played. Then you could wire the audio output of the drumkit sampler through the same
pipeline that any audio goes through. You would probably want it to be possible to control the slot with CV and
the pitch with the note, though. An upside to a system that splits notes into gates would mean that if you
wanted, you could set up a synth for each drum hit with the different gates wired to each synth's gate input.
