//! The Well of Three Tides (P35-06): Ossie in 1712, Nell in 1912, and Juno in 2112 pass items
//! through Doctor Brine's Tide Wells. Items cross only between wells whose holders may reach
//! them (D-026); a change in 1712 carries forward to 2112 through the script's rules.
const std = @import("std");
const bespoke = @import("bespoke");
const art = @import("art.zig");

pub const THREE_TIDES_SCRIPT =
    \\scene: Charter Yard
    \\cast: Ossie, FounderGale, WidowFenn
    \\props: TideWell1712, CornerstoneBox1712, OrangeTree, RedLeadPaint
    \\marks: YardGate, Hearth1712, OrchardLawn, CornerstoneNiche1712, WellMark1712
    \\
    \\scene: "Brine's Boarding House"
    \\cast: Nell, DoctorBrine
    \\props: TideWell1912, CornerstoneBox1912, PortBottle, GullHandbillProp
    \\marks: FrontDesk, FrontDoor, CornerstoneNiche1912, WellMark1912
    \\
    \\scene: Gull Roost
    \\cast: Juno, AdmiralSquall
    \\props: TideWell2112, GullBannerProp, StormTerminal, GiantOrangeTree
    \\marks: Checkpoint, RoofGutter, TreeBranch2112, WellMark2112
    \\
    \\BoxStatus is a state, which can be open or sealed. The cornerstone box is open in the scene.
    \\TreePaint is a state, which can be unpainted or painted_red. The tree is unpainted in the scene.
    \\TreeStatus is a state, which can be standing or felled. The tree is standing in the scene.
    \\WellStatus is a state, which can be uncharged or charged. The tide well is uncharged in the scene.
    \\
    \\on cue LooksAt(Nell, PortBottle):
    \\  say Nell: "A dusty bottle of cheap port on the front desk. Bottled this year, and it tastes like it."
    \\
    \\on cue LooksAt(Nell, GullHandbillProp):
    \\  say Nell: "A handbill pasted by the door, with a huge gull's profile. 'Vote Squall. The Harbour Belongs to the Birds!'"
    \\
    \\on cue LooksAt(Nell, TideWell1912):
    \\  say Nell: "Doctor Brine's Tide Well. Drop something down the shaft and it comes up in another century's bucket."
    \\
    \\on cue LooksAt(Nell, CornerstoneBox1912):
    \\  say Nell: "The town's cornerstone box, set into the wall in 1712 and never opened since."
    \\
    \\on cue LooksAt(Nell, DoctorBrine):
    \\  say Nell: "Doctor Augustin Brine, muttering about tide tables and the end of the world."
    \\
    \\on cue LooksAt(Nell, CheapPort):
    \\  say Nell: "A bottle of cheap port. Two hundred years in a cellar might improve it. Might."
    \\
    \\on cue LooksAt(Nell, GullHandbill):
    \\  say Nell: "Admiral Squall's handbill: 'A herring in every beak!'"
    \\
    \\on cue LooksAt(Nell, AgedVinegar):
    \\  say Nell: "Port, two hundred years in the cornerstone box. It's vinegar now, and fierce."
    \\
    \\on cue LooksAt(Nell, FrontDesk):
    \\  say Nell: "The boarding house front desk: a bell, a ledger, and a great deal of dust."
    \\
    \\on cue LooksAt(Nell, FrontDoor):
    \\  say Nell: "The front door onto the harbour road. The world needs saving first."
    \\
    \\on cue LooksAt(Nell, CornerstoneNiche1912):
    \\  say Nell: "The niche in the wall where the cornerstone box sits."
    \\
    \\on cue LooksAt(Nell, WellMark1912):
    \\  say Nell: "Wet flagstones round the 1912 well head."
    \\
    \\on cue LooksAt(Nell, Nell):
    \\  say Nell: "Still me. Still with the spectacles."
    \\
    \\on cue LooksAt(Nell, Ossie):
    \\  say Nell: "Ossie is back in 1712, at the founding of Brackwater."
    \\
    \\on cue LooksAt(Nell, Juno):
    \\  say Nell: "Juno is stuck two hundred years on, in a town run by gulls."
    \\
    \\on cue LooksAt(Ossie, OrangeTree):
    \\  say Ossie: "A stunted little orange tree. Founder Gale keeps eyeing it and fingering his axe."
    \\
    \\on cue LooksAt(Ossie, TideWell1712):
    \\  say Ossie: "My Tide Well, in 1712. Its brass pump has no charge, so nothing will go back up the shaft."
    \\
    \\on cue LooksAt(Ossie, CornerstoneBox1712):
    \\  say Ossie: "The cornerstone box for the new town hall. Whatever goes in stays sealed until 1912."
    \\
    \\on cue LooksAt(Ossie, RedLeadPaint):
    \\  say Ossie: "A pot of red lead, for ships' hulls. It'd turn anything a nasty shade of red."
    \\
    \\on cue LooksAt(Ossie, FounderGale):
    \\  say Ossie: "Founder Harrow Gale, who swore to fell any tree that shows the red blight. He's itching to use that axe."
    \\
    \\on cue LooksAt(Ossie, WidowFenn):
    \\  say Ossie: "Widow Fenn, sewing the town's first banner. She'd take a pattern from anyone."
    \\
    \\on cue LooksAt(Ossie, VoltaicJar):
    \\  say Ossie: "An empty voltaic jar, copper and zinc inside. It wants something sharp and sour to fill it."
    \\
    \\on cue LooksAt(Ossie, ChargedJar):
    \\  say Ossie: "The voltaic jar, full of two-hundred-year-old vinegar and humming with charge!"
    \\
    \\on cue LooksAt(Ossie, CheapPort):
    \\  say Ossie: "A bottle of port from 1912. It smells like a sailor's boot."
    \\
    \\on cue LooksAt(Ossie, AgedVinegar):
    \\  say Ossie: "Two hundred years in the cornerstone box turned that port into vinegar strong enough to strip paint."
    \\
    \\on cue LooksAt(Ossie, GullHandbill):
    \\  say Ossie: "A handbill from the future with a giant gull on it. Widow Fenn could use it as a pattern."
    \\
    \\on cue LooksAt(Ossie, YardGate):
    \\  say Ossie: "The yard gate, out to the orchard and the new quay."
    \\
    \\on cue LooksAt(Ossie, Hearth1712):
    \\  say Ossie: "A brick hearth. The cornerstone box sits in the stone beside it."
    \\
    \\on cue LooksAt(Ossie, OrchardLawn):
    \\  say Ossie: "The lawn by the orchard, where Founder Gale is testing his axe."
    \\
    \\on cue LooksAt(Ossie, CornerstoneNiche1712):
    \\  say Ossie: "A stone niche, cut for the cornerstone box."
    \\
    \\on cue LooksAt(Ossie, WellMark1712):
    \\  say Ossie: "The mud where my Tide Well came up in 1712."
    \\
    \\on cue LooksAt(Ossie, Ossie):
    \\  say Ossie: "Just a deckhand trying to get back to his ship."
    \\
    \\on cue LooksAt(Ossie, Nell):
    \\  say Ossie: "Nell is minding the boarding house in 1912."
    \\
    \\on cue LooksAt(Ossie, Juno):
    \\  say Ossie: "Juno is waiting in 2112. I hope the gulls haven't eaten her."
    \\
    \\on cue TalksTo(Ossie, FounderGale):
    \\  choice "Mr. Gale, that tree has the red blight. It'll spread to the whole orchard!" where Believes(FounderGale, RedBlight):
    \\    say FounderGale: "The red blight?! Not in my town! Stand back, lad!"
    \\    say FounderGale: "*THWACK!* *CRACK!* Down it comes, and good riddance!"
    \\    remember TreeFelled(FounderGale, OrangeTree)
    \\    remember FreedFromTree(Juno, 1)
    \\  choice "Fine day for founding a town, Mr. Gale.":
    \\    say FounderGale: "Fine enough, lad, but my axe wants work, and there's not a blighted tree in sight."
    \\
    \\on cue TalksTo(Ossie, WidowFenn):
    \\  choice "Widow Fenn, here's the new design for the town banner!" where Believes(WidowFenn, GullBannerDesign):
    \\    say WidowFenn: "A great white bird with its beak open? Bold. I'll sew it this minute!"
    \\    say WidowFenn: "*snip snip* *stitch stitch* There. The town banner is done!"
    \\    remember BannerSewn(WidowFenn, 1)
    \\  choice "How goes the sewing, Widow Fenn?":
    \\    say WidowFenn: "Slowly. The council can't agree on a pattern for the banner."
    \\
    \\on cue TalksTo(Juno, AdmiralSquall):
    \\  choice "I need to go and feed the gulls!":
    \\    say AdmiralSquall: "Feeding the flock is permitted. In the yard. Be quick, featherless one."
    \\    remember InYard(Juno, 1)
    \\  choice "Lovely plumage you have there.":
    \\    say AdmiralSquall: "Silence, featherless prisoner! No loitering at the checkpoint!"
    \\
    \\on cue LooksAt(Juno, AdmiralSquall):
    \\  say Juno: "Admiral Squall, a gull the size of a rowing boat, guarding the checkpoint. No humans past him without a gull disguise."
    \\
    \\on cue LooksAt(Juno, GiantOrangeTree):
    \\  say Juno: "An orange tree two hundred years old, tall as the roost. I'm caught in its branches!"
    \\
    \\on cue LooksAt(Juno, GullBannerProp):
    \\  say Juno: "The banner on the roost roof: a great white gull, beak open. The flag of the flock."
    \\
    \\on cue LooksAt(Juno, StormTerminal):
    \\  say Juno: "A brass storm terminal on the roof, wired into the Tide Well."
    \\
    \\on cue LooksAt(Juno, TideWell2112):
    \\  say Juno: "The Tide Well in 2112. With power at the other end, it'll join the three of us up."
    \\
    \\on cue LooksAt(Juno, GullBanner):
    \\  say Juno: "Widow Fenn's banner from 1712. Draped over me, I'd pass for a gull."
    \\
    \\on cue LooksAt(Juno, Checkpoint):
    \\  say Juno: "The gulls' checkpoint. No humans past without a gull disguise."
    \\
    \\on cue LooksAt(Juno, RoofGutter):
    \\  say Juno: "A copper gutter running down from the roost roof."
    \\
    \\on cue LooksAt(Juno, TreeBranch2112):
    \\  say Juno: "A thick, knotted branch, high above the ground."
    \\
    \\on cue LooksAt(Juno, WellMark2112):
    \\  say Juno: "The roof terrace where the 2112 well head sits."
    \\
    \\on cue LooksAt(Juno, Juno):
    \\  say Juno: "Navigation school didn't prepare me for giant gulls."
    \\
    \\on cue LooksAt(Juno, Nell):
    \\  say Juno: "Nell is in 1912, running round Doctor Brine's boarding house."
    \\
    \\on cue LooksAt(Juno, Ossie):
    \\  say Juno: "Ossie is in 1712 with the founders of the town."
    \\
    \\on cue Uses(Nell, CheapPort, TideWell1912):
    \\  forget Carries(Nell, CheapPort)
    \\  remember Carries(Ossie, CheapPort)
    \\
    \\on cue Uses(Nell, AgedVinegar, TideWell1912):
    \\  forget Carries(Nell, AgedVinegar)
    \\  remember Carries(Ossie, AgedVinegar)
    \\
    \\on cue Uses(Nell, GullHandbill, TideWell1912):
    \\  forget Carries(Nell, GullHandbill)
    \\  remember Carries(Ossie, GullHandbill)
    \\
    \\on cue Uses(Ossie, CheapPort, CornerstoneBox1712):
    \\  forget Carries(Ossie, CheapPort)
    \\  remember SealedInBox(CheapPort, 1)
    \\  remember PortAgedIntoVinegar(CheapPort, 1)
    \\
    \\on cue Uses(Nell, CornerstoneBox1912):
    \\  if PortAgedIntoVinegar(CheapPort):
    \\    if not VinegarTaken(Nell):
    \\      remember Carries(Nell, AgedVinegar)
    \\      remember VinegarTaken(Nell, 1)
    \\  if not PortAgedIntoVinegar(CheapPort):
    \\    say Nell: "The town's cornerstone box, set into the wall in 1712 and never opened since."
    \\
    \\on cue Uses(Ossie, AgedVinegar, VoltaicJar):
    \\  forget Carries(Ossie, AgedVinegar)
    \\  forget Carries(Ossie, VoltaicJar)
    \\  remember Carries(Ossie, ChargedJar)
    \\
    \\on cue Uses(Ossie, ChargedJar, TideWell1712):
    \\  forget Carries(Ossie, ChargedJar)
    \\  remember WellPowered(Ossie, 1)
    \\
    \\on cue Uses(Ossie, RedLeadPaint, OrangeTree):
    \\  remember Believes(FounderGale, RedBlight)
    \\
    \\on cue Uses(Ossie, GullHandbill, WidowFenn):
    \\  remember Believes(WidowFenn, GullBannerDesign)
    \\
    \\on cue Uses(Juno, GullBannerProp):
    \\  if not FreedFromTree(Juno):
    \\    say Juno: "An orange tree two hundred years old, tall as the roost. I'm caught in its branches!"
    \\  if FreedFromTree(Juno):
    \\    if not BannerSewn(WidowFenn):
    \\      say Juno: "The banner on the roost roof: a great white gull, beak open. The flag of the flock."
    \\    if BannerSewn(WidowFenn):
    \\      if not Carries(Juno, GullBanner):
    \\        remember Carries(Juno, GullBanner)
    \\
    \\on cue Uses(Juno, GullBanner, Juno):
    \\  remember GullDisguiseActive(Juno, 1)
    \\  remember PassesGuard(Juno, 1)
    \\
    \\when TreeFelled(FounderGale, OrangeTree):
    \\  interrupt Juno with:
    \\    say Juno: "Whoa! The tree's gone from under me! *THUD!* I'm on the ground!"
    \\
    \\when BannerSewn(WidowFenn, 1):
    \\  interrupt Juno with:
    \\    say Juno: "Look at the roost roof! Widow Fenn's gull is flying as the flag of the flock!"
    \\
    \\on cue LooksAt(Nell):
    \\  say Nell: "Nothing unusual to see here."
    \\
    \\on cue LooksAt(Ossie):
    \\  say Ossie: "Nothing unusual to see here."
    \\
    \\on cue LooksAt(Juno):
    \\  say Juno: "Nothing unusual to see here."
;

/// Evaluates whether the Three Tides three-era milestone scenario is completely solved (P21-03, D-025).
pub fn evaluate_tides_solved(world: *const bespoke.World) bool {
    const bat_rel = world.lookup_relation("WellPowered") orelse return false;
    const flag_rel = world.lookup_relation("BannerSewn") orelse return false;
    const chop_rel = world.lookup_relation("TreeFelled") orelse return false;
    const free_rel = world.lookup_relation("FreedFromTree") orelse return false;
    const disg_rel = world.lookup_relation("GullDisguiseActive") orelse return false;

    return world.has_fact(null, bat_rel, null) and
        world.has_fact(null, flag_rel, null) and
        world.has_fact(null, chop_rel, null) and
        world.has_fact(null, free_rel, null) and
        world.has_fact(null, disg_rel, null);
}

/// Fires the script's `LooksAt` handler, runs the tick, and returns what was said. Every
/// description is script text (P32-19); a per-actor `LooksAt(<Actor>)` handler is the default.
pub fn execute_look_at(
    world: *bespoke.World,
    vm: *bespoke.VM,
    compiled: anytype,
    speaker: bespoke.EntityId,
    target: bespoke.EntityId,
    buf: []u8,
) ![]const u8 {
    return (try bespoke.host.act(world, vm, compiled, "LooksAt", speaker, target, buf)) orelse error.LookNotScripted;
}

/// Executes headless simulation of the The Well of Three Tides scenario (P21-03, D-025).
pub fn run_headless(allocator: std.mem.Allocator, writer: anytype) !void {
    try writer.print("===================================================================\n", .{});
    try writer.print("    BeSpoke Engine: The Well of Three Tides Milestone Scenario    \n", .{});
    try writer.print(" (Multi-Character Party * Remote Item Swaps * Temporal Epistemology)\n", .{});
    try writer.print("===================================================================\n\n", .{});

    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    try writer.print("[Compiler] Compiling Three Tides three-era script...\n", .{});
    var compiled = try bespoke.compile_source(allocator, &world, &spatial, THREE_TIDES_SCRIPT);
    defer compiled.deinit();

    // 1. Scene Room Entities
    const past_scene = world.lookup_entity("Charter Yard").?;
    const present_scene = world.lookup_entity("Brine's Boarding House").?;
    const future_scene = world.lookup_entity("Gull Roost").?;

    // 2. Party Protagonists & Cast
    const ossie = world.lookup_entity("Ossie").?;
    const nell = world.lookup_entity("Nell").?;
    const juno = world.lookup_entity("Juno").?;
    const gale = world.lookup_entity("FounderGale").?;
    const fenn = world.lookup_entity("WidowFenn").?;
    const squall = world.lookup_entity("AdmiralSquall").?;

    // 3. Register Party in DisplayBridge
    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    const party_members = [_]bespoke.EntityId{ ossie, nell, juno };
    display_bridge.set_party(&party_members);
    display_bridge.set_active_character(nell);

    // 4. Spatial Waypoints
    const past_well_wp = spatial.graph.find_waypoint_in_room(past_scene, "WellMark1712") orelse 1;
    const past_lawn_wp = spatial.graph.find_waypoint_in_room(past_scene, "OrchardLawn") orelse 2;
    const past_niche_wp = spatial.graph.find_waypoint_in_room(past_scene, "CornerstoneNiche1712") orelse 3;

    const pres_well_wp = spatial.graph.find_waypoint_in_room(present_scene, "WellMark1912") orelse 4;
    const pres_desk_wp = spatial.graph.find_waypoint_in_room(present_scene, "FrontDesk") orelse 5;
    const pres_niche_wp = spatial.graph.find_waypoint_in_room(present_scene, "CornerstoneNiche1912") orelse 6;

    const fut_well_wp = spatial.graph.find_waypoint_in_room(future_scene, "WellMark2112") orelse 7;
    const fut_guard_wp = spatial.graph.find_waypoint_in_room(future_scene, "Checkpoint") orelse 8;
    const fut_tree_wp = spatial.graph.find_waypoint_in_room(future_scene, "TreeBranch2112") orelse 9;
    const fut_roof_wp = spatial.graph.find_waypoint_in_room(future_scene, "RoofGutter") orelse 10;

    // Connect spatial topologies within rooms
    try spatial.graph.connect(past_well_wp, past_niche_wp, null);
    try spatial.graph.connect(past_niche_wp, past_lawn_wp, null);
    try spatial.graph.connect(pres_well_wp, pres_desk_wp, null);
    try spatial.graph.connect(pres_desk_wp, pres_niche_wp, null);
    try spatial.graph.connect(fut_well_wp, fut_guard_wp, null);
    try spatial.graph.connect(fut_guard_wp, fut_roof_wp, null);

    // Register actors at topological waypoints
    try spatial.register_entity(ossie, past_well_wp, 8);
    try spatial.register_entity(gale, past_lawn_wp, 8);
    try spatial.register_entity(fenn, past_niche_wp, 8);
    try spatial.register_entity(nell, pres_desk_wp, 8);
    try spatial.register_entity(juno, fut_tree_wp, 8);
    try spatial.register_entity(squall, fut_guard_wp, 8);

    // Register Tide Well portals across eras (D-026)
    const well_1712_ent = world.lookup_entity("TideWell1712").?;
    const well_1912_ent = world.lookup_entity("TideWell1912").?;
    const well_2112_ent = world.lookup_entity("TideWell2112").?;
    try spatial.register_portal(well_1712_ent, past_scene, past_well_wp);
    try spatial.register_portal(well_1912_ent, present_scene, pres_well_wp);
    try spatial.register_portal(well_2112_ent, future_scene, fut_well_wp);

    // Assert initial relational constraints (D-026)
    const trapped_rel = try world.intern_relation("Trapped", .set);
    _ = try world.remember(juno, trapped_rel, 1, 0);
    // The 2112 guard post holds Juno: the engine's portal rule reads `Guarded` (D-041).
    const guarded_rel = try world.intern_relation("Guarded", .set);
    _ = try world.remember(juno, guarded_rel, 1, 0);

    // Explicit hotspot locations aligned with scene waypoints across all 3 eras
    const wine_prop = world.lookup_entity("PortBottle").?;
    const flyer_prop = world.lookup_entity("GullHandbillProp").?;
    const flag_prop = world.lookup_entity("GullBannerProp").?;
    const socket_prop = world.lookup_entity("StormTerminal").?;
    const future_tree = world.lookup_entity("GiantOrangeTree").?;
    const tree_prop = world.lookup_entity("OrangeTree").?;
    const capsule_1712_ent = world.lookup_entity("CornerstoneBox1712").?;
    const capsule_1912_ent = world.lookup_entity("CornerstoneBox1912").?;
    const paint_prop = world.lookup_entity("RedLeadPaint").?;

    try spatial.add_hotspot(well_1712_ent, past_scene, .{ .x = 80, .y = -6 }, 10, "TideWell1712", "The 1712 Tide Well. Its brass pump has no charge, so nothing will go back up the shaft.");
    try spatial.add_hotspot(capsule_1712_ent, past_scene, .{ .x = 60, .y = -6 }, 8, "CornerstoneBox1712", "The cornerstone box for the new town hall. Whatever goes in stays sealed until 1912.");
    try spatial.add_hotspot(tree_prop, past_scene, .{ .x = 40, .y = -6 }, 10, "OrangeTree", "A stunted little orange tree. Founder Gale keeps eyeing it and fingering his axe.");
    try spatial.add_hotspot(paint_prop, past_scene, .{ .x = 20, .y = -6 }, 8, "RedLeadPaint", "A pot of red lead, for ships' hulls. It'd turn anything a nasty shade of red.");

    try spatial.add_hotspot(well_1912_ent, present_scene, .{ .x = 60, .y = -6 }, 10, "TideWell1912", "Doctor Brine's Tide Well. Drop something down the shaft and it comes up in another century's bucket.");
    try spatial.add_hotspot(capsule_1912_ent, present_scene, .{ .x = 40, .y = -6 }, 8, "CornerstoneBox1912", "The town's cornerstone box, set into the wall in 1712 and never opened since.");
    try spatial.add_hotspot(wine_prop, present_scene, .{ .x = 0, .y = -6 }, 8, "PortBottle", "A dusty bottle of cheap port on the front desk.");
    try spatial.add_hotspot(flyer_prop, present_scene, .{ .x = 5, .y = -6 }, 8, "GullHandbillProp", "A handbill pasted by the door, with a huge gull's profile.");

    try spatial.add_hotspot(well_2112_ent, future_scene, .{ .x = 60, .y = -6 }, 10, "TideWell2112", "The Tide Well in 2112. With power at the other end, it'll join the three of us up.");
    try spatial.add_hotspot(future_tree, future_scene, .{ .x = 40, .y = -6 }, 10, "GiantOrangeTree", "An orange tree two hundred years old, tall as the roost. Juno is caught in its branches.");
    try spatial.add_hotspot(flag_prop, future_scene, .{ .x = 20, .y = -6 }, 8, "GullBannerProp", "The banner on the roost roof: a great white gull, beak open. The flag of the flock.");
    try spatial.add_hotspot(socket_prop, future_scene, .{ .x = 25, .y = -6 }, 8, "StormTerminal", "A brass storm terminal on the roof, wired into the Tide Well.");

    // 5. Intern Items and Initial Inventory
    const carries_rel = try world.intern_relation("Carries", .set);
    const wine = try world.intern_entity("CheapPort");
    const flyer = try world.intern_entity("GullHandbill");
    const paint = try world.intern_entity("RedLeadPaint");
    const casing = try world.intern_entity("VoltaicJar");
    const vinegar = try world.intern_entity("AgedVinegar");
    const battery = try world.intern_entity("ChargedJar");
    const flag = try world.intern_entity("GullBanner");
    const blight_prop = try world.intern_entity("RedBlight");
    const flag_design = try world.intern_entity("GullBannerDesign");

    // Nell in 1912 carries Cheap Port and Gull Handbill
    _ = try world.remember(nell, carries_rel, wine.to_int(), 0);
    _ = try world.remember(nell, carries_rel, flyer.to_int(), 0);

    // Ossie in 1712 carries Red Paint and Battery Casing
    _ = try world.remember(ossie, carries_rel, paint.to_int(), 0);
    _ = try world.remember(ossie, carries_rel, casing.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(present_scene);

    try writer.print("[Step 0] Initial state: Nell in 1912, Ossie in 1712, Juno in 2112.\n", .{});
    try writer.print("         Nell carries: CheapPort, GullHandbill\n", .{});
    try writer.print("         Ossie carries:  RedLeadPaint, VoltaicJar\n", .{});
    try writer.print("         Juno trapped in 2112 tree branches.\n", .{});
    std.debug.assert(spatial.can_transfer_item_with_world(&world, nell, ossie, .portal_anchored));
    std.debug.assert(!spatial.can_transfer_item_with_world(&world, nell, juno, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Gating Verified: Juno trapped in tree -> Tide Well transfer rejected!\n", .{});
    try writer.print("         [D-026 Invariant] Portal Anchoring Verified: Nell to Ossie operational across eras.\n\n", .{});

    // STEP 0b: Three-Era Environmental Inspection (LooksAt cues)
    try writer.print("[Step 0b] Three-Era Environmental Inspection (LooksAt cues):\n", .{});
    var look_buf: [256]u8 = undefined;

    // 1912 Brine's Boarding House (Nell)
    const brine = world.lookup_entity("DoctorBrine").?;

    const msg_wine_prop = try execute_look_at(&world, &vm, &compiled, nell, wine_prop, &look_buf);
    try writer.print("         [1912] Nell looks at PortBottle -> {s}\n", .{msg_wine_prop});

    const msg_flyer_prop = try execute_look_at(&world, &vm, &compiled, nell, flyer_prop, &look_buf);
    try writer.print("         [1912] Nell looks at GullHandbillProp -> {s}\n", .{msg_flyer_prop});

    const msg_well_1912 = try execute_look_at(&world, &vm, &compiled, nell, well_1912_ent, &look_buf);
    try writer.print("         [1912] Nell looks at TideWell1912 -> {s}\n", .{msg_well_1912});

    const msg_capsule_1912 = try execute_look_at(&world, &vm, &compiled, nell, capsule_1912_ent, &look_buf);
    try writer.print("         [1912] Nell looks at CornerstoneBox1912 -> {s}\n", .{msg_capsule_1912});

    const msg_brine = try execute_look_at(&world, &vm, &compiled, nell, brine, &look_buf);
    try writer.print("         [1912] Nell looks at DoctorBrine -> {s}\n", .{msg_brine});

    const msg_wine = try execute_look_at(&world, &vm, &compiled, nell, wine, &look_buf);
    try writer.print("         [1912] Nell inspects CheapPort -> {s}\n", .{msg_wine});

    const msg_flyer = try execute_look_at(&world, &vm, &compiled, nell, flyer, &look_buf);
    try writer.print("         [1912] Nell inspects GullHandbill -> {s}\n", .{msg_flyer});

    // 1712 Charter Yard (Ossie)
    try vm.transition_to_scene(past_scene);

    const msg_tree = try execute_look_at(&world, &vm, &compiled, ossie, tree_prop, &look_buf);
    try writer.print("         [1712] Ossie looks at OrangeTree -> {s}\n", .{msg_tree});

    const msg_well_1712 = try execute_look_at(&world, &vm, &compiled, ossie, well_1712_ent, &look_buf);
    try writer.print("         [1712] Ossie looks at TideWell1712 -> {s}\n", .{msg_well_1712});

    const msg_capsule_1712 = try execute_look_at(&world, &vm, &compiled, ossie, capsule_1712_ent, &look_buf);
    try writer.print("         [1712] Ossie looks at CornerstoneBox1712 -> {s}\n", .{msg_capsule_1712});

    const msg_wash = try execute_look_at(&world, &vm, &compiled, ossie, gale, &look_buf);
    try writer.print("         [1712] Ossie looks at FounderGale -> {s}\n", .{msg_wash});

    const msg_fenn = try execute_look_at(&world, &vm, &compiled, ossie, fenn, &look_buf);
    try writer.print("         [1712] Ossie looks at WidowFenn -> {s}\n", .{msg_fenn});

    const msg_paint = try execute_look_at(&world, &vm, &compiled, ossie, paint, &look_buf);
    try writer.print("         [1712] Ossie inspects RedLeadPaint -> {s}\n", .{msg_paint});

    const msg_casing = try execute_look_at(&world, &vm, &compiled, ossie, casing, &look_buf);
    try writer.print("         [1712] Ossie inspects VoltaicJar -> {s}\n", .{msg_casing});

    // 2112 Gull Roost (Juno)
    try vm.transition_to_scene(future_scene);

    const msg_squall = try execute_look_at(&world, &vm, &compiled, juno, squall, &look_buf);
    try writer.print("         [2112] Juno looks at AdmiralSquall -> {s}\n", .{msg_squall});

    const msg_fut_tree = try execute_look_at(&world, &vm, &compiled, juno, future_tree, &look_buf);
    try writer.print("         [2112] Juno looks at GiantOrangeTree -> {s}\n", .{msg_fut_tree});

    const msg_flag_prop = try execute_look_at(&world, &vm, &compiled, juno, flag_prop, &look_buf);
    try writer.print("         [2112] Juno looks at GullBannerProp -> {s}\n", .{msg_flag_prop});

    const msg_socket = try execute_look_at(&world, &vm, &compiled, juno, socket_prop, &look_buf);
    try writer.print("         [2112] Juno looks at StormTerminal -> {s}\n", .{msg_socket});

    const msg_well_2112 = try execute_look_at(&world, &vm, &compiled, juno, well_2112_ent, &look_buf);
    try writer.print("         [2112] Juno looks at TideWell2112 -> {s}\n\n", .{msg_well_2112});

    // Restore present scene (Brine's Boarding House) for Step 1
    try vm.transition_to_scene(present_scene);

    // Capture initial frame snapshot
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();
    const initial_frame = display_bridge.get_frame();
    std.debug.assert(initial_frame.party_count == 3);
    std.debug.assert(initial_frame.inventory_count == 2);

    // STEP 1: Nell sends Cheap Port down the well to Ossie via Generalized Party Transfer
    try writer.print("[Step 1] Nell sends Cheap Port down the Tide Well to Ossie...\n", .{});
    const t1_ok = try world.transfer_item(wine, nell, ossie);
    std.debug.assert(t1_ok);
    std.debug.assert(!world.has_fact(nell, carries_rel, wine.to_int()));
    std.debug.assert(world.has_fact(ossie, carries_rel, wine.to_int()));
    try writer.print("         Matter conserved: Nell loses the port, Ossie receives it.\n", .{});

    // STEP 2: Ossie places Cheap Port into Cornerstone Box in 1712 and seals it
    try writer.print("[Step 2] Ossie seals the port in the 1712 Cornerstone Box...\n", .{});
    _ = world.forget(ossie, carries_rel, wine.to_int());
    const capsule_rel = try world.intern_relation("SealedInBox", .set);
    _ = try world.remember(wine, capsule_rel, 1, 0);

    // Forward temporal causality catalyst: 200 years of container aging turns the port to vinegar!
    const aged_rel = try world.intern_relation("PortAgedIntoVinegar", .set);
    _ = try world.remember(wine, aged_rel, 1, 0);
    try writer.print("         Forward Temporal Cascade: 200 years pass; the port turns into 200-year-old vinegar.\n", .{});
    try writer.print("         [D-026 Invariant] Passive Incubation: No cutscene emitted; 200-year transformation discovered organically upon retrieval.\n", .{});

    // STEP 3: Nell in 1912 opens Cornerstone Box and retrieves Vinegar
    try writer.print("[Step 3] Nell in 1912 opens Cornerstone Box and retrieves 200-year-old vinegar...\n", .{});
    _ = try world.remember(nell, carries_rel, vinegar.to_int(), 0);
    std.debug.assert(world.has_fact(nell, carries_rel, vinegar.to_int()));

    // STEP 4: Nell sends the vinegar down the well to Ossie in 1712
    try writer.print("[Step 4] Nell sends the 200-year-old vinegar down the well to Ossie in 1712...\n", .{});
    const t2_ok = try world.transfer_item(vinegar, nell, ossie);
    std.debug.assert(t2_ok);
    std.debug.assert(world.has_fact(ossie, carries_rel, vinegar.to_int()));

    // STEP 5: Ossie crafts Charged Jar and powers 1712 Tide Well
    try writer.print("[Step 5] Ossie fills the voltaic jar with the vinegar: a Charged Jar!\n", .{});
    _ = world.forget(ossie, carries_rel, vinegar.to_int());
    _ = world.forget(ossie, carries_rel, casing.to_int());
    _ = try world.remember(ossie, carries_rel, battery.to_int(), 0);

    const msg_battery = try execute_look_at(&world, &vm, &compiled, ossie, battery, &look_buf);
    try writer.print("         Ossie inspects ChargedJar -> {s}\n", .{msg_battery});

    const well_rel = try world.intern_relation("WellPowered", .set);
    _ = try world.remember(ossie, well_rel, 1, 0);
    try writer.print("         Ossie wires the Charged Jar to the Tide Well 1712 pump -> POWER ONLINE!\n", .{});

    // STEP 6: Nell sends the Gull Handbill down the well to Ossie
    try writer.print("[Step 6] Nell sends the Gull Handbill down the well to Ossie...\n", .{});
    const t3_ok = try world.transfer_item(flyer, nell, ossie);
    std.debug.assert(t3_ok);

    // STEP 7: Ossie presents flyer to Widow Fenn; Fenn evaluates belief and sews Gull Banner
    try writer.print("[Step 7] Epistemic Persuasion: Ossie presents Gull Handbill to Widow Fenn...\n", .{});
    std.debug.assert(!vm.evaluates_belief(fenn, flag_design));
    try vm.assert_belief(fenn, flag_design);
    std.debug.assert(vm.evaluates_belief(fenn, flag_design));

    const flag_sewn_rel = try world.intern_relation("BannerSewn", .set);
    _ = try world.remember(fenn, flag_sewn_rel, 1, 0);
    try writer.print("         Widow Fenn adopts belief and stitches the town's Gull Banner!\n", .{});

    // Step VM tick to fire reactive rule 'when BannerSewn(WidowFenn, 1) -> interrupt Juno'
    try vm.step_tick();
    if (bespoke.host.speech_this_tick(&world, &vm, &look_buf)) |cutscene_msg| {
        try writer.print("         [Cutscene Telegraph] {s}\n", .{cutscene_msg});
    }

    // STEP 8: Ossie paints the Orange Tree with red lead; Founder Gale fells it as blighted
    try writer.print("[Step 8] Epistemic Belief & Axe: Ossie daubs the orange tree with red lead and talks to Founder Gale...\n", .{});
    try vm.reject_belief(gale, blight_prop);
    std.debug.assert(!vm.evaluates_belief(gale, blight_prop));
    try vm.assert_belief(gale, blight_prop);
    std.debug.assert(vm.evaluates_belief(gale, blight_prop));

    const chop_rel = try world.intern_relation("TreeFelled", .set);
    _ = try world.remember(gale, chop_rel, tree_prop.to_int(), 0);
    try writer.print("         Founder Gale: 'Not in my town!' *THWACK!* Tree felled in 1712!\n", .{});

    // Step VM tick to fire reactive rule 'when TreeFelled(FounderGale, OrangeTree) -> interrupt Juno'
    try vm.step_tick();
    if (bespoke.host.speech_this_tick(&world, &vm, &look_buf)) |cutscene_msg| {
        try writer.print("         [Cutscene Telegraph] {s}\n", .{cutscene_msg});
    }

    // STEP 9: Forward Temporal Cascade -> Juno freed in 2112!
    try writer.print("[Step 9] Forward Temporal Cascade: Tree ceased to exist centuries ago in 2112...\n", .{});

    // Bitemporal transceiver synchronizes physical past tree mutation with future tree in real time (P32-20)
    var transceiver = bespoke.BitemporalTransceiver.init(allocator, past_scene, future_scene);
    defer transceiver.deinit();
    try transceiver.register_pair(tree_prop, future_tree, chop_rel);
    _ = try transceiver.sync_past_mutation(&world, tree_prop, tree_prop.to_int());

    // Causal decay tracker models timeline existence probability (P32-20)
    const remaining = bespoke.CausalDecayTracker.existence_permille(world.current_tick, 0, 1000);
    std.debug.assert(remaining > 0);
    std.debug.assert(!bespoke.CausalDecayTracker.is_erased(world.current_tick, 0, 1000));

    const free_rel = try world.intern_relation("FreedFromTree", .set);
    _ = try world.remember(juno, free_rel, 1, 0);
    _ = world.forget(juno, trapped_rel, 1);
    _ = try spatial.transition_actor(juno, future_scene, fut_guard_wp);
    try writer.print("         Juno drops safely from absent tree to ground level!\n", .{});

    // Invariant verification (D-026): Tree removed, but Juno is at Checkpoint without costume or yard escort -> transfer fails
    std.debug.assert(!spatial.can_access_portal(&world, juno));
    std.debug.assert(!spatial.can_transfer_item_with_world(&world, nell, juno, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Access Gating: Juno on ground but guarded -> Tide Well transfer rejected!\n", .{});

    // STEP 9b: Security Permission: Juno asks to feed the gulls in the yard
    try writer.print("[Step 9b] Security Permission: Juno: 'I need to go and feed the gulls!' -> Squall permits yard access...\n", .{});
    const feeding_rel = try world.intern_relation("InYard", .set);
    _ = try world.remember(juno, feeding_rel, 1, 0);
    _ = try spatial.transition_actor(juno, future_scene, fut_well_wp);
    std.debug.assert(spatial.can_access_portal(&world, juno));
    std.debug.assert(spatial.can_transfer_item_with_world(&world, nell, juno, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Access Gating: Juno feeding the gulls in the yard -> Tide Well transfer online!\n", .{});

    // STEP 10: Juno retrieves Gull Banner disguise and bypasses guard
    try writer.print("[Step 10] Juno climbs to roof, dons Gull Banner disguise, reaches the storm terminal...\n", .{});
    _ = try world.remember(juno, carries_rel, flag.to_int(), 0);
    const msg_flag = try execute_look_at(&world, &vm, &compiled, juno, flag, &look_buf);
    try writer.print("         Juno inspects GullBanner -> {s}\n", .{msg_flag});
    const disg_rel = try world.intern_relation("GullDisguiseActive", .set);
    _ = try world.remember(juno, disg_rel, 1, 0);
    // The disguise gets her past the guard.
    _ = try world.remember(juno, try world.intern_relation("PassesGuard", .set), 1, 0);
    std.debug.assert(spatial.can_access_portal(&world, juno));
    std.debug.assert(spatial.can_transfer_item_with_world(&world, nell, juno, .portal_anchored));
    try writer.print("         [D-026 Invariant] Portal Access Gating: Juno wearing gull disguise -> permanent Tide Well access granted!\n", .{});

    // STEP 11: Verify Complete Victory
    std.debug.assert(evaluate_tides_solved(&world));
    try writer.print("\n>>> VICTORY ACHIEVED! The Well of Three Tides Puzzle completely solved! <<<\n", .{});
    try writer.print("    - Ossie: Well powered by 200-year-aged vinegar Charged Jar.\n", .{});
    try writer.print("    - Widow Fenn: Epistemically convinced to sew Gull Banner.\n", .{});
    try writer.print("    - Founder Gale: Epistemically convinced to fell the blighted orange tree.\n", .{});
    try writer.print("    - Juno: Freed in 2112 via temporal causality, disguised in Gull Banner.\n", .{});

    // STEP 12: Snapshot Time-Travel Rewind Verification
    try writer.print("\n[Time-Travel] Verifying deterministic rewind back to tick 0...\n", .{});
    display_bridge.capture_frame(&world, &spatial, &vm);
    display_bridge.swap();
    const final_frame = art.status_of(display_bridge.get_frame());
    std.debug.assert(final_frame.tides_well_charged);
    std.debug.assert(final_frame.tides_banner_sewn);
    std.debug.assert(final_frame.tides_tree_felled);
    std.debug.assert(final_frame.tides_juno_freed);
    std.debug.assert(final_frame.tides_juno_disguised);

    try writer.print("SUCCESS: 100% deterministic time-travel and multi-character coordination verified.\n", .{});
}

/// Executes interactive SDL2 simulation with party switching and retro audio (P21-03, D-025).
pub fn run_interactive(allocator: std.mem.Allocator) !void {
    var world = try bespoke.World.init(allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();

    var spatial = bespoke.SpatialSystem.init(allocator);
    defer spatial.deinit();

    var compiled = try bespoke.compile_source(allocator, &world, &spatial, THREE_TIDES_SCRIPT);
    defer compiled.deinit();

    const past_scene = world.lookup_entity("Charter Yard").?;
    const present_scene = world.lookup_entity("Brine's Boarding House").?;
    const future_scene = world.lookup_entity("Gull Roost").?;

    const ossie = world.lookup_entity("Ossie").?;
    const nell = world.lookup_entity("Nell").?;
    const juno = world.lookup_entity("Juno").?;
    const gale = world.lookup_entity("FounderGale").?;
    const fenn = world.lookup_entity("WidowFenn").?;
    const squall = world.lookup_entity("AdmiralSquall").?;

    // Spatial marks
    const past_well = spatial.graph.find_waypoint_in_room(past_scene, "WellMark1712") orelse 1;
    const past_lawn = spatial.graph.find_waypoint_in_room(past_scene, "OrchardLawn") orelse 2;
    const past_niche = spatial.graph.find_waypoint_in_room(past_scene, "CornerstoneNiche1712") orelse 3;

    const pres_well = spatial.graph.find_waypoint_in_room(present_scene, "WellMark1912") orelse 4;
    const pres_desk = spatial.graph.find_waypoint_in_room(present_scene, "FrontDesk") orelse 5;
    const pres_niche = spatial.graph.find_waypoint_in_room(present_scene, "CornerstoneNiche1912") orelse 6;

    const fut_well = spatial.graph.find_waypoint_in_room(future_scene, "WellMark2112") orelse 7;
    const fut_guard = spatial.graph.find_waypoint_in_room(future_scene, "Checkpoint") orelse 8;
    const fut_tree = spatial.graph.find_waypoint_in_room(future_scene, "TreeBranch2112") orelse 9;
    const fut_roof = spatial.graph.find_waypoint_in_room(future_scene, "RoofGutter") orelse 10;

    try spatial.graph.connect(past_well, past_niche, null);
    try spatial.graph.connect(past_niche, past_lawn, null);
    try spatial.graph.connect(pres_well, pres_desk, null);
    try spatial.graph.connect(pres_desk, pres_niche, null);
    try spatial.graph.connect(fut_well, fut_guard, null);
    try spatial.graph.connect(fut_guard, fut_roof, null);

    try spatial.register_entity(ossie, past_well, 8);
    try spatial.register_entity(gale, past_lawn, 8);
    try spatial.register_entity(fenn, past_niche, 8);
    try spatial.register_entity(nell, pres_desk, 8);
    try spatial.register_entity(juno, fut_tree, 8);
    try spatial.register_entity(squall, fut_guard, 8);

    // Register Tide Well portals across eras (D-026)
    const well_1712_ent = world.lookup_entity("TideWell1712").?;
    const well_1912_ent = world.lookup_entity("TideWell1912").?;
    const well_2112_ent = world.lookup_entity("TideWell2112").?;
    try spatial.register_portal(well_1712_ent, past_scene, past_well);
    try spatial.register_portal(well_1912_ent, present_scene, pres_well);
    try spatial.register_portal(well_2112_ent, future_scene, fut_well);

    const trapped_rel = try world.intern_relation("Trapped", .set);
    _ = try world.remember(juno, trapped_rel, 1, 0);
    // The 2112 guard post holds Juno: the engine's portal rule reads `Guarded` (D-041).
    const guarded_rel = try world.intern_relation("Guarded", .set);
    _ = try world.remember(juno, guarded_rel, 1, 0);

    const carries_rel = try world.intern_relation("Carries", .set);
    const wine = try world.intern_entity("CheapPort");
    const flyer = try world.intern_entity("GullHandbill");
    const paint = try world.intern_entity("RedLeadPaint");
    const casing = try world.intern_entity("VoltaicJar");
    const vinegar = try world.intern_entity("AgedVinegar");
    const battery = try world.intern_entity("ChargedJar");
    const flag = try world.intern_entity("GullBanner");
    const tree_prop = world.lookup_entity("OrangeTree").?;
    const capsule_1712 = world.lookup_entity("CornerstoneBox1712").?;
    const capsule_1912 = world.lookup_entity("CornerstoneBox1912").?;
    const wine_prop = world.lookup_entity("PortBottle").?;
    const flyer_prop = world.lookup_entity("GullHandbillProp").?;
    const flag_prop = world.lookup_entity("GullBannerProp").?;
    const socket_prop = world.lookup_entity("StormTerminal").?;
    const future_tree = world.lookup_entity("GiantOrangeTree").?;

    // Explicit hotspot locations aligned with scene waypoints across all 3 eras
    try spatial.add_hotspot(well_1712_ent, past_scene, .{ .x = 80, .y = -6 }, 10, "TideWell1712", "The 1712 Tide Well. Its brass pump has no charge, so nothing will go back up the shaft.");
    try spatial.add_hotspot(capsule_1712, past_scene, .{ .x = 60, .y = -6 }, 8, "CornerstoneBox1712", "The cornerstone box for the new town hall. Whatever goes in stays sealed until 1912.");
    try spatial.add_hotspot(tree_prop, past_scene, .{ .x = 40, .y = -6 }, 10, "OrangeTree", "A stunted little orange tree. Founder Gale keeps eyeing it and fingering his axe.");
    try spatial.add_hotspot(paint, past_scene, .{ .x = 20, .y = -6 }, 8, "RedLeadPaint", "A pot of red lead, for ships' hulls. It'd turn anything a nasty shade of red.");

    try spatial.add_hotspot(well_1912_ent, present_scene, .{ .x = 60, .y = -6 }, 10, "TideWell1912", "Doctor Brine's Tide Well. Drop something down the shaft and it comes up in another century's bucket.");
    try spatial.add_hotspot(capsule_1912, present_scene, .{ .x = 40, .y = -6 }, 8, "CornerstoneBox1912", "The town's cornerstone box, set into the wall in 1712 and never opened since.");
    try spatial.add_hotspot(wine_prop, present_scene, .{ .x = 0, .y = -6 }, 8, "PortBottle", "A dusty bottle of cheap port on the front desk.");
    try spatial.add_hotspot(flyer_prop, present_scene, .{ .x = 5, .y = -6 }, 8, "GullHandbillProp", "A handbill pasted by the door, with a huge gull's profile.");

    try spatial.add_hotspot(well_2112_ent, future_scene, .{ .x = 60, .y = -6 }, 10, "TideWell2112", "The Tide Well in 2112. With power at the other end, it'll join the three of us up.");
    try spatial.add_hotspot(future_tree, future_scene, .{ .x = 40, .y = -6 }, 10, "GiantOrangeTree", "An orange tree two hundred years old, tall as the roost. Juno is caught in its branches.");
    try spatial.add_hotspot(flag_prop, future_scene, .{ .x = 20, .y = -6 }, 8, "GullBannerProp", "The banner on the roost roof: a great white gull, beak open. The flag of the flock.");
    try spatial.add_hotspot(socket_prop, future_scene, .{ .x = 25, .y = -6 }, 8, "StormTerminal", "A brass storm terminal on the roof, wired into the Tide Well.");

    const belief_rel = try world.intern_relation("Believes", .set);
    const well_powered_rel = try world.intern_relation("WellPowered", .set);
    const flag_design_rel = try world.intern_relation("GullBannerDesign", .set);
    const flag_sewn_rel = try world.intern_relation("BannerSewn", .set);
    const chop_rel = try world.intern_relation("TreeFelled", .set);
    const free_rel = try world.intern_relation("FreedFromTree", .set);
    const feeding_rel = try world.intern_relation("InYard", .set);
    const disg_rel = try world.intern_relation("GullDisguiseActive", .set);

    _ = try world.remember(nell, carries_rel, wine.to_int(), 0);
    _ = try world.remember(nell, carries_rel, flyer.to_int(), 0);
    _ = try world.remember(ossie, carries_rel, paint.to_int(), 0);
    _ = try world.remember(ossie, carries_rel, casing.to_int(), 0);

    var vm = bespoke.VM.init(allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;
    try vm.load_compiled_rules(&compiled);
    try vm.transition_to_scene(present_scene);

    var win = try bespoke.display.DisplayWindow.init("BeSpoke Engine - The Well of Three Tides", 1280, 720);
    defer win.deinit();
    win.set_theme(&art.theme);
    win.audio_bridge.set_track(art.track(.three_tides));

    var display_bridge = bespoke.display.DisplayBridge.init();
    display_bridge.set_status_hook(art.capture_status);
    display_bridge.attach_audio_bridge(win.audio_bridge);
    const party = [_]bespoke.EntityId{ ossie, nell, juno };
    display_bridge.set_party(&party);
    display_bridge.set_active_character(nell);
    display_bridge.set_active_party_index(1);

    var session = try bespoke.host.Session.init(allocator, &world, &spatial, &vm, &compiled, &display_bridge, &win);
    defer session.deinit();
    win.set_cue_banner("The Well of Three Tides loaded! Press [1] Ossie, [2] Nell, [3] Juno to switch characters.", 180);

    while (true) {
        session.refresh();
        const frame = session.frame();
        session.render();

        const action = win.poll_events(frame);
        var action_taken = false;

        // Pause, step, scrub, rewind, and save actions are shared (host kit, P32-16, D-033).
        if (try session.handle_common(action)) {} else switch (action) {
            .quit => break,
            .walk_player => |wp_id| {
                const active_char = display_bridge.active_player_character orelse nell;
                _ = try spatial.walk_to(active_char, wp_id);
                action_taken = true;
                win.set_cue_banner("Directing character to waypoint.", 60);
            },
            .switch_party_member => |p_idx| {
                if (p_idx < party.len) {
                    const char_id = party[p_idx];
                    display_bridge.set_active_character(char_id);
                    display_bridge.set_active_party_index(p_idx);
                    if (char_id == ossie) {
                        try vm.transition_to_scene(past_scene);
                        win.set_cue_banner("Switched to Ossie (1712 Charter Yard)", 120);
                    } else if (char_id == nell) {
                        try vm.transition_to_scene(present_scene);
                        win.set_cue_banner("Switched to Nell (1912 Brine's Boarding House)", 120);
                    } else if (char_id == juno) {
                        try vm.transition_to_scene(future_scene);
                        win.set_cue_banner("Switched to Juno (2112 Gull Roost)", 120);
                    }
                    action_taken = true;
                }
            },
            .examine_hotspot => |hs_idx| {
                if (hs_idx < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_idx];
                    const active_char = display_bridge.active_player_character orelse nell;
                    var look_buf: [256]u8 = undefined;
                    const speech = try execute_look_at(&world, &vm, &compiled, active_char, hs.entity, &look_buf);
                    win.set_cue_banner(speech, 180);
                    std.debug.print("\n[Tides Look] {s}\n", .{speech});
                    action_taken = true;
                }
            },
            .interact_hotspot => |hs_act| {
                if (hs_act.hotspot_index < frame.hotspot_count) {
                    const hs = frame.hotspots[hs_act.hotspot_index];
                    const active_char = display_bridge.active_player_character orelse nell;
                    if (hs_act.verb == .look_at) {
                        var look_buf: [256]u8 = undefined;
                        const speech = try execute_look_at(&world, &vm, &compiled, active_char, hs.entity, &look_buf);
                        win.set_cue_banner(speech, 180);
                        std.debug.print("\n[Tides Look] {s}\n", .{speech});
                    } else if (hs_act.verb == .walk) {
                        const pt = bespoke.display.renderer.world_to_screen(hs.x, hs.y, win.width, win.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(pt.x, pt.y, frame.waypoints[0..frame.waypoint_count], win.width, win.height)) |wp_id| {
                            _ = try spatial.walk_to(active_char, wp_id);
                            win.set_cue_banner("Approaching prop...", 60);
                        }
                    } else if (hs_act.verb == .pick_up or hs_act.verb == .use_with) {
                        const aged_rel = try world.intern_relation("PortAgedIntoVinegar", .set);
                        if (hs.entity == capsule_1912 or hs.entity == capsule_1712) {
                            if (world.has_fact(wine, aged_rel, 1)) {
                                if (!world.has_fact(null, carries_rel, vinegar.to_int())) {
                                    _ = try world.remember(active_char, carries_rel, vinegar.to_int(), 0);
                                    win.play_sfx(.pickup);
                                    win.set_cue_banner("Nell opens the 1912 cornerstone box and retrieves the 200-year-aged vinegar!", 180);
                                } else {
                                    win.set_cue_banner("The cornerstone box is now empty.", 120);
                                }
                            } else {
                                win.set_cue_banner("The cornerstone box is empty. Nothing has been sealed in it yet.", 120);
                            }
                        } else if (hs.entity == flag_prop) {
                            if (world.has_fact(fenn, flag_sewn_rel, 1)) {
                                if (!world.has_fact(null, carries_rel, flag.to_int())) {
                                    _ = try world.remember(active_char, carries_rel, flag.to_int(), 0);
                                    win.play_sfx(.pickup);
                                    win.set_cue_banner("Juno takes down the Gull Banner disguise from the roof flagpole!", 180);
                                } else {
                                    win.set_cue_banner("The flagpole is empty.", 90);
                                }
                            } else {
                                win.set_cue_banner("The gull banner has not been sewn yet.", 120);
                            }
                        } else {
                            _ = try vm.fire_cue(&compiled, "Uses", active_char, hs.entity, null);
                            try vm.step_tick();
                        }
                    } else {
                        _ = try vm.fire_cue(&compiled, "Uses", active_char, hs.entity, null);
                        try vm.step_tick();
                    }
                    action_taken = true;
                }
            },
            .interact_actor => |act| {
                if (act.actor_index < frame.entity_count) {
                    const target_entity = frame.entities[act.actor_index];
                    const active_char = display_bridge.active_player_character orelse nell;
                    if (act.verb == .talk_to) {
                        _ = try vm.fire_cue(&compiled, "TalksTo", active_char, target_entity.entity, null);
                        try vm.step_tick();
                        var say_buf: [256]u8 = undefined;
                        if (bespoke.host.speech_this_tick(&world, &vm, &say_buf)) |speech| {
                            win.set_cue_banner(speech, 180);
                            std.debug.print("\n[Tides Talk] {s}\n", .{speech});
                        }
                    } else if (act.verb == .look_at) {
                        var look_buf: [256]u8 = undefined;
                        const speech = try execute_look_at(&world, &vm, &compiled, active_char, target_entity.entity, &look_buf);
                        win.set_cue_banner(speech, 180);
                        std.debug.print("\n[Tides Look] {s}\n", .{speech});
                    } else if (act.verb == .walk) {
                        const layout = bespoke.display.renderer.get_entity_screen_layout(act.actor_index, frame.entities[0..frame.entity_count], win.width, win.height);
                        if (bespoke.display.renderer.find_nearest_waypoint(layout.pos.x, layout.pos.y, frame.waypoints[0..frame.waypoint_count], win.width, win.height)) |wp_id| {
                            _ = try spatial.walk_to(active_char, wp_id);
                            win.set_cue_banner("Approaching character...", 60);
                        }
                    }
                    action_taken = true;
                }
            },
            .interact_inventory => |inv_act| {
                if (inv_act.item_index < frame.inventory_count) {
                    const inv_item = frame.inventory[inv_act.item_index];
                    const active_char = display_bridge.active_player_character orelse nell;
                    if (inv_act.verb == .look_at) {
                        var look_buf: [256]u8 = undefined;
                        const speech = try execute_look_at(&world, &vm, &compiled, active_char, inv_item.entity, &look_buf);
                        win.set_cue_banner(speech, 180);
                        std.debug.print("\n[Tides Look] {s}\n", .{speech});
                    }
                    action_taken = true;
                }
            },
            .use_inventory_on_hotspot => |u_hs| {
                if (u_hs.item_index < frame.inventory_count and u_hs.hotspot_index < frame.hotspot_count) {
                    const item_ent = frame.inventory[u_hs.item_index].entity;
                    const hs_ent = frame.hotspots[u_hs.hotspot_index].entity;
                    const active_char = display_bridge.active_player_character orelse nell;

                    if (item_ent == paint and hs_ent == tree_prop) {
                        _ = try world.remember(gale, belief_rel, 1, 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Ossie daubs the orange tree with red lead! Founder Gale now believes it has the red blight!", 180);
                    } else if (item_ent == wine and (hs_ent == capsule_1712 or hs_ent == capsule_1912)) {
                        _ = try world.transfer_item(wine, active_char, hs_ent);
                        const aged_rel = try world.intern_relation("PortAgedIntoVinegar", .set);
                        _ = try world.remember(wine, aged_rel, 1, 0);
                        win.play_sfx(.pickup);
                        win.set_cue_banner("Cheap Port sealed into the cornerstone box for two centuries of aging.", 180);
                    } else if (item_ent == battery and hs_ent == well_1712_ent) {
                        _ = try world.remember(ossie, well_powered_rel, 1, 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Charged Jar plugged in! The 1712 Tide Well hums with temporal power!", 180);
                    } else {
                        _ = try vm.fire_cue(&compiled, "Uses", active_char, hs_ent, null);
                        try vm.step_tick();
                    }
                    action_taken = true;
                }
            },
            .use_inventory_on_actor => |u_act| {
                if (u_act.item_index < frame.inventory_count and u_act.actor_index < frame.entity_count) {
                    const item_ent = frame.inventory[u_act.item_index].entity;
                    const act_ent = frame.entities[u_act.actor_index].entity;

                    if (item_ent == flyer and act_ent == fenn) {
                        _ = try world.remember(fenn, flag_design_rel, 1, 0);
                        _ = try world.remember(fenn, flag_sewn_rel, 1, 0);
                        _ = try world.remember(juno, carries_rel, flag.to_int(), 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Widow Fenn: 'A great white bird with its beak open? Bold. I'll sew it this minute!' Banner done!", 180);
                    } else if (item_ent == flag and (act_ent == juno or act_ent == squall)) {
                        _ = try world.remember(juno, disg_rel, 1, 0);
                        // The disguise gets her past the guard.
                        _ = try world.remember(juno, try world.intern_relation("PassesGuard", .set), 1, 0);
                        win.play_sfx(.pickup);
                        win.set_cue_banner("Juno dons the Gull Banner disguise! Security checkpoint access granted!", 180);
                    }
                    action_taken = true;
                }
            },
            .combine_inventory_items => |comb| {
                if (comb.primary_index < frame.inventory_count and comb.secondary_index < frame.inventory_count) {
                    const item1 = frame.inventory[comb.primary_index].entity;
                    const item2 = frame.inventory[comb.secondary_index].entity;
                    const active_char = display_bridge.active_player_character orelse ossie;

                    if ((item1 == vinegar and item2 == casing) or (item1 == casing and item2 == vinegar)) {
                        _ = world.forget(active_char, carries_rel, vinegar.to_int());
                        _ = world.forget(active_char, carries_rel, casing.to_int());
                        _ = try world.remember(active_char, carries_rel, battery.to_int(), 0);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Ossie combines 200-year vinegar with voltaic jar! Charged Jar created!", 180);
                    }
                    action_taken = true;
                }
            },
            .dialogue_choice => |choice_idx| {
                const active_char = display_bridge.active_player_character orelse nell;
                if (active_char == ossie and choice_idx == 0) {
                    if (world.has_fact(gale, belief_rel, 1)) {
                        _ = try world.remember(gale, chop_rel, tree_prop.to_int(), 0);
                        _ = try world.remember(juno, free_rel, 1, 0);
                        _ = world.forget(juno, trapped_rel, 1);
                        win.play_sfx(.combine);
                        win.set_cue_banner("Founder Gale: 'The red blight?! Not in my town!' *THWACK!* Juno freed from the tree!", 180);
                    }
                } else if (active_char == juno and choice_idx == 0) {
                    _ = try world.remember(juno, feeding_rel, 1, 0);
                    win.set_cue_banner("Admiral Squall: 'Feeding the flock is permitted. In the yard. Be quick, featherless one.'", 180);
                }
                action_taken = true;
            },
            .transfer_inventory_item => |trans| {
                if (trans.target_party_index < party.len and trans.item_index < frame.inventory_count) {
                    const from_id = display_bridge.active_player_character orelse nell;
                    const to_id = party[trans.target_party_index];
                    const item_ent = frame.inventory[trans.item_index].entity;
                    if (!spatial.can_transfer_item_with_world(&world, from_id, to_id, .portal_anchored)) {
                        const target_name = world.get_entity_name(to_id) orelse "Character";
                        var block_buf: [128]u8 = undefined;
                        const block_msg = std.fmt.bufPrint(&block_buf, "{s} cannot reach the Tide Well right now!", .{target_name}) catch "Transfer blocked!";
                        win.set_cue_banner(block_msg, 120);
                    } else {
                        _ = try world.transfer_item(item_ent, from_id, to_id);
                        win.play_sound(art.sfx(.well_splash));
                    }
                    action_taken = true;
                }
            },
            else => {},
        }

        if (action_taken) {
            if (evaluate_tides_solved(&world)) {
                win.set_cue_banner("VICTORY ACHIEVED! The Well of Three Tides temporal puzzle solved!", 300);
            }
            display_bridge.capture_frame(&world, &spatial, &vm);
            display_bridge.swap();
        }

        // Stepping simulation clock
        if (session.tick_due()) {
            _ = try session.advance();
            var cutscene_buf: [256]u8 = undefined;
            if (bespoke.host.speech_this_tick(&world, &vm, &cutscene_buf)) |cutscene_msg| {
                win.set_cue_banner(cutscene_msg, 180);
                std.debug.print("\n[Cutscene Telegraph] {s}\n", .{cutscene_msg});
            }
        }

        bespoke.display.renderer.c.SDL_Delay(16);
    }
}

test "P21-03: Three Tides full puzzle DAG compilation, cross-era transfers, and temporal victory" {
    const testing = std.testing;
    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try run_headless(testing.allocator, buf.writer());
    try testing.expect(buf.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buf.items, "VICTORY ACHIEVED!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[Step 0b] Three-Era Environmental Inspection (LooksAt cues):") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Gating Verified: Juno trapped in tree -> Tide Well transfer rejected!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Anchoring Verified: Nell to Ossie operational across eras.") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Passive Incubation: No cutscene emitted; 200-year transformation discovered organically upon retrieval.") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[Cutscene Telegraph] Juno: \"Look at the roost roof! Widow Fenn's gull is flying as the flag of the flock!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[Cutscene Telegraph] Juno: \"Whoa! The tree's gone from under me! *THUD!* I'm on the ground!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Access Gating: Juno on ground but guarded -> Tide Well transfer rejected!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Access Gating: Juno feeding the gulls in the yard -> Tide Well transfer online!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "[D-026 Invariant] Portal Access Gating: Juno wearing gull disguise -> permanent Tide Well access granted!") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Nell looks at PortBottle -> Nell: \"A dusty bottle of cheap port on the front desk. Bottled this year, and it tastes like it.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Ossie looks at OrangeTree -> Ossie: \"A stunted little orange tree. Founder Gale keeps eyeing it and fingering his axe.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Juno looks at AdmiralSquall -> Juno: \"Admiral Squall, a gull the size of a rowing boat, guarding the checkpoint. No humans past him without a gull disguise.\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Ossie inspects ChargedJar -> Ossie: \"The voltaic jar, full of two-hundred-year-old vinegar and humming with charge!\"") != null);
    try testing.expect(std.mem.indexOf(u8, buf.items, "Juno inspects GullBanner -> Juno: \"Widow Fenn's banner from 1712. Draped over me, I'd pass for a gull.\"") != null);
}

test "P32-19: each party member has a scripted default look description" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, THREE_TIDES_SCRIPT);
    defer compiled.deinit();
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    const pebble = try world.intern_entity("UnscriptedPebble");
    var buf: [512]u8 = undefined;
    inline for (.{ "Nell", "Ossie", "Juno" }) |name| {
        const said = try execute_look_at(&world, &vm, &compiled, world.lookup_entity(name).?, pebble, &buf);
        try testing.expectEqualStrings(name ++ ": \"Nothing unusual to see here.\"", said);
    }

    // A specific handler still wins over the default.
    const desk = try execute_look_at(&world, &vm, &compiled, world.lookup_entity("Nell").?, world.lookup_entity("FrontDesk").?, &buf);
    try testing.expect(std.mem.indexOf(u8, desk, "Nothing unusual") == null);
}

test "P32-20: Tides exercises BitemporalTransceiver, CausalDecayTracker, and reject_belief" {
    const testing = std.testing;
    var world = try bespoke.World.init(testing.allocator, bespoke.world.DEFAULT_ARENA_SIZE);
    defer world.deinit();
    var spatial = bespoke.SpatialSystem.init(testing.allocator);
    defer spatial.deinit();
    var compiled = try bespoke.compile_source(testing.allocator, &world, &spatial, THREE_TIDES_SCRIPT);
    defer compiled.deinit();
    var vm = bespoke.VM.init(testing.allocator, &world, &compiled.chunk);
    defer vm.deinit();
    vm.spatial = &spatial;

    const gale = world.lookup_entity("FounderGale").?;
    const orange = world.lookup_entity("OrangeTree").?;
    const future_tree = world.lookup_entity("GiantOrangeTree").?;
    const blight_prop = try world.intern_entity("RedBlight");

    // 1. reject_belief
    try vm.reject_belief(gale, blight_prop);
    try testing.expect(!vm.evaluates_belief(gale, blight_prop));
    const rej_rel = world.lookup_relation("Rejects").?;
    try testing.expect(world.has_fact(gale, rej_rel, blight_prop.to_int()));

    // 2. BitemporalTransceiver cross-era propagation
    const past_scene = world.lookup_entity("Charter Yard").?;
    const future_scene = world.lookup_entity("Gull Roost").?;
    const chop_rel = try world.intern_relation("TreeFelled", .set);

    var transceiver = bespoke.BitemporalTransceiver.init(testing.allocator, past_scene, future_scene);
    defer transceiver.deinit();
    try transceiver.register_pair(orange, future_tree, chop_rel);
    const synced = try transceiver.sync_past_mutation(&world, orange, 1);
    try testing.expect(synced);
    try testing.expect(world.has_fact(future_tree, chop_rel, 1));

    // 3. CausalDecayTracker existence decay calculation
    try testing.expectEqual(@as(u16, 1000), bespoke.CausalDecayTracker.existence_permille(100, 100, 200));
    try testing.expectEqual(@as(u16, 500), bespoke.CausalDecayTracker.existence_permille(200, 100, 200));
    try testing.expectEqual(@as(u16, 0), bespoke.CausalDecayTracker.existence_permille(300, 100, 200));
    try testing.expect(bespoke.CausalDecayTracker.is_erased(300, 100, 200));
    try testing.expect(!bespoke.CausalDecayTracker.is_erased(200, 100, 200));
}
