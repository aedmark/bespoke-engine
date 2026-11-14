//! Presentation for the proofs of concept: backdrops, prop art, actor tokens, walkway styles,
//! and footer hints (P32-02b, D-039).
//!
//! This drawing code lived inside the engine's `render_frame` until P32-02b. It is proof
//! content, so it lives here and reaches the window only through the engine's `Theme` hook:
//! each proof calls `window.set_theme(&art.theme)`. The engine knows none of these scenes,
//! props, or characters.
//!
//! One theme serves all nine proofs because the art was written as one chain that picks a
//! scene by name and a prop or token by its name. Splitting it per proof is possible and not
//! required by the boundary. `proofs/golden/render.txt` pins every scene's pixels.
const std = @import("std");
const bespoke = @import("bespoke");
const music = @import("music.zig");
const r = bespoke.display.renderer;

const DisplayWindow = r.DisplayWindow;
const RenderFrame = bespoke.RenderFrame;
const ACTOR_SCREEN_RADIUS = r.ACTOR_SCREEN_RADIUS;
const Color = r.Color;
const TextLabel = r.TextLabel;
const world_to_screen = r.world_to_screen;
const Point = r.Point;
const to_layout = r.to_layout;
const LabelPriority = r.LabelPriority;

/// Colours of the proof scenes, props, and characters.
const Palette = struct {
    const cheese_color = Color{ .r = 250, .g = 204, .b = 21 }; // Gold
    const tavern_bg = Color{ .r = 22, .g = 18, .b = 16 };
    const tavern_room = Color{ .r = 38, .g = 28, .b = 24 };
    const cellar_room = Color{ .r = 24, .g = 30, .b = 41 };
    const cellar_border = Color{ .r = 45, .g = 55, .b = 72 };
    const cat_color = Color{ .r = 234, .g = 88, .b = 12 }; // Orange
    const guard_color = Color{ .r = 37, .g = 99, .b = 235 }; // Steel Blue
    const bard_color = Color{ .r = 147, .g = 51, .b = 234 }; // Purple
    // Booty Island Spitting Contest Colors (P10-03, D-012)
    const guybrush_coat = Color{ .r = 30, .g = 64, .b = 175 }; // Pirate Blue
    const guybrush_hair = Color{ .r = 250, .g = 204, .b = 21 }; // Blonde
    // Brackwater Barbs player (P35-02)
    const tamsin_coat = Color{ .r = 15, .g = 118, .b = 110 }; // Sea green
    const tamsin_hair = Color{ .r = 41, .g = 37, .b = 36 }; // Dark brown
    const organiser_coat = Color{ .r = 185, .g = 28, .b = 28 }; // Velvet Red
    const onlookers_color = Color{ .r = 120, .g = 80, .b = 140 }; // Purple Crowd
    const flag_color = Color{ .r = 239, .g = 68, .b = 68 }; // Red flag
    const flag_tampered = Color{ .r = 245, .g = 158, .b = 11 }; // Gold flag
    const wind_color = Color{ .r = 56, .g = 189, .b = 248 }; // Sky Blue
    const spit_color = Color{ .r = 34, .g = 197, .b = 94 }; // Lime Spit
    const grass_green = Color{ .r = 30, .g = 68, .b = 38 };
    const sand_color = Color{ .r = 180, .g = 160, .b = 110 };
    const ocean_blue = Color{ .r = 14, .g = 70, .b = 110 };
    const sky_dusk = Color{ .r = 16, .g = 24, .b = 48 };
    // Gabriel Knight 3 Scenario Colors (P14-02, D-016)
    const gabriel_coat = Color{ .r = 180, .g = 115, .b = 50 }; // Tan leather trench coat
    const gabriel_hair = Color{ .r = 245, .g = 215, .b = 110 }; // Signature blonde hair
    const mosely_suit = Color{ .r = 40, .g = 50, .b = 85 }; // Detective navy suit
    const buthane_vest = Color{ .r = 190, .g = 45, .b = 60 }; // Crimson shopkeeper vest
    const buthane_hair = Color{ .r = 180, .g = 70, .b = 30 }; // Auburn hair
    const stray_cat_color = Color{ .r = 25, .g = 25, .b = 30 }; // Black stray cat
    const cat_eye_color = Color{ .r = 50, .g = 220, .b = 90 }; // Piercing green eyes
    const hotel_wallpaper = Color{ .r = 95, .g = 25, .b = 32 }; // Burgundy damask
    const hotel_wainscot = Color{ .r = 45, .g = 22, .b = 15 }; // Dark polished mahogany
    const hotel_door = Color{ .r = 65, .g = 35, .b = 20 }; // French room door
    const garden_sky = Color{ .r = 140, .g = 185, .b = 225 }; // Southern French sky
    const garden_grass = Color{ .r = 55, .g = 115, .b = 50 }; // Courtyard greenery
    const garden_fence = Color{ .r = 150, .g = 95, .b = 50 }; // Wooden picket fence
    const rental_wall = Color{ .r = 75, .g = 65, .b = 55 }; // French stone plaster
    const rental_counter = Color{ .r = 160, .g = 100, .b = 45 }; // Pine shop counter
    const motorcycle_red = Color{ .r = 220, .g = 38, .b = 38 }; // Shiny red motorcycle
    // Broken Sword Lochmarne Goat Scenario Colors (P20-02, D-023)
    const george_jacket = Color{ .r = 115, .g = 65, .b = 35 }; // Brown leather jacket
    const george_hair = Color{ .r = 238, .g = 205, .b = 95 }; // Blonde hair parted in middle
    const goat_body = Color{ .r = 235, .g = 232, .b = 220 }; // Off-white Irish goat fleece
    const goat_horns = Color{ .r = 55, .g = 48, .b = 40 }; // Dark ridged horns
    const goat_collar = Color{ .r = 180, .g = 40, .b = 40 }; // Red collar
    const lochmarne_sky = Color{ .r = 120, .g = 145, .b = 170 }; // Overcast Irish sky
    const lochmarne_grass = Color{ .r = 45, .g = 115, .b = 52 }; // Rich emerald Irish turf
    const lochmarne_ruins = Color{ .r = 95, .g = 90, .b = 85 }; // Weathered castle stone
    const crypt_wall = Color{ .r = 35, .g = 32, .b = 30 }; // Ancient subterranean crypt stone
    const templar_red = Color{ .r = 195, .g = 30, .b = 30 }; // Vivid Templar cross red
    const rope_color = Color{ .r = 205, .g = 175, .b = 125 }; // Hemp tether rope
    // Day of the Tentacle Colors (P21-03, D-025)
    const tentacle_purple = Color{ .r = 138, .g = 43, .b = 226 };
    const tentacle_sucker = Color{ .r = 250, .g = 204, .b = 21 };
    const hoagie_cap = Color{ .r = 220, .g = 38, .b = 38 };
    const bernard_shirt = Color{ .r = 59, .g = 130, .b = 246 };
    const laverne_hair = Color{ .r = 253, .g = 224, .b = 71 };
    const laverne_dress = Color{ .r = 6, .g = 182, .b = 212 };
    const washington_coat = Color{ .r = 30, .g = 58, .b = 138 };
    const betsy_dress = Color{ .r = 159, .g = 18, .b = 57 };
    const colonial_wood = Color{ .r = 92, .g = 64, .b = 51 };
    const colonial_hearth = Color{ .r = 160, .g = 82, .b = 45 };
    const motel_teal = Color{ .r = 13, .g = 148, .b = 136 };
    const dystopia_metal = Color{ .r = 30, .g = 35, .b = 45 };
    // Donnie Darko / Roberta Sparrow Cinematic Colors (P31-01..P31-03, D-027)
    const tangent_glow = Color{ .r = 56, .g = 189, .b = 248, .a = 180 }; // Translucent water-like fluid blue
    const tangent_core = Color{ .r = 224, .g = 242, .b = 254, .a = 230 }; // Bright white-blue conduit core
    const frank_silver = Color{ .r = 148, .g = 163, .b = 184 }; // Monstrous silver rabbit
};


/// The Castle Fire Escape gallery grid (`proofs/grid_puzzle.zig`): one row of cells. The proof's
/// layout test fails if its script declares a different grid.
pub const GALLERY_CELLS: u16 = 6;
pub const GALLERY_CELL_SIZE: u32 = 8;

pub const theme = r.Theme{
    .backdrop = backdrop,
    .prop = prop,
    .actor = actor,
    .walkway = walkway,
    .shows_walkways = shows_walkways,
    .footer = footer,
    .soundtrack = &soundtrack,
    .hud = hud,
    .overlay = overlay,
    .thumbnails = &thumbnails,
};

/// The shared theme with one proof's key bindings added (P32-02c). Call at container level so
/// the result is a constant the window can borrow.
pub fn with_keys(comptime keys: []const r.KeyBinding) r.Theme {
    var t = theme;
    t.keys = keys;
    return t;
}

/// Which proof scene a frame shows, chosen by scene name and, when a host sets none, by the
/// marks and cast present.
const Scene = struct {

    is_bell_base_scene: bool = false,
    is_gallery_scene: bool = false,
    is_observatory_scene: bool = false,
    is_bell_belfry_scene: bool = false,
    is_bike_rental_scene: bool = false,
    is_darko_bedroom_scene: bool = false,
    is_darko_school_scene: bool = false,
    is_darko_vortex_scene: bool = false,
    is_dott_future_scene: bool = false,
    is_dott_past_scene: bool = false,
    is_dott_present_scene: bool = false,
    is_garden_scene: bool = false,
    is_goat_courtyard_scene: bool = false,
    is_tidewalk_scene: bool = false,
    is_hotel_scene: bool = false,
    is_fencing_yard_scene: bool = false,
    is_lantern_scene: bool = false,
    is_spitting_scene: bool = false,
    is_tavern_scene: bool = false,
    is_templar_crypt_scene: bool = false,
    is_village_scene: bool = false,
    is_wine_cellar_scene: bool = false,
};

fn detect(frame: *const RenderFrame) Scene {
    var sc = Scene{};
    // Detect active scene theme (P12-03, P14-02, P20-02, P21-03, D-014, D-016, D-023, D-025)
    const cur_scene = frame.get_current_scene();

    if (cur_scene.len > 0) {
        // Checked first: "Bell Tower" scenes must not fall through to substring themes below.
        if (std.mem.indexOf(u8, cur_scene, "Hollin Keep") != null) {
            sc.is_gallery_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Larkspur") != null) {
            sc.is_observatory_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Bell Tower") != null) {
            if (std.mem.indexOf(u8, cur_scene, "Belfry") != null) {
                sc.is_bell_belfry_scene = true;
            } else {
                sc.is_bell_base_scene = true;
            }
        } else if (std.mem.indexOf(u8, cur_scene, "Colonial") != null or
            std.mem.indexOf(u8, cur_scene, "Workshop") != null or
            std.mem.indexOf(u8, cur_scene, "1790") != null)
        {
            sc.is_dott_past_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Motel") != null or
            std.mem.indexOf(u8, cur_scene, "Lobby") != null or
            std.mem.indexOf(u8, cur_scene, "1993") != null)
        {
            sc.is_dott_present_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Dystopian") != null or
            std.mem.indexOf(u8, cur_scene, "Guard Post") != null or
            std.mem.indexOf(u8, cur_scene, "2193") != null)
        {
            sc.is_dott_future_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Bedroom") != null or
                   std.mem.indexOf(u8, cur_scene, "Darko") != null or
                   std.mem.indexOf(u8, cur_scene, "Donnie") != null)
        {
            sc.is_darko_bedroom_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "School") != null or
                   std.mem.indexOf(u8, cur_scene, "High School") != null or
                   std.mem.indexOf(u8, cur_scene, "Middlesex High") != null)
        {
            sc.is_darko_school_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Vortex") != null or
                   std.mem.indexOf(u8, cur_scene, "Ridge") != null or
                   std.mem.indexOf(u8, cur_scene, "Tangent") != null)
        {
            sc.is_darko_vortex_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Lochmarne") != null or
            (std.mem.indexOf(u8, cur_scene, "Courtyard") != null and std.mem.indexOf(u8, cur_scene, "Castle") != null))
        {
            sc.is_goat_courtyard_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Crypt") != null or
                   std.mem.indexOf(u8, cur_scene, "Templar") != null)
        {
            sc.is_templar_crypt_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Village") != null or
            std.mem.indexOf(u8, cur_scene, "Living") != null)
        {
            sc.is_village_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Tidewalk") != null) {
            sc.is_tidewalk_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Fencing Yard") != null) {
            sc.is_fencing_yard_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Drowned Lantern") != null) {
            sc.is_lantern_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Spit") != null or
            std.mem.indexOf(u8, cur_scene, "Booty") != null)
        {
            sc.is_spitting_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Cellar") != null) {
            sc.is_wine_cellar_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Tavern") != null or
                   std.mem.indexOf(u8, cur_scene, "Common") != null)
        {
            sc.is_tavern_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Garden") != null or
                   std.mem.indexOf(u8, cur_scene, "Courtyard") != null)
        {
            sc.is_garden_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Corridor") != null or
                   std.mem.eql(u8, cur_scene, "Hotel Corridor"))
        {
            sc.is_hotel_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Bike") != null or
                   std.mem.indexOf(u8, cur_scene, "Rental") != null or
                   std.mem.indexOf(u8, cur_scene, "Shop") != null)
        {
            sc.is_bike_rental_scene = true;
        } else if (std.mem.indexOf(u8, cur_scene, "Hotel") != null) {
            sc.is_hotel_scene = true;
        }
    }

    // Fallback detection if current_scene wasn't explicitly set
    if (!sc.is_bell_base_scene and !sc.is_bell_belfry_scene and !sc.is_gallery_scene and !sc.is_observatory_scene and
        !sc.is_dott_past_scene and !sc.is_dott_present_scene and !sc.is_dott_future_scene and
        !sc.is_goat_courtyard_scene and !sc.is_templar_crypt_scene and
        !sc.is_spitting_scene and !sc.is_wine_cellar_scene and !sc.is_tavern_scene and
        !sc.is_hotel_scene and !sc.is_garden_scene and !sc.is_bike_rental_scene and
        !sc.is_tidewalk_scene and !sc.is_fencing_yard_scene and !sc.is_lantern_scene and !sc.is_village_scene and
        !sc.is_darko_bedroom_scene and !sc.is_darko_school_scene and !sc.is_darko_vortex_scene)
    {
        for (frame.waypoints[0..frame.waypoint_count]) |wp| {
            if (std.mem.indexOf(u8, wp.get_name(), "ToiletMark1790") != null or
                std.mem.indexOf(u8, wp.get_name(), "KumquatLawn") != null)
            {
                sc.is_dott_past_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "ToiletMark1993") != null or
                std.mem.indexOf(u8, wp.get_name(), "LobbyDesk") != null)
            {
                sc.is_dott_present_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "ToiletMark2193") != null or
                std.mem.indexOf(u8, wp.get_name(), "GuardPost") != null or
                std.mem.indexOf(u8, wp.get_name(), "TreeBranch2193") != null)
            {
                sc.is_dott_future_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "BedMark") != null or
                std.mem.indexOf(u8, wp.get_name(), "Bedroom") != null)
            {
                sc.is_darko_bedroom_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "LockersMark") != null or
                std.mem.indexOf(u8, wp.get_name(), "Hallway") != null)
            {
                sc.is_darko_school_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "RidgeMark") != null or
                std.mem.indexOf(u8, wp.get_name(), "VortexMark") != null)
            {
                sc.is_darko_vortex_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "TetherCenter") != null or
                std.mem.indexOf(u8, wp.get_name(), "DigOpening") != null or
                std.mem.indexOf(u8, wp.get_name(), "CourtyardEntrance") != null or
                std.mem.indexOf(u8, wp.get_name(), "PloughMark") != null)
            {
                sc.is_goat_courtyard_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "CryptLadder") != null or
                       std.mem.indexOf(u8, wp.get_name(), "AltarMark") != null)
            {
                sc.is_templar_crypt_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "TownSquare") != null or
                std.mem.indexOf(u8, wp.get_name(), "SheriffsPost") != null or
                std.mem.indexOf(u8, wp.get_name(), "Bakery") != null)
            {
                sc.is_village_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "Tidewalk") != null) {
                sc.is_tidewalk_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "YardGate") != null or
                std.mem.indexOf(u8, wp.get_name(), "YardCircle") != null)
            {
                sc.is_fencing_yard_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "LanternDoor") != null) {
                sc.is_lantern_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "Starting Line") != null or
                std.mem.indexOf(u8, wp.get_name(), "Offstage") != null)
            {
                sc.is_spitting_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "Fence") != null or
                       std.mem.indexOf(u8, wp.get_name(), "CatLounge") != null or
                       std.mem.indexOf(u8, wp.get_name(), "Garden") != null)
            {
                sc.is_garden_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "Room25") != null or
                       std.mem.indexOf(u8, wp.get_name(), "Room33") != null or
                       std.mem.indexOf(u8, wp.get_name(), "Corridor") != null)
            {
                sc.is_hotel_scene = true;
                break;
            } else if (std.mem.indexOf(u8, wp.get_name(), "Counter") != null or
                       std.mem.indexOf(u8, wp.get_name(), "BikeMark") != null or
                       std.mem.indexOf(u8, wp.get_name(), "ShopEntrance") != null)
            {
                sc.is_bike_rental_scene = true;
                break;
            }
        }
        if (!sc.is_dott_past_scene and !sc.is_dott_present_scene and !sc.is_dott_future_scene and
            !sc.is_goat_courtyard_scene and !sc.is_templar_crypt_scene and
            !sc.is_spitting_scene and !sc.is_hotel_scene and !sc.is_garden_scene and !sc.is_bike_rental_scene and
            !sc.is_tidewalk_scene and !sc.is_fencing_yard_scene and !sc.is_lantern_scene and
            !sc.is_darko_bedroom_scene and !sc.is_darko_school_scene and !sc.is_darko_vortex_scene)
        {
            for (frame.entities[0..frame.entity_count]) |e| {
                const ename = e.get_name();
                if (std.mem.eql(u8, ename, "Donnie") or std.mem.eql(u8, ename, "Frank")) {
                    sc.is_darko_bedroom_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Gretchen")) {
                    sc.is_darko_school_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "RobertaSparrow")) {
                    sc.is_darko_vortex_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Hoagie") or std.mem.eql(u8, ename, "BetsyRoss") or std.mem.eql(u8, ename, "Washington")) {
                    sc.is_dott_past_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Bernard") or std.mem.eql(u8, ename, "DrFred")) {
                    sc.is_dott_present_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Laverne") or std.mem.eql(u8, ename, "PurpleTentacle")) {
                    sc.is_dott_future_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "BillyGoat") or
                    (std.mem.eql(u8, ename, "George") and !sc.is_hotel_scene))
                {
                    sc.is_goat_courtyard_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "BosunPike") or std.mem.eql(u8, ename, "OldGannet") or
                    std.mem.eql(u8, ename, "DoryQuill"))
                {
                    sc.is_tidewalk_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Vell")) {
                    sc.is_fencing_yard_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Barkeep") or std.mem.eql(u8, ename, "Citizen")) {
                    sc.is_lantern_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Organiser") or
                           std.mem.eql(u8, ename, "Onlookers"))
                {
                    sc.is_spitting_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "StrayCat")) {
                    sc.is_garden_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Buthane")) {
                    sc.is_bike_rental_scene = true;
                    break;
                } else if (std.mem.eql(u8, ename, "Gabriel") or std.mem.eql(u8, ename, "Mosely")) {
                    sc.is_hotel_scene = true;
                    break;
                }
            }
        }
        if (!sc.is_goat_courtyard_scene and !sc.is_templar_crypt_scene and
            !sc.is_spitting_scene and !sc.is_hotel_scene and !sc.is_garden_scene and !sc.is_bike_rental_scene)
        {
            for (frame.hotspots[0..frame.hotspot_count]) |hs| {
                if (std.mem.indexOf(u8, hs.get_name(), "Plough") != null or
                    std.mem.indexOf(u8, hs.get_name(), "Tether") != null)
                {
                    sc.is_goat_courtyard_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, hs.get_name(), "Mural") != null or
                           std.mem.indexOf(u8, hs.get_name(), "Crypt") != null or
                           std.mem.indexOf(u8, hs.get_name(), "Altar") != null)
                {
                    sc.is_templar_crypt_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, hs.get_name(), "Flag") != null) {
                    sc.is_spitting_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, hs.get_name(), "Fence") != null or
                           std.mem.indexOf(u8, hs.get_name(), "Shrub") != null)
                {
                    sc.is_garden_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, hs.get_name(), "Motorcycle") != null or
                           std.mem.indexOf(u8, hs.get_name(), "Rental") != null)
                {
                    sc.is_bike_rental_scene = true;
                    break;
                } else if (std.mem.indexOf(u8, hs.get_name(), "Door") != null or
                           std.mem.indexOf(u8, hs.get_name(), "Desk") != null)
                {
                    sc.is_hotel_scene = true;
                    break;
                }
            }
        }
    }

    return sc;
}

fn backdrop(w: *DisplayWindow, frame: *const RenderFrame) bool {
    const sc = detect(frame);
    if (sc.is_gallery_scene) {
        render_gallery(w, frame);
    } else if (sc.is_observatory_scene) {
        render_observatory(w);
    } else if (sc.is_bell_base_scene or sc.is_bell_belfry_scene) {
        render_bell_tower(w, frame, sc.is_bell_belfry_scene);
    } else if (sc.is_spitting_scene) {
        // Sky
        w.fill_rect(0, 0, w.width, w.height, Palette.sky_dusk);

        // Grassy Contest Field & Ocean
        const field_x: i32 = 40;
        const field_y: i32 = 110;
        const field_w: i32 = w.width - 80;
        const field_h: i32 = 320;

        // Green grass field
        w.fill_rect(field_x, field_y, field_w - 180, field_h, Palette.grass_green);
        w.draw_rect_outline(field_x, field_y, field_w - 180, field_h, Color{ .r = 45, .g = 95, .b = 55 });

        // Caribbean Ocean / Looking Offstage
        const ocean_x = field_x + field_w - 180;
        w.fill_rect(ocean_x, field_y, 180, field_h, Palette.ocean_blue);
        w.draw_rect_outline(ocean_x, field_y, 180, field_h, Color{ .r = 56, .g = 189, .b = 248 });
        // Sandy shoreline edge
        w.fill_rect(ocean_x - 12, field_y, 12, field_h, Palette.sand_color);

        // Ocean label
        w.draw_text("CARIBBEAN SEA", ocean_x + 16, field_y + 16, 2, Color{ .r = 56, .g = 189, .b = 248 });
        w.draw_text("(LOOKING OFFSTAGE)", ocean_x + 16, field_y + 36, 1, Color.white);

        // Field Title Header
        w.draw_text("BOOTY ISLAND - SPITTING COMPETITION", field_x + 16, field_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });

        // Ground distance track lines
        // Starting Line at x=200 (world_x = 0)
        w.draw_line(200, field_y + 60, 200, field_y + field_h - 20, Color.white);
        w.draw_text("START LINE", 165, field_y + field_h - 16, 1, Color.white);

        // 3rd Place Line at x=340 (world_x = 10)
        w.draw_line(340, field_y + 70, 340, field_y + field_h - 30, Color.hud_subtext);
        w.draw_text("3RD PLACE", 315, field_y + field_h - 26, 1, Color.hud_subtext);

        // 2nd Place Line at x=508 (world_x = 22, where Flags stand)
        w.draw_line(508, field_y + 70, 508, field_y + field_h - 30, Color{ .r = 245, .g = 158, .b = 11 });
        w.draw_text("2ND PLACE", 483, field_y + field_h - 26, 1, Color{ .r = 245, .g = 158, .b = 11 });

        // 1st Place Champion Line at x=676 (world_x = 34)
        w.draw_line(676, field_y + 60, 676, field_y + field_h - 20, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_text("CHAMPION LINE (1ST PLACE)", 600, field_y + field_h - 16, 1, Color{ .r = 250, .g = 204, .b = 21 });

        // Wind Indicator
        if (status_of(frame).wind_blowing) {
            w.draw_text(">>> WIND GUST: STRONG TAILWIND (BLOWING EAST TOWARD TARGET!) >>>", field_x + 16, field_y + 44, 2, Palette.wind_color);
            w.draw_line(260, field_y + 140, 680, field_y + 140, Palette.wind_color);
            w.draw_line(280, field_y + 190, 710, field_y + 190, Palette.wind_color);
            w.draw_line(250, field_y + 240, 690, field_y + 240, Palette.wind_color);
        } else {
            w.draw_text("WIND: CALM (Wait for tailwind gust)", field_x + 16, field_y + 44, 2, Color.hud_subtext);
        }
    } else if (sc.is_wine_cellar_scene) {
        // Subterranean Stone Vault Theme (P12-03, D-014)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 15, .g = 18, .b = 26 });

        const cellar_x: i32 = 40;
        const cellar_y: i32 = 110;
        const cellar_w: i32 = w.width - 80;
        const cellar_h: i32 = 320;

        // Vault chamber floor and stone wall
        w.fill_rect(cellar_x, cellar_y, cellar_w, cellar_h, Palette.cellar_room);
        w.draw_rect_outline(cellar_x, cellar_y, cellar_w, cellar_h, Palette.cellar_border);

        // Archway stone pillars on left and right borders
        w.fill_rect(cellar_x, cellar_y, 48, cellar_h, Color{ .r = 25, .g = 32, .b = 48 });
        w.draw_rect_outline(cellar_x, cellar_y, 48, cellar_h, Color{ .r = 45, .g = 55, .b = 75 });
        w.fill_rect(cellar_x + cellar_w - 48, cellar_y, 48, cellar_h, Color{ .r = 25, .g = 32, .b = 48 });
        w.draw_rect_outline(cellar_x + cellar_w - 48, cellar_y, 48, cellar_h, Color{ .r = 45, .g = 55, .b = 75 });

        // Stone flagstone grid lines across floor
        var row_y = cellar_y + 80;
        while (row_y < cellar_y + cellar_h) : (row_y += 60) {
            w.draw_line(cellar_x + 48, row_y, cellar_x + cellar_w - 48, row_y, Color{ .r = 35, .g = 42, .b = 58 });
        }

        // Cellar Vault Title Header
        w.draw_text("WINE CELLAR - SUBTERRANEAN VAULT", cellar_x + 60, cellar_y + 16, 2, Color{ .r = 192, .g = 132, .b = 252 });
        w.draw_text("(COOL, DAMP AIR WITH OAK & MUSTY BOUQUET)", cellar_x + 60, cellar_y + 36, 1, Color.hud_subtext);

        // Cellar torchlight sconces on stone pillars
        w.fill_circle(cellar_x + 24, cellar_y + 60, 6, Color{ .r = 245, .g = 158, .b = 11 });
        w.fill_circle(cellar_x + 24, cellar_y + 58, 3, Color{ .r = 254, .g = 240, .b = 138 });
        w.fill_circle(cellar_x + cellar_w - 24, cellar_y + 60, 6, Color{ .r = 245, .g = 158, .b = 11 });
        w.fill_circle(cellar_x + cellar_w - 24, cellar_y + 58, 3, Color{ .r = 254, .g = 240, .b = 138 });
    } else if (sc.is_tavern_scene) {
        // Dedicated Warm Wooden Tavern Common Room Theme (P12-03, D-014)
        w.fill_rect(0, 0, w.width, w.height, Palette.tavern_bg);

        const tavern_x: i32 = 40;
        const tavern_y: i32 = 110;
        const tavern_w: i32 = w.width - 80;
        const tavern_h: i32 = 320;

        w.fill_rect(tavern_x, tavern_y, tavern_w, tavern_h, Palette.tavern_room);
        w.draw_rect_outline(tavern_x, tavern_y, tavern_w, tavern_h, Color.panel_border);

        // Timber ceiling beams
        w.fill_rect(tavern_x, tavern_y + 50, tavern_w, 8, Color{ .r = 30, .g = 20, .b = 15 });
        w.fill_rect(tavern_x, tavern_y + 100, tavern_w, 6, Color{ .r = 30, .g = 20, .b = 15 });

        // Title Header
        w.draw_text("TAVERN - COMMON ROOM", tavern_x + 16, tavern_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(WARM FIREPLACE, CLINKING TANKARDS)", tavern_x + 16, tavern_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_hotel_scene) {
        // Hotel des Couronnes Corridor (P14-02, D-016)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 20, .g = 12, .b = 15 });

        const hotel_x: i32 = 40;
        const hotel_y: i32 = 110;
        const hotel_w: i32 = w.width - 80;
        const hotel_h: i32 = w.height - 210;

        // Burgundy wallpaper
        w.fill_rect(hotel_x, hotel_y, hotel_w, hotel_h, Palette.hotel_wallpaper);
        w.draw_rect_outline(hotel_x, hotel_y, hotel_w, hotel_h, Color{ .r = 140, .g = 40, .b = 45 });

        // Dark mahogany wainscoting
        w.fill_rect(hotel_x, hotel_y + hotel_h - 120, hotel_w, 120, Palette.hotel_wainscot);
        w.draw_line(hotel_x, hotel_y + hotel_h - 120, hotel_x + hotel_w, hotel_y + hotel_h - 120, Color{ .r = 180, .g = 120, .b = 50 });

        // Calculate door positions aligned with world coordinates (Room 25: x=0, Room 33: x=16)
        const pt_r25 = world_to_screen(0, 0, w.width, w.height);
        const pt_r33 = world_to_screen(16, 0, w.width, w.height);

        // Door 25 (Gabriel's room)
        const d25_x = pt_r25.x - 35;
        w.fill_rect(d25_x, hotel_y + hotel_h - 260, 70, 140, Palette.hotel_door);
        w.draw_rect_outline(d25_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 180, .g = 120, .b = 50 });
        w.draw_text("25", d25_x + 24, hotel_y + hotel_h - 250, 2, Color.wp_hover);

        // Door 33 (Mosely's room)
        const d33_x = pt_r33.x - 35;
        w.fill_rect(d33_x, hotel_y + hotel_h - 260, 70, 140, Palette.hotel_door);
        w.draw_rect_outline(d33_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 180, .g = 120, .b = 50 });
        w.draw_text("33", d33_x + 24, hotel_y + hotel_h - 250, 2, Color.wp_hover);

        // Corridor Exit / Garden Archway (aligned with CorridorExit mark world_x = 32)
        const pt_exit = world_to_screen(32, 0, w.width, w.height);
        const ex_x = pt_exit.x - 35;
        w.fill_rect(ex_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 45, .g = 25, .b = 15 });
        w.draw_rect_outline(ex_x, hotel_y + hotel_h - 260, 70, 140, Color{ .r = 180, .g = 120, .b = 50 });
        w.fill_circle(ex_x + 35, hotel_y + hotel_h - 260, 35, Color{ .r = 45, .g = 25, .b = 15 });
        w.draw_circle_outline(ex_x + 35, hotel_y + hotel_h - 260, 35, Color{ .r = 180, .g = 120, .b = 50 });
        // Sunlit daylight pouring in from courtyard garden
        w.fill_rect(ex_x + 8, hotel_y + hotel_h - 250, 54, 120, Color{ .r = 160, .g = 210, .b = 245, .a = 180 });
        w.draw_text("GARDEN", ex_x + 10, hotel_y + hotel_h - 280, 1, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("EXIT", ex_x + 18, hotel_y + hotel_h - 268, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // Brass sconces
        w.fill_circle(hotel_x + 40, hotel_y + 90, 6, Color.wp_hover);
        w.fill_circle(hotel_x + hotel_w - 40, hotel_y + 90, 6, Color.wp_hover);

        // Title
        w.draw_text("HOTEL DES COURONNES - CORRIDOR", hotel_x + 16, hotel_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(FRENCH DAMASK WALLS * ROOM 25 & ROOM 33)", hotel_x + 16, hotel_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_garden_scene) {
        // Hotel Courtyard Garden (P14-02, D-016)
        // 1. Sky & Sun
        w.fill_rect(0, 0, w.width, w.height, Palette.garden_sky);

        const garden_x: i32 = 40;
        const garden_y: i32 = 110;
        const garden_w: i32 = w.width - 80;
        const garden_h: i32 = w.height - 210;

        // Sky gradient bands & clouds
        w.fill_rect(garden_x, garden_y, garden_w, 40, Color{ .r = 110, .g = 175, .b = 230 });
        w.fill_rect(garden_x, garden_y + 40, garden_w, 40, Color{ .r = 135, .g = 195, .b = 240 });
        w.fill_rect(garden_x, garden_y + 80, garden_w, 40, Color{ .r = 165, .g = 210, .b = 245 });

        // Warm afternoon sun (top right)
        const sun_cx = garden_x + garden_w - 180;
        const sun_cy = garden_y + 45;
        w.fill_circle(sun_cx, sun_cy, 24, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_circle_outline(sun_cx, sun_cy, 28, Color{ .r = 253, .g = 224, .b = 71 });
        w.draw_circle_outline(sun_cx, sun_cy, 34, Color{ .r = 250, .g = 204, .b = 21, .a = 140 });

        // White fluffy clouds
        w.fill_circle(garden_x + 460, garden_y + 35, 18, Color{ .r = 255, .g = 255, .b = 255, .a = 210 });
        w.fill_circle(garden_x + 485, garden_y + 30, 24, Color{ .r = 255, .g = 255, .b = 255, .a = 230 });
        w.fill_circle(garden_x + 510, garden_y + 35, 18, Color{ .r = 255, .g = 255, .b = 255, .a = 210 });

        w.fill_circle(garden_x + 780, garden_y + 50, 14, Color{ .r = 255, .g = 255, .b = 255, .a = 180 });
        w.fill_circle(garden_x + 800, garden_y + 45, 20, Color{ .r = 255, .g = 255, .b = 255, .a = 200 });
        w.fill_circle(garden_x + 820, garden_y + 50, 14, Color{ .r = 255, .g = 255, .b = 255, .a = 180 });

        // Distant Pyrenean / Languedoc rolling foothills
        w.fill_circle(garden_x + 600, garden_y + 140, 180, Color{ .r = 115, .g = 150, .b = 130 });
        w.fill_circle(garden_x + 850, garden_y + 150, 200, Color{ .r = 100, .g = 140, .b = 120 });
        w.fill_circle(garden_x + 1100, garden_y + 160, 220, Color{ .r = 90, .g = 130, .b = 110 });

        // Courtyard grass lawn (Right of terrace, from x=320 to garden_w)
        w.fill_rect(garden_x + 320, garden_y + 130, garden_w - 320, garden_h - 130, Palette.garden_grass);
        w.draw_rect_outline(garden_x, garden_y, garden_w, garden_h, Color{ .r = 40, .g = 90, .b = 40 });

        // Trimmed boxwood hedge along rear fence
        w.fill_rect(garden_x + 320, garden_y + 118, garden_w - 320, 26, Color{ .r = 30, .g = 85, .b = 35 });
        var hi: i32 = garden_x + 320;
        while (hi < garden_x + garden_w - 20) : (hi += 32) {
            w.fill_circle(hi + 16, garden_y + 122, 14, Color{ .r = 38, .g = 100, .b = 42 });
        }

        // 2. Hotel des Couronnes Exterior Wing (Left side: garden_x to garden_x + 320)
        const wing_w: i32 = 320;
        w.fill_rect(garden_x, garden_y, wing_w, garden_h, Color{ .r = 215, .g = 195, .b = 160 }); // French limestone
        w.draw_rect_outline(garden_x, garden_y, wing_w, garden_h, Color{ .r = 150, .g = 130, .b = 100 });

        // Limestone masonry block seams
        var my: i32 = garden_y + 30;
        var row_even = true;
        while (my < garden_y + garden_h) : (my += 28) {
            w.draw_line(garden_x, my, garden_x + wing_w, my, Color{ .r = 185, .g = 165, .b = 130 });
            const offset: i32 = if (row_even) 0 else 30;
            var mx: i32 = garden_x + offset;
            while (mx < garden_x + wing_w) : (mx += 60) {
                w.draw_line(mx, my, mx, my + 28, Color{ .r = 185, .g = 165, .b = 130 });
            }
            row_even = !row_even;
        }

        // Ivy vines creeping up hotel wall
        w.fill_circle(garden_x + 30, garden_y + 90, 20, Color{ .r = 35, .g = 100, .b = 40 });
        w.fill_circle(garden_x + 45, garden_y + 130, 24, Color{ .r = 45, .g = 120, .b = 50 });
        w.fill_circle(garden_x + 25, garden_y + 180, 22, Color{ .r = 35, .g = 95, .b = 38 });
        w.fill_circle(garden_x + 40, garden_y + 230, 26, Color{ .r = 50, .g = 130, .b = 55 });
        w.fill_circle(garden_x + 300, garden_y + 110, 18, Color{ .r = 35, .g = 100, .b = 40 });
        w.fill_circle(garden_x + 310, garden_y + 160, 22, Color{ .r = 45, .g = 120, .b = 50 });

        // Upper-floor French window with dark green shutters
        const win_x = garden_x + 110;
        const win_y = garden_y + 40;
        w.fill_rect(win_x, win_y, 80, 100, Color{ .r = 25, .g = 35, .b = 50 }); // Window glass
        w.draw_rect_outline(win_x, win_y, 80, 100, Color{ .r = 140, .g = 120, .b = 90 });
        // Window panes
        w.draw_line(win_x + 40, win_y, win_x + 40, win_y + 100, Color.white);
        w.draw_line(win_x, win_y + 50, win_x + 80, win_y + 50, Color.white);
        // Left & right wooden shutters (olive green)
        w.fill_rect(win_x - 30, win_y, 28, 100, Color{ .r = 45, .g = 80, .b = 55 });
        w.draw_rect_outline(win_x - 30, win_y, 28, 100, Color{ .r = 30, .g = 55, .b = 38 });
        w.fill_rect(win_x + 82, win_y, 28, 100, Color{ .r = 45, .g = 80, .b = 55 });
        w.draw_rect_outline(win_x + 82, win_y, 28, 100, Color{ .r = 30, .g = 55, .b = 38 });
        // Window sill with red geranium flower box
        w.fill_rect(win_x - 10, win_y + 98, 100, 14, Color{ .r = 160, .g = 75, .b = 45 });
        w.fill_circle(win_x + 10, win_y + 94, 6, Color{ .r = 239, .g = 68, .b = 68 });
        w.fill_circle(win_x + 35, win_y + 94, 6, Color{ .r = 244, .g = 63, .b = 94 });
        w.fill_circle(win_x + 60, win_y + 94, 6, Color{ .r = 239, .g = 68, .b = 68 });

        // Ground floor arched entrance door (aligned with GardenPath world_x = 0)
        const pt_path = world_to_screen(0, 0, w.width, w.height);
        const door_x = pt_path.x - 45;
        const door_y = garden_y + garden_h - 220;
        w.fill_rect(door_x, door_y, 90, 140, Color{ .r = 45, .g = 25, .b = 15 }); // Dark carved oak
        w.draw_rect_outline(door_x, door_y, 90, 140, Color{ .r = 180, .g = 130, .b = 70 });
        // Arch top
        w.fill_circle(door_x + 45, door_y, 45, Color{ .r = 45, .g = 25, .b = 15 });
        w.draw_circle_outline(door_x + 45, door_y, 45, Color{ .r = 180, .g = 130, .b = 70 });
        // Glass window panels with warm hallway interior light
        w.fill_rect(door_x + 10, door_y + 10, 30, 50, Color{ .r = 254, .g = 240, .b = 138, .a = 200 });
        w.fill_rect(door_x + 50, door_y + 10, 30, 50, Color{ .r = 254, .g = 240, .b = 138, .a = 200 });
        w.draw_rect_outline(door_x + 10, door_y + 10, 30, 50, Color{ .r = 180, .g = 130, .b = 70 });
        w.draw_rect_outline(door_x + 50, door_y + 10, 30, 50, Color{ .r = 180, .g = 130, .b = 70 });
        // Brass handle
        w.fill_circle(door_x + 78, door_y + 75, 4, Color{ .r = 250, .g = 204, .b = 21 });
        // Hotel Doorway Header
        w.fill_rect(door_x - 10, door_y - 24, 110, 18, Color{ .r = 30, .g = 20, .b = 15 });
        w.draw_rect_outline(door_x - 10, door_y - 24, 110, 18, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_text("HOTEL EXIT", door_x - 2, door_y - 20, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // 3. Terracotta Patio Terrace (near hotel, left foreground)
        const terrace_w: i32 = 320;
        w.fill_rect(garden_x, garden_y + garden_h - 100, terrace_w, 100, Color{ .r = 185, .g = 95, .b = 65 }); // Terracotta
        // Grout tiles
        var ty: i32 = garden_y + garden_h - 100;
        while (ty < garden_y + garden_h) : (ty += 25) {
            w.draw_line(garden_x, ty, garden_x + terrace_w, ty, Color{ .r = 145, .g = 70, .b = 45 });
        }
        var tx: i32 = garden_x;
        while (tx < garden_x + terrace_w) : (tx += 30) {
            w.draw_line(tx, garden_y + garden_h - 100, tx, garden_y + garden_h, Color{ .r = 145, .g = 70, .b = 45 });
        }

        // 4. Centerpiece: Stone Tiered Birdbath / Fountain (between terrace and fence)
        const fountain_x = garden_x + 400;
        const fountain_y = garden_y + garden_h - 80;
        // Stone base & pillar
        w.fill_rect(fountain_x - 14, fountain_y + 10, 28, 36, Color{ .r = 160, .g = 150, .b = 140 });
        w.draw_rect_outline(fountain_x - 14, fountain_y + 10, 28, 36, Color{ .r = 110, .g = 100, .b = 95 });
        // Lower bowl
        w.fill_circle(fountain_x, fountain_y + 10, 32, Color{ .r = 175, .g = 165, .b = 155 });
        w.draw_circle_outline(fountain_x, fountain_y + 10, 32, Color{ .r = 120, .g = 110, .b = 105 });
        w.fill_circle(fountain_x, fountain_y + 10, 26, Color{ .r = 56, .g = 189, .b = 248, .a = 210 }); // Water
        // Upper pillar & small bowl
        w.fill_rect(fountain_x - 7, fountain_y - 18, 14, 26, Color{ .r = 160, .g = 150, .b = 140 });
        w.fill_circle(fountain_x, fountain_y - 18, 16, Color{ .r = 175, .g = 165, .b = 155 });
        w.fill_circle(fountain_x, fountain_y - 18, 12, Color{ .r = 56, .g = 189, .b = 248, .a = 210 });

        // 5. Wooden Picket Fence (x = 360 to garden_w)
        const fence_start_x = garden_x + 340;
        const fence_w = garden_w - 340;
        const fence_y = garden_y + garden_h - 180;
        // Fence horizontal support rails
        w.fill_rect(fence_start_x, fence_y - 8, fence_w, 10, Color{ .r = 135, .g = 85, .b = 40 });
        w.fill_rect(fence_start_x, fence_y + 34, fence_w, 10, Color{ .r = 135, .g = 85, .b = 40 });

        // Vertical pickets
        var p_i: i32 = fence_start_x;
        while (p_i < garden_x + garden_w - 60) : (p_i += 22) {
            // Skip pickets where the hole is located (around pt_fence.x = 604)
            if (p_i >= 580 and p_i <= 630) {
                p_i += 22;
                continue;
            }

            // Pointed tip
            w.draw_line(p_i + 5, fence_y - 32, p_i, fence_y - 22, Color{ .r = 100, .g = 60, .b = 28 });
            w.draw_line(p_i + 5, fence_y - 32, p_i + 10, fence_y - 22, Color{ .r = 100, .g = 60, .b = 28 });
            w.fill_rect(p_i, fence_y - 22, 11, 74, Palette.garden_fence);
            w.draw_rect_outline(p_i, fence_y - 22, 11, 74, Color{ .r = 100, .g = 60, .b = 28 });
        }

        // 6. Fence Hole (Hotspot at world_x = 18, screen x ≈ 604)
        const pt_fence = world_to_screen(18, 0, w.width, w.height);
        const hole_x = pt_fence.x - 30;
        const hole_y = fence_y + 8;
        const hole_w: i32 = 60;
        const hole_h: i32 = 46;

        // Broken jagged pickets above hole
        w.fill_rect(hole_x + 4, fence_y - 22, 11, 28, Palette.garden_fence);
        w.fill_rect(hole_x + 24, fence_y - 22, 11, 22, Palette.garden_fence);
        w.fill_rect(hole_x + 44, fence_y - 22, 11, 26, Palette.garden_fence);

        // The escape opening through to priest's property
        w.fill_rect(hole_x, hole_y, hole_w, hole_h, Color{ .r = 20, .g = 30, .b = 18 });
        w.draw_rect_outline(hole_x, hole_y, hole_w, hole_h, Color{ .r = 120, .g = 70, .b = 30 });
        w.draw_text("FENCE GAP", hole_x + 4, hole_y - 12, 1, Color{ .r = 250, .g = 204, .b = 21 });

        // Masking tape indicator if taped
        if (status_of(frame).fence_taped) {
            // Wide tape band stretched taut across hole
            w.fill_rect(hole_x - 8, hole_y + 16, hole_w + 16, 12, Color{ .r = 254, .g = 243, .b = 199 });
            w.draw_rect_outline(hole_x - 8, hole_y + 16, hole_w + 16, 12, Color{ .r = 217, .g = 119, .b = 6 });

            if (status_of(frame).fence_has_hair) {
                // Thick tuft of black cat hair stuck to the tape!
                w.fill_rect(hole_x + 14, hole_y + 13, 32, 18, Color.black);
                w.draw_rect_outline(hole_x + 14, hole_y + 13, 32, 18, Color{ .r = 250, .g = 204, .b = 21 });
                w.draw_text("★ BLACK CAT FUR STUCK TO TAPE ★", hole_x - 45, hole_y - 28, 1, Color{ .r = 250, .g = 204, .b = 21 });
            } else {
                w.draw_text("[STICKY MASKING TAPE READY]", hole_x - 30, hole_y - 28, 1, Color.wp_hover);
            }
        }

        // 7. Lavender Shrub & Stray Cat Lounge (world_x = 34, screen x ≈ 892)
        const pt_cat = world_to_screen(34, 0, w.width, w.height);
        const shrub_x = pt_cat.x;
        const shrub_y = pt_cat.y - 48;

        // Wooden Potting Bench with garden supplies
        w.fill_rect(shrub_x - 70, shrub_y + 20, 60, 24, Color{ .r = 115, .g = 75, .b = 40 });
        w.draw_rect_outline(shrub_x - 70, shrub_y + 20, 60, 24, Color{ .r = 75, .g = 45, .b = 22 });
        w.fill_rect(shrub_x - 68, shrub_y + 44, 8, 30, Color{ .r = 85, .g = 50, .b = 25 });
        w.fill_rect(shrub_x - 22, shrub_y + 44, 8, 30, Color{ .r = 85, .g = 50, .b = 25 });
        // Terracotta pot on bench
        w.fill_rect(shrub_x - 62, shrub_y + 8, 16, 12, Color{ .r = 190, .g = 90, .b = 55 });
        // Garden spray bottle sitting on bench
        w.fill_rect(shrub_x - 40, shrub_y + 4, 12, 16, Color{ .r = 56, .g = 189, .b = 248 });
        w.fill_rect(shrub_x - 38, shrub_y - 2, 8, 6, Color.white);

        // Fragrant blooming lavender bush clusters
        w.fill_circle(shrub_x + 10, shrub_y - 5, 26, Color{ .r = 40, .g = 135, .b = 60 });
        w.fill_circle(shrub_x + 35, shrub_y + 5, 24, Color{ .r = 30, .g = 115, .b = 48 });
        w.fill_circle(shrub_x - 5, shrub_y + 10, 22, Color{ .r = 50, .g = 150, .b = 70 });
        // Purple lavender flower specks
        w.fill_circle(shrub_x + 10, shrub_y - 18, 10, Color{ .r = 168, .g = 85, .b = 247 });
        w.fill_circle(shrub_x + 28, shrub_y - 8, 12, Color{ .r = 192, .g = 132, .b = 252 });
        w.fill_circle(shrub_x - 2, shrub_y - 4, 11, Color{ .r = 168, .g = 85, .b = 247 });
        w.fill_circle(shrub_x + 20, shrub_y + 12, 10, Color{ .r = 147, .g = 51, .b = 234 });

        // 8. Far Right: Stone Arch / Village Gate (leading toward Bike Shop)
        const gate_x = garden_x + garden_w - 75;
        const gate_y = garden_y + garden_h - 220;
        w.fill_rect(gate_x, gate_y, 65, 140, Color{ .r = 140, .g = 130, .b = 115 });
        w.draw_rect_outline(gate_x, gate_y, 65, 140, Color{ .r = 95, .g = 85, .b = 75 });
        w.fill_circle(gate_x + 32, gate_y, 32, Color{ .r = 140, .g = 130, .b = 115 });
        // Iron gate bars
        w.fill_rect(gate_x + 10, gate_y, 45, 130, Color{ .r = 18, .g = 22, .b = 30 });
        w.draw_line(gate_x + 20, gate_y, gate_x + 20, gate_y + 130, Color{ .r = 80, .g = 90, .b = 100 });
        w.draw_line(gate_x + 32, gate_y, gate_x + 32, gate_y + 130, Color{ .r = 80, .g = 90, .b = 100 });
        w.draw_line(gate_x + 44, gate_y, gate_x + 44, gate_y + 130, Color{ .r = 80, .g = 90, .b = 100 });
        w.draw_text("VILLAGE", gate_x + 6, gate_y - 18, 1, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_text("-> SHOP", gate_x + 6, gate_y - 6, 1, Color{ .r = 250, .g = 204, .b = 21 });

        // 9. Scene Title & Header
        w.draw_text("HOTEL COURTYARD - GARDEN FENCE", garden_x + 16, garden_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(SUNNY PROVENCAL COURTYARD * WOODEN PICKET FENCE * ESCAPE GAP)", garden_x + 16, garden_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_bike_rental_scene) {
        // Madame Buthane's Bike Rental Shop (P14-02, D-016)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 25, .g = 20, .b = 20 });

        const shop_x: i32 = 40;
        const shop_y: i32 = 110;
        const shop_w: i32 = w.width - 80;
        const shop_h: i32 = w.height - 210;

        w.fill_rect(shop_x, shop_y, shop_w, shop_h, Palette.rental_wall);
        w.draw_rect_outline(shop_x, shop_y, shop_w, shop_h, Color{ .r = 110, .g = 95, .b = 85 });

        // Stone floor
        w.fill_rect(shop_x, shop_y + shop_h - 100, shop_w, 100, Color{ .r = 45, .g = 40, .b = 38 });

        // Road touring map of Languedoc on the wall
        const map_x = shop_x + 60;
        w.fill_rect(map_x, shop_y + 55, 140, 90, Color{ .r = 254, .g = 243, .b = 199 });
        w.draw_rect_outline(map_x, shop_y + 55, 140, 90, Color{ .r = 180, .g = 83, .b = 9 });
        w.draw_text("MAP OF LANGUEDOC", map_x + 8, shop_y + 65, 1, Color{ .r = 120, .g = 53, .b = 15 });
        w.draw_text("RENNES-LE-CHATEAU", map_x + 8, shop_y + 80, 1, Color{ .r = 180, .g = 83, .b = 9 });

        // Pine rental counter (aligned with CounterMark world_x = 16)
        const pt_counter = world_to_screen(16, 0, w.width, w.height);
        const cnt_x = pt_counter.x - 110;
        w.fill_rect(cnt_x, shop_y + shop_h - 180, 220, 80, Palette.rental_counter);
        w.draw_rect_outline(cnt_x, shop_y + shop_h - 180, 220, 80, Color{ .r = 217, .g = 119, .b = 6 });
        w.draw_text("RENTAL COUNTER", cnt_x + 20, shop_y + shop_h - 165, 2, Color{ .r = 60, .g = 35, .b = 15 });

        // Red Motorcycle display (aligned with BikeMark world_x = 32)
        const pt_bike = world_to_screen(32, 0, w.width, w.height);
        const mc_x = pt_bike.x - 65;
        w.fill_circle(mc_x + 25, shop_y + shop_h - 110, 20, Color.black);
        w.fill_circle(mc_x + 105, shop_y + shop_h - 110, 20, Color.black);
        w.draw_circle_outline(mc_x + 25, shop_y + shop_h - 110, 20, Color{ .r = 200, .g = 200, .b = 200 });
        w.draw_circle_outline(mc_x + 105, shop_y + shop_h - 110, 20, Color{ .r = 200, .g = 200, .b = 200 });
        w.fill_rect(mc_x + 25, shop_y + shop_h - 140, 80, 25, Palette.motorcycle_red);
        w.draw_line(mc_x + 35, shop_y + shop_h - 155, mc_x + 60, shop_y + shop_h - 140, Color.white);

        if (status_of(frame).bike_rented) {
            w.draw_text("[RENTED TO MOSELY!]", mc_x + 10, shop_y + shop_h - 170, 2, Color.status_running);
        } else {
            w.draw_text("[RESERVED: MOSELY]", mc_x + 10, shop_y + shop_h - 170, 2, Color.cue_alert);
        }

        // Title
        w.draw_text("RENNES-LE-CHATEAU - BIKE RENTAL SHOP", shop_x + 16, shop_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(VINTAGE MOTORCYCLE * MADAME BUTHANE AT THE DESK)", shop_x + 16, shop_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_tidewalk_scene) {
        // Brackwater Tidewalk (P15-02, P35-02)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 10, .g = 15, .b = 30 }); // Deep night sky

        const road_x: i32 = 40;
        const road_y: i32 = 110;
        const road_w: i32 = w.width - 80;
        const road_h: i32 = w.height - 210;

        // Pine tree silhouettes and mountain ridges
        w.fill_rect(road_x, road_y + 40, road_w, road_h - 40, Color{ .r = 15, .g = 22, .b = 38 });
        // Yellow crescent moon
        w.fill_circle(road_x + road_w - 120, road_y + 60, 24, Color{ .r = 254, .g = 240, .b = 138 });
        w.fill_circle(road_x + road_w - 112, road_y + 54, 20, Color{ .r = 10, .g = 15, .b = 30 });

        // Dark cobblestone harbour walk
        w.fill_rect(road_x, road_y + road_h - 130, road_w, 130, Color{ .r = 30, .g = 35, .b = 45 });
        w.draw_rect_outline(road_x, road_y + road_h - 130, road_w, 130, Color{ .r = 60, .g = 70, .b = 85 });

        // Roadside iron lantern
        w.fill_rect(road_x + 80, road_y + road_h - 190, 6, 60, Color.black);
        w.fill_circle(road_x + 83, road_y + road_h - 195, 10, Color{ .r = 245, .g = 158, .b = 11, .a = 220 });

        // Header
        w.draw_text("BRACKWATER - THE TIDEWALK", road_x + 16, road_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(PATROLLING FENCERS * BARBED DUELS * LEARNED COMEBACKS)", road_x + 16, road_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_fencing_yard_scene) {
        // Mistress Vell's fencing yard
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 12, .g = 25, .b = 18 });

        const s_x: i32 = 40;
        const s_y: i32 = 110;
        const s_w: i32 = w.width - 80;
        const s_h: i32 = w.height - 210;

        w.fill_rect(s_x, s_y, s_w, s_h, Color{ .r = 20, .g = 45, .b = 30 });
        w.draw_rect_outline(s_x, s_y, s_w, s_h, Color{ .r = 34, .g = 80, .b = 50 });

        // Training circle
        const center_x = s_x + @divTrunc(s_w, 2);
        w.draw_circle_outline(center_x, s_y + s_h - 80, 70, Color{ .r = 250, .g = 204, .b = 21 });

        // Timber fence & gate
        w.fill_rect(s_x + 60, s_y + s_h - 160, 140, 15, Color{ .r = 160, .g = 120, .b = 60 });

        // Target dummy
        w.fill_circle(s_x + s_w - 140, s_y + s_h - 120, 16, Color{ .r = 217, .g = 119, .b = 6 });
        w.fill_rect(s_x + s_w - 144, s_y + s_h - 104, 8, 30, Color{ .r = 120, .g = 70, .b = 30 });

        // Header
        w.draw_text("VELL'S FENCING YARD", s_x + 16, s_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(MASTER VARIANTS * SAME COMEBACKS * TIER CHECKS)", s_x + 16, s_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_lantern_scene) {
        // The Drowned Lantern
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 30, .g = 18, .b = 12 });

        const b_x: i32 = 40;
        const b_y: i32 = 110;
        const b_w: i32 = w.width - 80;
        const b_h: i32 = w.height - 210;

        w.fill_rect(b_x, b_y, b_w, b_h, Color{ .r = 55, .g = 32, .b = 20 });
        w.draw_rect_outline(b_x, b_y, b_w, b_h, Color{ .r = 120, .g = 75, .b = 40 });

        // Oak bar counter
        w.fill_rect(b_x + 80, b_y + b_h - 140, 260, 60, Color{ .r = 90, .g = 50, .b = 28 });
        w.draw_rect_outline(b_x + 80, b_y + b_h - 140, 260, 60, Color{ .r = 160, .g = 95, .b = 45 });
        w.draw_text("CIDER BAR", b_x + 100, b_y + b_h - 125, 2, Color{ .r = 254, .g = 240, .b = 138 });

        // Cider barrel
        w.fill_circle(b_x + b_w - 160, b_y + b_h - 100, 30, Color{ .r = 40, .g = 25, .b = 18 });
        w.draw_circle_outline(b_x + b_w - 160, b_y + b_h - 100, 30, Color{ .r = 180, .g = 120, .b = 50 });
        w.draw_text("CIDER", b_x + b_w - 180, b_y + b_h - 106, 2, Color{ .r = 239, .g = 68, .b = 68 });

        // Header
        w.draw_text("THE DROWNED LANTERN - BRACKWATER", b_x + 16, b_y + 16, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(BARKEEP AT THE TAPS * CONVERSATIONAL REPETITION FATIGUE)", b_x + 16, b_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_village_scene) {
        // The Living Village: Multi-Building Settlement & Social Graph HUD (P18-03, D-021)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 16, .g = 28, .b = 20 });

        const v_x: i32 = 228;
        const v_y: i32 = 82;
        const v_w: i32 = w.width - 490;
        const v_h: i32 = w.height - 178;

        // Verdant village green commons
        w.fill_rect(v_x, v_y, v_w, v_h, Color{ .r = 26, .g = 52, .b = 32 });
        w.draw_rect_outline(v_x, v_y, v_w, v_h, Color{ .r = 65, .g = 110, .b = 70 });

        // Header Banner inside village commons
        w.draw_text("THE LIVING VILLAGE - EMERGENT SIMULATION SANDBOX", v_x + 14, v_y + 10, 2, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("(AUTONOMOUS DRIVES * PROPERTY THEFT * WITNESS RUMORS * JUSTICE CASCADE)", v_x + 14, v_y + 30, 1, Color.hud_subtext);

        // 1. Bakery (Upper-left landmark at world (2, -10))
        const pt_bakery = world_to_screen(2, -10, w.width, w.height);
        w.fill_rect(pt_bakery.x - 62, pt_bakery.y - 44, 124, 72, Color{ .r = 120, .g = 55, .b = 35 });
        w.draw_rect_outline(pt_bakery.x - 62, pt_bakery.y - 44, 124, 72, Color{ .r = 245, .g = 158, .b = 11 });
        w.draw_text("VILLAGE BAKERY", pt_bakery.x - 46, pt_bakery.y - 38, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // 2. Farm & Granary (Lower-left landmark at world (2, 6))
        const pt_farm = world_to_screen(2, 6, w.width, w.height);
        w.fill_rect(pt_farm.x - 62, pt_farm.y - 36, 124, 72, Color{ .r = 95, .g = 75, .b = 30 });
        w.draw_rect_outline(pt_farm.x - 62, pt_farm.y - 36, 124, 72, Color{ .r = 234, .g = 179, .b = 8 });
        // Golden wheat rows
        w.draw_line(pt_farm.x - 50, pt_farm.y - 12, pt_farm.x + 50, pt_farm.y - 12, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_line(pt_farm.x - 50, pt_farm.y - 4, pt_farm.x + 50, pt_farm.y - 4, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_text("WHEAT FARM", pt_farm.x - 34, pt_farm.y - 30, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // 3. Town Square & Fountain (Center landmark at world (15, -2))
        const pt_sq = world_to_screen(15, -2, w.width, w.height);
        w.fill_circle(pt_sq.x, pt_sq.y, 56, Color{ .r = 75, .g = 85, .b = 99 });
        w.draw_circle_outline(pt_sq.x, pt_sq.y, 56, Color{ .r = 156, .g = 163, .b = 175 });
        w.fill_circle(pt_sq.x, pt_sq.y - 18, 18, Color{ .r = 56, .g = 189, .b = 248, .a = 210 });
        w.draw_circle_outline(pt_sq.x, pt_sq.y - 18, 18, Color.white);
        w.draw_text("TOWN SQUARE", pt_sq.x - 36, pt_sq.y - 50, 1, Color.white);

        // 4. Cottages (Bottom-center landmark at world (15, 9))
        const pt_cot = world_to_screen(15, 9, w.width, w.height);
        w.fill_rect(pt_cot.x - 64, pt_cot.y - 32, 128, 64, Color{ .r = 85, .g = 60, .b = 42 });
        w.draw_rect_outline(pt_cot.x - 64, pt_cot.y - 32, 128, 64, Color{ .r = 180, .g = 130, .b = 80 });
        w.draw_text("COTTAGES (SLEEP)", pt_cot.x - 50, pt_cot.y - 26, 1, Color{ .r = 253, .g = 230, .b = 138 });

        // 5. Village Tavern (Upper-right landmark at world (28, -10))
        const pt_tav = world_to_screen(28, -10, w.width, w.height);
        w.fill_rect(pt_tav.x - 62, pt_tav.y - 44, 124, 72, Color{ .r = 78, .g = 38, .b = 26 });
        w.draw_rect_outline(pt_tav.x - 62, pt_tav.y - 44, 124, 72, Color{ .r = 217, .g = 119, .b = 6 });
        w.draw_text("VILLAGE TAVERN", pt_tav.x - 46, pt_tav.y - 38, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // 6. Sheriff's Post & Jail (Lower-right landmark at world (28, 6))
        const pt_sh = world_to_screen(28, 6, w.width, w.height);
        w.fill_rect(pt_sh.x - 62, pt_sh.y - 36, 124, 72, Color{ .r = 30, .g = 45, .b = 75 });
        w.draw_rect_outline(pt_sh.x - 62, pt_sh.y - 36, 124, 72, Color{ .r = 96, .g = 165, .b = 250 });
        // Iron jail cell bars on right side of Sheriff's Post
        var bar_x: i32 = pt_sh.x + 18;
        while (bar_x <= pt_sh.x + 52) : (bar_x += 8) {
            w.draw_line(bar_x, pt_sh.y - 20, bar_x, pt_sh.y + 28, Color{ .r = 148, .g = 163, .b = 184 });
        }
        w.draw_text("SHERIFF & JAIL", pt_sh.x - 54, pt_sh.y - 30, 1, Color{ .r = 147, .g = 197, .b = 253 });

        // Left HUD Panel: Autonomous Villager Physiological Drives (P18-01)
        const lp_x: i32 = 12;
        const lp_y: i32 = 82;
        const lp_w: i32 = 208;
        const lp_h: i32 = w.height - 178;
        w.fill_rect(lp_x, lp_y, lp_w, lp_h, Color{ .r = 12, .g = 19, .b = 34, .a = 240 });
        w.draw_rect_outline(lp_x, lp_y, lp_w, lp_h, Color{ .r = 71, .g = 85, .b = 105 });
        w.draw_text("VILLAGER DRIVES (P18-01)", lp_x + 10, lp_y + 10, 1, Color.wp_hover);

        var dy_cursor: i32 = lp_y + 28;
        for (status_of(frame).villager_drives[0..status_of(frame).villager_drive_count]) |vd| {
            const vname = vd.get_name();
            const act_label = switch (vd.activity) {
                0 => "Work",
                1 => "Patrol",
                2 => "Eat",
                3 => "Sleep",
                4 => "Social",
                5 => "STEAL!",
                6 => "Flee!",
                7 => "Hunt!",
                8 => "JAILED",
                else => "Idle",
            };
            var line_buf: [64]u8 = undefined;
            const hdr = std.fmt.bufPrint(&line_buf, "{s} ({d}g) [{s}]", .{ vname, vd.gold, act_label }) catch vname;
            const hdr_col = if (vd.is_arrested)
                Color.cue_alert
            else if (vd.knows_rumor)
                Color.wp_hover
            else
                Color.white;
            w.draw_text(hdr, lp_x + 8, dy_cursor, 1, hdr_col);
            dy_cursor += 12;

            // Hunger Bar
            w.draw_text("Hng:", lp_x + 8, dy_cursor, 1, Color.hud_subtext);
            w.fill_rect(lp_x + 38, dy_cursor + 1, 100, 6, Color{ .r = 30, .g = 41, .b = 59 });
            const h_col = if (vd.hunger >= 80)
                Color.cue_alert
            else if (vd.hunger >= 55)
                Color.status_paused
            else
                Color.status_running;
            w.fill_rect(lp_x + 38, dy_cursor + 1, @as(i32, vd.hunger), 6, h_col);
            dy_cursor += 10;

            // Energy Bar
            w.draw_text("Eng:", lp_x + 8, dy_cursor, 1, Color.hud_subtext);
            w.fill_rect(lp_x + 38, dy_cursor + 1, 100, 6, Color{ .r = 30, .g = 41, .b = 59 });
            w.fill_rect(lp_x + 38, dy_cursor + 1, @as(i32, vd.energy), 6, Color.wp_target);
            dy_cursor += 16;
        }

        // Right HUD Panel: Live Social Graph & Emergence Status (P18-02, P18-03)
        const rp_w: i32 = 242;
        const rp_x: i32 = w.width - rp_w - 12;
        const rp_y: i32 = 82;
        const rp_h: i32 = w.height - 178;
        w.fill_rect(rp_x, rp_y, rp_w, rp_h, Color{ .r = 12, .g = 19, .b = 34, .a = 240 });
        w.draw_rect_outline(rp_x, rp_y, rp_w, rp_h, Color{ .r = 71, .g = 85, .b = 105 });
        w.draw_text("EMERGENCE & SOCIAL GRAPH", rp_x + 10, rp_y + 10, 1, Color.wp_hover);

        var ry_cursor: i32 = rp_y + 28;
        const crime_str = if (status_of(frame).village_crime_active) "1. Theft:   COMMITTED!" else "1. Theft:   None";
        w.draw_text(crime_str, rp_x + 10, ry_cursor, 1, if (status_of(frame).village_crime_active) Color.cue_alert else Color.hud_subtext);
        ry_cursor += 14;

        const war_str = if (status_of(frame).village_warrant_active) "2. Warrant: ACTIVE HUNT!" else "2. Warrant: None";
        w.draw_text(war_str, rp_x + 10, ry_cursor, 1, if (status_of(frame).village_warrant_active) Color.status_paused else Color.hud_subtext);
        ry_cursor += 14;

        const arr_str = if (status_of(frame).village_arrest_made) "3. Justice: ARRESTED & JAILED!" else "3. Justice: Peace / Pending";
        w.draw_text(arr_str, rp_x + 10, ry_cursor, 1, if (status_of(frame).village_arrest_made) Color.status_running else Color.hud_subtext);
        ry_cursor += 18;

        w.draw_line(rp_x + 8, ry_cursor, rp_x + rp_w - 8, ry_cursor, Color{ .r = 51, .g = 65, .b = 85 });
        ry_cursor += 8;
        w.draw_text("RELATIONAL EDGES (WORLD):", rp_x + 10, ry_cursor, 1, Color.hud_subtext);
        ry_cursor += 14;

        var edge_i: usize = 0;
        while (edge_i < status_of(frame).social_edge_count and ry_cursor < rp_y + rp_h - 16) : (edge_i += 1) {
            const se = &status_of(frame).social_edges[edge_i];
            const rel_tag = switch (se.kind) {
                0 => "Friend",
                1 => "Grudge",
                2 => "Rumor",
                3 => "Warrant",
                4 => "Arrested",
                else => "Edge",
            };
            const ecol = switch (se.kind) {
                0 => Color{ .r = 74, .g = 222, .b = 128 },
                1 => Color{ .r = 251, .g = 146, .b = 60 },
                2 => Color{ .r = 250, .g = 204, .b = 21 },
                3 => Color.cue_alert,
                4 => Color.wp_target,
                else => Color.white,
            };
            var ebuf: [64]u8 = undefined;
            const estr = std.fmt.bufPrint(&ebuf, "* {s}({s}, {s})", .{ rel_tag, se.get_from(), se.get_to() }) catch "";
            w.draw_text(estr, rp_x + 10, ry_cursor, 1, ecol);
            ry_cursor += 13;
        }
    } else if (sc.is_goat_courtyard_scene) {
        // Lochmarne Castle Courtyard (P20-02, D-023)
        // 1. Sky & Atmosphere
        w.fill_rect(0, 0, w.width, w.height, Palette.lochmarne_sky);

        const yard_x: i32 = 40;
        const yard_y: i32 = 110;
        const yard_w: i32 = w.width - 80;
        const yard_h: i32 = w.height - 210;

        // Rolling Irish emerald hills in background
        w.fill_circle(yard_x + 300, yard_y + 160, 220, Color{ .r = 40, .g = 95, .b = 45 });
        w.fill_circle(yard_x + 650, yard_y + 170, 240, Color{ .r = 35, .g = 85, .b = 40 });
        w.fill_circle(yard_x + 980, yard_y + 150, 200, Color{ .r = 42, .g = 100, .b = 48 });

        // Weathered castle stone walls & ivy (Left tower and rear battlements)
        const wall_top = yard_y + 60;
        w.fill_rect(yard_x, wall_top, yard_w, 70, Palette.lochmarne_ruins);
        w.draw_rect_outline(yard_x, wall_top, yard_w, 70, Color{ .r = 65, .g = 60, .b = 55 });

        // Castle tower ruins on the left
        const tower_w: i32 = 180;
        w.fill_rect(yard_x, yard_y, tower_w, yard_h, Palette.lochmarne_ruins);
        w.draw_rect_outline(yard_x, yard_y, tower_w, yard_h, Color{ .r = 60, .g = 55, .b = 50 });

        // Tower battlements (crenellations)
        var cr_x: i32 = yard_x;
        while (cr_x < yard_x + tower_w - 20) : (cr_x += 36) {
            w.fill_rect(cr_x, yard_y - 18, 20, 18, Palette.lochmarne_ruins);
            w.draw_rect_outline(cr_x, yard_y - 18, 20, 18, Color{ .r = 60, .g = 55, .b = 50 });
        }

        // Arched arrow-slit window in tower
        w.fill_rect(yard_x + 75, yard_y + 70, 26, 60, Color{ .r = 25, .g = 22, .b = 20 });
        w.fill_circle(yard_x + 88, yard_y + 70, 13, Color{ .r = 25, .g = 22, .b = 20 });

        // Ivy vines crawling up the ruins
        w.fill_circle(yard_x + 20, yard_y + 120, 18, Color{ .r = 30, .g = 75, .b = 35 });
        w.fill_circle(yard_x + 35, yard_y + 160, 22, Color{ .r = 38, .g = 90, .b = 42 });
        w.fill_circle(yard_x + 25, yard_y + 210, 20, Color{ .r = 32, .g = 80, .b = 36 });
        w.fill_circle(yard_x + 160, yard_y + 100, 16, Color{ .r = 35, .g = 85, .b = 40 });
        w.fill_circle(yard_x + 170, yard_y + 140, 20, Color{ .r = 40, .g = 95, .b = 45 });

        // Courtyard emerald grass lawn
        w.fill_rect(yard_x + tower_w, yard_y + 120, yard_w - tower_w, yard_h - 120, Palette.lochmarne_grass);
        w.draw_rect_outline(yard_x, yard_y, yard_w, yard_h, Color{ .r = 40, .g = 55, .b = 40 });

        // Cellar Pit / Peagram's Excavation Entrance (aligned with DigOpening)
        const pt_dig = world_to_screen(28, 0, w.width, w.height);
        const pit_x = pt_dig.x - 45;
        const pit_y = yard_y + yard_h - 150;
        w.fill_rect(pit_x, pit_y, 90, 60, Color{ .r = 20, .g = 18, .b = 16 });
        w.draw_rect_outline(pit_x, pit_y, 90, 60, Color{ .r = 100, .g = 65, .b = 30 });
        // Wooden ladder rungs descending into pit
        w.fill_rect(pit_x + 30, pit_y - 12, 6, 72, Color{ .r = 140, .g = 90, .b = 45 });
        w.fill_rect(pit_x + 54, pit_y - 12, 6, 72, Color{ .r = 140, .g = 90, .b = 45 });
        var rung_y: i32 = pit_y - 6;
        while (rung_y < pit_y + 54) : (rung_y += 12) {
            w.fill_rect(pit_x + 30, rung_y, 30, 4, Color{ .r = 170, .g = 115, .b = 60 });
        }

        // Tether Stake (at TetherCenter)
        const pt_tether = world_to_screen(16, 0, w.width, w.height);
        w.fill_rect(pt_tether.x - 5, pt_tether.y - 18, 10, 36, Color{ .r = 110, .g = 70, .b = 35 });
        w.draw_rect_outline(pt_tether.x - 5, pt_tether.y - 18, 10, 36, Color{ .r = 75, .g = 45, .b = 20 });
        w.draw_circle_outline(pt_tether.x, pt_tether.y - 14, 6, Color{ .r = 180, .g = 180, .b = 190 }); // Iron ring

        // Farm Plough (at PloughMark)
        const pt_plough = world_to_screen(10, 8, w.width, w.height);
        const plough_draw_x = if (status_of(frame).plough_moved) pt_plough.x + 30 else pt_plough.x;
        // Heavy iron beam & share
        w.fill_rect(plough_draw_x - 30, pt_plough.y - 8, 60, 16, Color{ .r = 65, .g = 55, .b = 50 });
        w.draw_rect_outline(plough_draw_x - 30, pt_plough.y - 8, 60, 16, Color{ .r = 95, .g = 85, .b = 80 });
        // Iron blade point
        w.fill_rect(plough_draw_x + 20, pt_plough.y + 4, 16, 14, Color{ .r = 45, .g = 40, .b = 38 });
        // Wooden handles
        w.draw_line(plough_draw_x - 24, pt_plough.y - 8, plough_draw_x - 45, pt_plough.y - 32, Color{ .r = 130, .g = 85, .b = 45 });
        w.draw_line(plough_draw_x - 18, pt_plough.y - 8, plough_draw_x - 39, pt_plough.y - 32, Color{ .r = 130, .g = 85, .b = 45 });

        // Dynamic Rope Drawing between Stake, Plough, and BillyGoat
        var goat_pt: ?Point = null;
        for (frame.entities[0..frame.entity_count]) |e| {
            if (std.mem.eql(u8, e.get_name(), "BillyGoat")) {
                goat_pt = world_to_screen(e.x, e.y, w.width, w.height);
                break;
            }
        }
        if (goat_pt) |gpt| {
            if (status_of(frame).goat_is_tangled) {
                // Rope loops around the farm plough then connects to goat
                w.draw_line(pt_tether.x, pt_tether.y - 14, plough_draw_x, pt_plough.y, Palette.rope_color);
                w.draw_circle_outline(plough_draw_x, pt_plough.y, 14, Palette.rope_color);
                w.draw_circle_outline(plough_draw_x, pt_plough.y, 18, Palette.rope_color);
                w.draw_line(plough_draw_x, pt_plough.y, gpt.x, gpt.y, Palette.rope_color);
                w.draw_text("[ROPE TANGLED ON PLOUGH!]", plough_draw_x - 60, pt_plough.y - 48, 1, Color.status_running);
            } else {
                // Direct rope from stake to goat
                w.draw_line(pt_tether.x, pt_tether.y - 14, gpt.x, gpt.y, Palette.rope_color);
            }
        }

        // Title
        w.draw_text("LOCHMARNE CASTLE COURTYARD - IRELAND", yard_x + 16, yard_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(PEAGRAM'S EXCAVATION PIT * TETHERED BILLY GOAT * IRON PLOUGH)", yard_x + 16, yard_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_templar_crypt_scene) {
        // Subterranean Templar Dig Crypt (P20-02, D-023)
        w.fill_rect(0, 0, w.width, w.height, Palette.crypt_wall);

        const crypt_x: i32 = 40;
        const crypt_y: i32 = 110;
        const crypt_w: i32 = w.width - 80;
        const crypt_h: i32 = w.height - 210;

        w.fill_rect(crypt_x, crypt_y, crypt_w, crypt_h, Color{ .r = 28, .g = 25, .b = 24 });
        w.draw_rect_outline(crypt_x, crypt_y, crypt_w, crypt_h, Color{ .r = 68, .g = 64, .b = 60 });

        // Flagstone crypt floor
        w.fill_rect(crypt_x, crypt_y + crypt_h - 110, crypt_w, 110, Color{ .r = 44, .g = 40, .b = 38 });
        var fx: i32 = crypt_x;
        while (fx < crypt_x + crypt_w) : (fx += 80) {
            w.draw_line(fx, crypt_y + crypt_h - 110, fx, crypt_y + crypt_h, Color{ .r = 30, .g = 28, .b = 26 });
        }

        // Gothic vaulted ceiling arches
        var ax: i32 = crypt_x + 160;
        while (ax < crypt_x + crypt_w - 100) : (ax += 240) {
            w.fill_rect(ax - 10, crypt_y + 40, 20, crypt_h - 150, Color{ .r = 50, .g = 46, .b = 44 });
            w.draw_circle_outline(ax, crypt_y + 70, 70, Color{ .r = 75, .g = 70, .b = 66 });
        }

        // Flaming torch sconces on walls casting amber glow
        const torch_l_x = crypt_x + 100;
        const torch_r_x = crypt_x + crypt_w - 140;
        const torch_y = crypt_y + 90;
        // Left torch
        w.fill_circle(torch_l_x, torch_y, 22, Color{ .r = 245, .g = 158, .b = 11, .a = 70 });
        w.fill_circle(torch_l_x, torch_y, 12, Color{ .r = 251, .g = 191, .b = 36 });
        w.fill_circle(torch_l_x, torch_y - 4, 7, Color{ .r = 239, .g = 68, .b = 68 });
        w.fill_rect(torch_l_x - 3, torch_y + 6, 6, 24, Color.black);
        // Right torch
        w.fill_circle(torch_r_x, torch_y, 22, Color{ .r = 245, .g = 158, .b = 11, .a = 70 });
        w.fill_circle(torch_r_x, torch_y, 12, Color{ .r = 251, .g = 191, .b = 36 });
        w.fill_circle(torch_r_x, torch_y - 4, 7, Color{ .r = 239, .g = 68, .b = 68 });
        w.fill_rect(torch_r_x - 3, torch_y + 6, 6, 24, Color.black);

        // Carved Templar Mural on rear stone wall (depicting Knight & Cross)
        const mural_x = crypt_x + crypt_w - 320;
        const mural_y = crypt_y + 50;
        w.fill_rect(mural_x, mural_y, 180, 140, Color{ .r = 55, .g = 50, .b = 48 });
        w.draw_rect_outline(mural_x, mural_y, 180, 140, Color{ .r = 120, .g = 115, .b = 110 });
        // Templar Cross pattée (Crimson)
        const cx_m = mural_x + 90;
        const cy_m = mural_y + 60;
        w.fill_rect(cx_m - 8, cy_m - 28, 16, 56, Palette.templar_red);
        w.fill_rect(cx_m - 28, cy_m - 8, 56, 16, Palette.templar_red);
        w.fill_circle(cx_m, cy_m, 14, Palette.templar_red);
        w.draw_text("TEMPLAR MURAL", mural_x + 20, mural_y + 115, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // Stone Altar in crypt center (at AltarMark world_x = 20)
        const pt_altar = world_to_screen(20, 0, w.width, w.height);
        const altar_x = pt_altar.x - 70;
        const altar_y = crypt_y + crypt_h - 180;
        w.fill_rect(altar_x, altar_y, 140, 70, Color{ .r = 90, .g = 85, .b = 82 });
        w.draw_rect_outline(altar_x, altar_y, 140, 70, Color{ .r = 140, .g = 135, .b = 130 });
        w.fill_rect(altar_x - 10, altar_y - 10, 160, 14, Color{ .r = 110, .g = 105, .b = 102 });
        w.draw_rect_outline(altar_x - 10, altar_y - 10, 160, 14, Color{ .r = 160, .g = 155, .b = 150 });
        // Holy chalice relief on altar
        w.fill_circle(pt_altar.x, altar_y + 24, 8, Color{ .r = 251, .g = 191, .b = 36 });
        w.fill_rect(pt_altar.x - 2, altar_y + 28, 4, 14, Color{ .r = 251, .g = 191, .b = 36 });
        w.draw_text("TEMPLAR ALTAR", altar_x + 16, altar_y + 48, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // Excavation ladder on the left (at CryptLadder world_x = 4)
        const pt_ladder = world_to_screen(4, 0, w.width, w.height);
        const lad_x = pt_ladder.x - 20;
        w.fill_rect(lad_x, crypt_y, 8, crypt_h - 50, Color{ .r = 130, .g = 80, .b = 40 });
        w.fill_rect(lad_x + 32, crypt_y, 8, crypt_h - 50, Color{ .r = 130, .g = 80, .b = 40 });
        var ly: i32 = crypt_y + 10;
        while (ly < crypt_y + crypt_h - 50) : (ly += 16) {
            w.fill_rect(lad_x, ly, 40, 4, Color{ .r = 160, .g = 105, .b = 55 });
        }
        w.draw_text("LADDER UP", lad_x - 10, crypt_y + crypt_h - 40, 1, Color.wp_hover);

        // Title
        w.draw_text("SUBTERRANEAN TEMPLAR DIG CRYPT", crypt_x + 16, crypt_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(MEDIEVAL KNIGHTS TEMPLAR MURAL * CHALICE ALTAR * EXCAVATION LADDER)", crypt_x + 16, crypt_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_dott_past_scene) {
        // 1790 Colonial Workshop (P21-03, D-025)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 45, .g = 30, .b = 20 });

        const shop_x: i32 = 40;
        const shop_y: i32 = 110;
        const shop_w: i32 = w.width - 80;
        const shop_h: i32 = w.height - 210;

        // Wood panel workshop room
        w.fill_rect(shop_x, shop_y, shop_w, shop_h, Palette.colonial_wood);
        w.draw_rect_outline(shop_x, shop_y, shop_w, shop_h, Color{ .r = 139, .g = 90, .b = 43 });

        // Hardwood floorboards
        w.fill_rect(shop_x, shop_y + shop_h - 100, shop_w, 100, Color{ .r = 74, .g = 48, .b = 32 });
        var plank_x: i32 = shop_x;
        while (plank_x < shop_x + shop_w) : (plank_x += 70) {
            w.draw_line(plank_x, shop_y + shop_h - 100, plank_x, shop_y + shop_h, Color{ .r = 50, .g = 32, .b = 20 });
        }

        // Brick fireplace hearth on left
        w.fill_rect(shop_x + 30, shop_y + 40, 140, shop_h - 140, Palette.colonial_hearth);
        w.draw_rect_outline(shop_x + 30, shop_y + 40, 140, shop_h - 140, Color{ .r = 100, .g = 40, .b = 20 });
        w.fill_rect(shop_x + 50, shop_y + shop_h - 180, 100, 80, Color.black);
        // Glowing fire embers
        w.fill_circle(shop_x + 100, shop_y + shop_h - 130, 20, Color{ .r = 245, .g = 158, .b = 11 });
        w.fill_circle(shop_x + 100, shop_y + shop_h - 135, 12, Color{ .r = 239, .g = 68, .b = 68 });
        w.fill_circle(shop_x + 100, shop_y + shop_h - 140, 6, Color{ .r = 250, .g = 204, .b = 21 });

        // Colonial window looking out to Kumquat/Cherry tree lawn
        const win_x = shop_x + shop_w - 280;
        const win_y = shop_y + 30;
        w.fill_rect(win_x, win_y, 220, 150, Color{ .r = 125, .g = 185, .b = 240 }); // Sky
        w.fill_rect(win_x, win_y + 90, 220, 60, Color{ .r = 34, .g = 120, .b = 40 }); // Green lawn
        w.draw_rect_outline(win_x, win_y, 220, 150, Color.white);
        w.draw_line(win_x + 110, win_y, win_x + 110, win_y + 150, Color.white);
        w.draw_line(win_x, win_y + 75, win_x + 220, win_y + 75, Color.white);

        // Tree seen through window
        if (status_of(frame).dott_tree_chopped) {
            w.fill_rect(win_x + 100, win_y + 115, 20, 25, Color{ .r = 120, .g = 75, .b = 35 });
            w.fill_circle(win_x + 110, win_y + 115, 10, Color{ .r = 160, .g = 105, .b = 55 });
            w.draw_text("[TREE CHOPPED!]", win_x + 30, win_y + 20, 1, Color{ .r = 250, .g = 204, .b = 21 });
        } else {
            w.fill_rect(win_x + 105, win_y + 70, 10, 50, Color{ .r = 100, .g = 60, .b = 25 });
            w.fill_circle(win_x + 110, win_y + 55, 30, Color{ .r = 22, .g = 101, .b = 52 });
            w.fill_circle(win_x + 95, win_y + 45, 4, Color{ .r = 220, .g = 38, .b = 38 });
            w.fill_circle(win_x + 120, win_y + 50, 4, Color{ .r = 220, .g = 38, .b = 38 });
            w.fill_circle(win_x + 105, win_y + 65, 4, Color{ .r = 220, .g = 38, .b = 38 });
        }

        // Chrono-Toilet 1790 (Wooden outhouse booth)
        const pt_toilet = world_to_screen(80, 0, w.width, w.height);
        const t_x = pt_toilet.x - 30;
        const t_y = shop_y + shop_h - 180;
        w.fill_rect(t_x, t_y, 60, 90, Color{ .r = 105, .g = 65, .b = 35 });
        w.draw_rect_outline(t_x, t_y, 60, 90, Color{ .r = 150, .g = 100, .b = 50 });
        w.fill_circle(t_x + 30, t_y + 25, 8, Color{ .r = 250, .g = 204, .b = 21 });
        w.fill_circle(t_x + 34, t_y + 25, 6, Color{ .r = 105, .g = 65, .b = 35 });
        if (status_of(frame).dott_battery_charged) {
            w.draw_text("[POWERED]", t_x - 4, t_y - 16, 1, Color.status_running);
        }

        // Title
        w.draw_text("COLONIAL WORKSHOP - 1790", shop_x + 16, shop_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(HOAGIE * GEORGE WASHINGTON * BETSY ROSS * TIME CAPSULE)", shop_x + 16, shop_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_dott_present_scene) {
        // 1993 Motel Lobby (P21-03, D-025)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 20, .g = 30, .b = 40 });

        const motel_x: i32 = 40;
        const motel_y: i32 = 110;
        const motel_w: i32 = w.width - 80;
        const motel_h: i32 = w.height - 210;

        // 90s motel wallpaper & carpet
        w.fill_rect(motel_x, motel_y, motel_w, motel_h, Palette.motel_teal);
        w.draw_rect_outline(motel_x, motel_y, motel_w, motel_h, Color{ .r = 45, .g = 212, .b = 191 });

        // Geometric 90s wallpaper stripes
        var stripe_x: i32 = motel_x;
        while (stripe_x < motel_x + motel_w) : (stripe_x += 60) {
            w.draw_line(stripe_x, motel_y, stripe_x + 30, motel_y + motel_h - 100, Color{ .r = 15, .g = 118, .b = 110 });
        }

        // Motel carpet floor (magenta & blue pattern)
        w.fill_rect(motel_x, motel_y + motel_h - 100, motel_w, 100, Color{ .r = 112, .g = 26, .b = 117 });
        var carpet_x: i32 = motel_x;
        while (carpet_x < motel_x + motel_w) : (carpet_x += 40) {
            w.fill_rect(carpet_x, motel_y + motel_h - 60, 20, 20, Color{ .r = 134, .g = 25, .b = 143 });
        }

        // Reception Desk with counter bell
        const desk_x = motel_x + 80;
        const desk_y = motel_y + motel_h - 160;
        w.fill_rect(desk_x, desk_y, 160, 70, Color{ .r = 120, .g = 53, .b = 15 });
        w.draw_rect_outline(desk_x, desk_y, 160, 70, Color{ .r = 180, .g = 83, .b = 9 });
        w.fill_circle(desk_x + 40, desk_y - 6, 6, Color{ .r = 250, .g = 204, .b = 21 }); // Brass bell
        w.draw_text("REGISTRATION", desk_x + 20, desk_y + 25, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // Flyer rack
        w.fill_rect(desk_x + 180, desk_y - 20, 40, 90, Color{ .r = 75, .g = 85, .b = 99 });
        w.fill_rect(desk_x + 185, desk_y - 10, 30, 20, Palette.tentacle_purple);
        w.draw_text("FLYERS", desk_x + 182, desk_y + 35, 1, Color.white);

        // Chrono-Toilet 1993 (Public stall)
        const pt_toilet = world_to_screen(60, 0, w.width, w.height);
        const ct_x = pt_toilet.x - 30;
        const ct_y = motel_y + motel_h - 180;
        w.fill_rect(ct_x, ct_y, 60, 90, Color{ .r = 226, .g = 232, .b = 240 });
        w.draw_rect_outline(ct_x, ct_y, 60, 90, Color{ .r = 148, .g = 163, .b = 184 });
        w.fill_rect(ct_x + 20, ct_y + 10, 20, 30, Color{ .r = 203, .g = 213, .b = 225 });

        // Title
        w.draw_text("EDISON MOTEL LOBBY - 1993", motel_x + 16, motel_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(BERNARD * DR. FRED * CHRONO-TOILET * TIME CAPSULE)", motel_x + 16, motel_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_dott_future_scene) {
        // 2193 Dystopian Guard Post (P21-03, D-025)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 15, .g = 10, .b = 25 });

        const post_x: i32 = 40;
        const post_y: i32 = 110;
        const post_w: i32 = w.width - 80;
        const post_h: i32 = w.height - 210;

        // Dystopian metal bunker walls
        w.fill_rect(post_x, post_y, post_w, post_h, Palette.dystopia_metal);
        w.draw_rect_outline(post_x, post_y, post_w, post_h, Color{ .r = 88, .g = 28, .b = 135 });

        // Glowing neon purple conduit lines
        w.draw_line(post_x, post_y + 60, post_x + post_w, post_y + 60, Palette.tentacle_purple);
        w.draw_line(post_x, post_y + post_h - 110, post_x + post_w, post_y + post_h - 110, Palette.tentacle_purple);

        // Giant Tentacle Banner hanging from ceiling
        const banner_x = post_x + post_w - 240;
        w.fill_rect(banner_x, post_y, 140, post_h - 100, Palette.tentacle_purple);
        w.draw_rect_outline(banner_x, post_y, 140, post_h - 100, Color{ .r = 216, .g = 180, .b = 254 });
        w.fill_circle(banner_x + 70, post_y + 50, 16, Palette.tentacle_sucker);
        w.fill_circle(banner_x + 70, post_y + 100, 14, Palette.tentacle_sucker);
        w.fill_circle(banner_x + 70, post_y + 150, 12, Palette.tentacle_sucker);
        w.draw_text("PURPLE EMPIRE", banner_x + 16, post_y + post_h - 130, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // Security Laser Barrier
        w.draw_line(post_x + 180, post_y + 40, post_x + 180, post_y + post_h - 40, Color{ .r = 244, .g = 63, .b = 94 });

        // Roof gutter & flagpole
        w.fill_rect(post_x + 20, post_y + 10, 120, 12, Color{ .r = 71, .g = 85, .b = 105 });
        w.draw_line(post_x + 80, post_y + 10, post_x + 80, post_y - 30, Color.white);
        if (status_of(frame).dott_flag_sewn) {
            w.fill_rect(post_x + 80, post_y - 30, 40, 24, Palette.tentacle_purple);
            w.fill_circle(post_x + 100, post_y - 18, 5, Palette.tentacle_sucker);
            w.draw_text("[TENTACLE FLAG FLYING]", post_x + 30, post_y - 45, 1, Palette.tentacle_sucker);
        }

        // Chrono-Toilet 2193 (Futuristic teleport booth)
        const pt_toilet_fut = world_to_screen(60, 0, w.width, w.height);
        const ft_x = pt_toilet_fut.x - 30;
        const ft_y = post_y + post_h - 180;
        w.fill_rect(ft_x, ft_y, 60, 90, Color{ .r = 40, .g = 35, .b = 60 });
        w.draw_rect_outline(ft_x, ft_y, 60, 90, Palette.tentacle_purple);
        w.fill_rect(ft_x + 15, ft_y + 15, 30, 40, Color{ .r = 168, .g = 85, .b = 247 });
        w.draw_text("CHRONO-2193", ft_x - 6, ft_y - 16, 1, Color{ .r = 216, .g = 180, .b = 254 });

        // Title
        w.draw_text("DYSTOPIAN TENTACLE GUARD POST - 2193", post_x + 16, post_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(LAVERNE * PURPLE TENTACLE GUARD * SECURITY CHECKPOINT)", post_x + 16, post_y + 36, 1, Color.hud_subtext);
    } else if (sc.is_darko_bedroom_scene) {
        // Suburban Bedroom - October 1988 (P31-01, D-027)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 15, .g = 18, .b = 28 });

        const bedr_x: i32 = 40;
        const bedr_y: i32 = 110;
        const bedr_w: i32 = w.width - 80;
        const bedr_h: i32 = w.height - 210;

        // Room walls
        w.fill_rect(bedr_x, bedr_y, bedr_w, bedr_h, Color{ .r = 25, .g = 30, .b = 45 });
        w.draw_rect_outline(bedr_x, bedr_y, bedr_w, bedr_h, Color{ .r = 50, .g = 60, .b = 85 });

        // Hardwood floor
        w.fill_rect(bedr_x, bedr_y + bedr_h - 110, bedr_w, 110, Color{ .r = 45, .g = 35, .b = 30 });
        var plank_x: i32 = bedr_x;
        while (plank_x < bedr_x + bedr_w) : (plank_x += 60) {
            w.draw_line(plank_x, bedr_y + bedr_h - 110, plank_x, bedr_y + bedr_h, Color{ .r = 30, .g = 22, .b = 18 });
        }

        // Window with moonlight
        const win_x = bedr_x + bedr_w - 260;
        const win_y = bedr_y + 30;
        w.fill_rect(win_x, win_y, 200, 140, Color{ .r = 20, .g = 30, .b = 55 });
        w.draw_rect_outline(win_x, win_y, 200, 140, Color{ .r = 140, .g = 160, .b = 200 });
        w.draw_line(win_x + 100, win_y, win_x + 100, win_y + 140, Color{ .r = 140, .g = 160, .b = 200 });
        w.draw_line(win_x, win_y + 70, win_x + 200, win_y + 70, Color{ .r = 140, .g = 160, .b = 200 });
        // Full moon
        w.fill_circle(win_x + 140, win_y + 40, 18, Color{ .r = 230, .g = 240, .b = 255 });

        // Bed with tangled sheets
        w.fill_rect(bedr_x + 30, bedr_y + bedr_h - 170, 150, 80, Color{ .r = 60, .g = 50, .b = 45 });
        w.fill_rect(bedr_x + 35, bedr_y + bedr_h - 160, 140, 60, Color{ .r = 40, .g = 70, .b = 110 });
        w.fill_rect(bedr_x + 40, bedr_y + bedr_h - 180, 50, 25, Color{ .r = 220, .g = 225, .b = 235 });

        // Smashed ceiling hole from falling Jet Engine if anomaly active
        if (status_of(frame).tangent_active) {
            w.fill_circle(bedr_x + @divTrunc(bedr_w, 2), bedr_y + 10, 50, Color{ .r = 10, .g = 12, .b = 20 });
            w.draw_circle_outline(bedr_x + @divTrunc(bedr_w, 2), bedr_y + 10, 52, Palette.tangent_glow);
            w.draw_line(bedr_x + @divTrunc(bedr_w, 2) - 40, bedr_y + 10, bedr_x + @divTrunc(bedr_w, 2) + 40, bedr_y + 35, Color{ .r = 90, .g = 60, .b = 30 });
        }

        // Title
        w.draw_text("MIDDLESEX SUBURBAN BEDROOM - OCTOBER 1988", bedr_x + 16, bedr_y + 16, 2, Color{ .r = 224, .g = 242, .b = 254 });
        w.draw_text("(DONNIE * FRANK THE DEMONIC RABBIT * BEDROOM DESK * JET ENGINE IMPACT)", bedr_x + 16, bedr_y + 36, 1, Palette.tangent_glow);
    } else if (sc.is_darko_school_scene) {
        // Middlesex High School (P31-01, D-027)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 20, .g = 24, .b = 28 });

        const sch_x: i32 = 40;
        const sch_y: i32 = 110;
        const sch_w: i32 = w.width - 80;
        const sch_h: i32 = w.height - 210;

        // Hallway walls
        w.fill_rect(sch_x, sch_y, sch_w, sch_h, Color{ .r = 40, .g = 45, .b = 55 });
        w.draw_rect_outline(sch_x, sch_y, sch_w, sch_h, Color{ .r = 70, .g = 80, .b = 95 });

        // Checkered linoleum hallway floor
        w.fill_rect(sch_x, sch_y + sch_h - 110, sch_w, 110, Color{ .r = 50, .g = 55, .b = 65 });
        var tile_x: i32 = sch_x;
        var tile_col_idx: usize = 0;
        while (tile_x < sch_x + sch_w) : (tile_x += 40) {
            const is_dark_tile = (tile_col_idx % 2 == 0);
            const tile_color = if (is_dark_tile) Color{ .r = 35, .g = 40, .b = 48 } else Color{ .r = 65, .g = 70, .b = 80 };
            w.fill_rect(tile_x, sch_y + sch_h - 110, 40, 110, tile_color);
            tile_col_idx += 1;
        }

        // Green metal lockers along back wall
        var locker_x: i32 = sch_x + 30;
        while (locker_x < sch_x + sch_w - 60) : (locker_x += 35) {
            w.fill_rect(locker_x, sch_y + 40, 30, sch_h - 160, Color{ .r = 30, .g = 65, .b = 50 });
            w.draw_rect_outline(locker_x, sch_y + 40, 30, sch_h - 160, Color{ .r = 20, .g = 45, .b = 35 });
            // Vents and handle
            w.draw_line(locker_x + 5, sch_y + 55, locker_x + 25, sch_y + 55, Color{ .r = 20, .g = 45, .b = 35 });
            w.draw_line(locker_x + 5, sch_y + 60, locker_x + 25, sch_y + 60, Color{ .r = 20, .g = 45, .b = 35 });
            w.fill_circle(locker_x + 22, sch_y + 110, 2, Color{ .r = 180, .g = 190, .b = 200 });
        }

        // School Banner
        const ban_w: i32 = 320;
        const ban_x = sch_x + @divTrunc(sch_w - ban_w, 2);
        w.fill_rect(ban_x, sch_y + 10, ban_w, 26, Color{ .r = 15, .g = 75, .b = 40 });
        w.draw_rect_outline(ban_x, sch_y + 10, ban_w, 26, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_text("MIDDLESEX HIGH - HOME OF THE CAROUSEL BRONCOS", ban_x + 12, sch_y + 16, 1, Color{ .r = 254, .g = 240, .b = 138 });

        // Water flooding if pipe broken
        if (status_of(frame).darko_water_flooded) {
            w.fill_rect(sch_x, sch_y + sch_h - 40, sch_w, 40, Color{ .r = 56, .g = 189, .b = 248, .a = 150 });
            w.draw_line(sch_x, sch_y + sch_h - 40, sch_x + sch_w, sch_y + sch_h - 40, Color{ .r = 224, .g = 242, .b = 254 });
            w.draw_text("[WATER MAIN BURST - HIGH SCHOOL FLOODED!]", sch_x + 30, sch_y + sch_h - 28, 1, Color.white);
        }

        // Title
        w.draw_text("MIDDLESEX HIGH SCHOOL - MAIN CORRIDOR", sch_x + 16, sch_y + 16, 2, Color{ .r = 224, .g = 242, .b = 254 });
        w.draw_text("(DONNIE * GRETCHEN * LOCKERS * WATER MAIN PIPE * BRONCO STATUE)", sch_x + 16, sch_y + 36, 1, Palette.tangent_glow);
    } else if (sc.is_darko_vortex_scene) {
        // Tangent Vortex Overlook Ridge (P31-01, D-027)
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 10, .g = 6, .b = 20 });

        const vr_x: i32 = 40;
        const vr_y: i32 = 110;
        const vr_w: i32 = w.width - 80;
        const vr_h: i32 = w.height - 210;

        // Night mountain landscape
        w.fill_rect(vr_x, vr_y, vr_w, vr_h, Color{ .r = 18, .g = 12, .b = 35 });
        w.draw_rect_outline(vr_x, vr_y, vr_w, vr_h, Color.vortex_purple);

        // Grassy ridge hill
        w.fill_rect(vr_x, vr_y + vr_h - 90, vr_w, 90, Color{ .r = 25, .g = 40, .b = 30 });

        // Swirling Tangent Vortex in night sky
        const vortex_cx = vr_x + @divTrunc(vr_w, 2);
        const vortex_cy = vr_y + 80;
        w.fill_circle(vortex_cx, vortex_cy, 65, Color{ .r = 50, .g = 15, .b = 85 });
        w.fill_circle(vortex_cx, vortex_cy, 45, Color{ .r = 88, .g = 28, .b = 135 });
        w.fill_circle(vortex_cx, vortex_cy, 25, Color.vortex_purple);
        w.fill_circle(vortex_cx, vortex_cy, 12, Color{ .r = 224, .g = 242, .b = 254 });
        w.draw_circle_outline(vortex_cx, vortex_cy, 75, Palette.tangent_glow);
        w.draw_circle_outline(vortex_cx, vortex_cy, 95, Color{ .r = 168, .g = 85, .b = 247 });

        // Telephone poles on ridge
        w.draw_line(vr_x + 80, vr_y + vr_h - 140, vr_x + 80, vr_y + vr_h - 40, Color{ .r = 45, .g = 35, .b = 30 });
        w.draw_line(vr_x + 65, vr_y + vr_h - 130, vr_x + 95, vr_y + vr_h - 130, Color{ .r = 45, .g = 35, .b = 30 });
        w.draw_line(vr_x + vr_w - 100, vr_y + vr_h - 140, vr_x + vr_w - 100, vr_y + vr_h - 40, Color{ .r = 45, .g = 35, .b = 30 });
        w.draw_line(vr_x + vr_w - 115, vr_y + vr_h - 130, vr_x + vr_w - 85, vr_y + vr_h - 130, Color{ .r = 45, .g = 35, .b = 30 });
        w.draw_line(vr_x + 80, vr_y + vr_h - 130, vr_x + vr_w - 100, vr_y + vr_h - 130, Color{ .r = 60, .g = 50, .b = 45 });

        // Title
        w.draw_text("TANGENT VORTEX OVERLOOK RIDGE - MIDNIGHT", vr_x + 16, vr_y + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
        w.draw_text("(ROBERTA SPARROW * MAILBOX 'CELLAR DOOR' * ATMOSPHERIC TIME PORTAL)", vr_x + 16, vr_y + 36, 1, Palette.tangent_glow);
    } else {
        // 1. Clear background
        w.fill_rect(0, 0, w.width, w.height, Palette.tavern_bg);

        // 2. Render Rooms (Tavern Hall & Wine Cellar side-by-side)
        const tavern_rect_x = 100;
        const tavern_rect_y = 120;
        const tavern_rect_w = 480;
        const tavern_rect_h = 320;
        w.fill_rect(tavern_rect_x, tavern_rect_y, tavern_rect_w, tavern_rect_h, Palette.tavern_room);
        w.draw_rect_outline(tavern_rect_x, tavern_rect_y, tavern_rect_w, tavern_rect_h, Color.panel_border);
        w.draw_text("TAVERN - COMMON ROOM", tavern_rect_x + 16, tavern_rect_y + 16, 2, Color.hud_subtext);

        const cellar_rect_x = 600;
        const cellar_rect_y = 120;
        const cellar_rect_w = 260;
        const cellar_rect_h = 320;
        w.fill_rect(cellar_rect_x, cellar_rect_y, cellar_rect_w, cellar_rect_h, Palette.cellar_room);
        w.draw_rect_outline(cellar_rect_x, cellar_rect_y, cellar_rect_w, cellar_rect_h, Palette.cellar_border);
        w.draw_text("WINE CELLAR", cellar_rect_x + 16, cellar_rect_y + 16, 2, Color.hud_subtext);
    }
    return true;
}

fn render_bell_tower(w: *DisplayWindow, frame: *const RenderFrame, belfry: bool) void {
        const stone = Color{ .r = 52, .g = 50, .b = 60 };
        const stone_dark = Color{ .r = 34, .g = 33, .b = 42 };
        const mortar = Color{ .r = 70, .g = 68, .b = 78 };
        const iron = Color{ .r = 88, .g = 92, .b = 100 };
        const ember = Color{ .r = 249, .g = 115, .b = 22 };
        const flame = Color{ .r = 253, .g = 224, .b = 71 };
        const bronze = Color{ .r = 180, .g = 130, .b = 60 };
        const rx: i32 = 40;
        const ry: i32 = 110;
        const rw: i32 = w.width - 80;
        const rh: i32 = w.height - 220;

        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 14, .g = 14, .b = 22 });
        w.fill_rect(rx, ry, rw, rh, stone);

        if (belfry) {
            // Night sky through three open arches
            var a: i32 = 0;
            while (a < 3) : (a += 1) {
                const ax = rx + 120 + a * 340;
                // Arch top stays inside the room rectangle (circle top = ry + 10)
                w.fill_rect(ax, ry + 110, 200, 120, Color{ .r = 22, .g = 30, .b = 64 });
                w.fill_circle(ax + 100, ry + 110, 100, Color{ .r = 22, .g = 30, .b = 64 });
                w.fill_circle(ax + 40 + a * 50, ry + 90, 2, Color.white);
                w.fill_circle(ax + 150 - a * 30, ry + 140, 1, Color.white);
            }
        }

        // Stone courses
        var y: i32 = ry + 30;
        while (y < ry + rh) : (y += 34) {
            w.draw_line(rx, y, rx + rw, y, mortar);
        }
        const floor = world_to_screen(0, 8, w.width, w.height);
        w.fill_rect(rx, floor.y, rw, ry + rh - floor.y, stone_dark);
        w.draw_line(rx, floor.y, rx + rw, floor.y, mortar);
        w.draw_rect_outline(rx, ry, rw, rh, mortar);

        if (!belfry) {
            // Doorway arch
            const door = world_to_screen(1, 0, w.width, w.height);
            w.fill_rect(door.x - 30, door.y - 70, 60, floor.y - door.y + 70, Color{ .r = 20, .g = 24, .b = 40 });
            w.fill_circle(door.x, door.y - 70, 30, Color{ .r = 20, .g = 24, .b = 40 });

            // Lantern: always lit, its flame the first teacher
            const lan = world_to_screen(4, -6, w.width, w.height);
            w.draw_line(lan.x, lan.y - 30, lan.x, lan.y - 12, iron);
            w.fill_rect(lan.x - 9, lan.y - 12, 18, 24, iron);
            w.fill_rect(lan.x - 6, lan.y - 9, 12, 18, Color{ .r = 120, .g = 70, .b = 20 });
            w.fill_circle(lan.x, lan.y + 1, 4, flame);

            // Brazier: cold coals or a fire whose glow climbs the wall
            const br = world_to_screen(13, -1, w.width, w.height);
            if (status_of(frame).bell_brazier_lit) {
                w.fill_circle(br.x, br.y - 20, 60, Color{ .r = 120, .g = 60, .b = 20, .a = 70 });
            }
            w.fill_rect(br.x - 30, br.y, 60, 12, iron);
            w.draw_line(br.x - 20, br.y + 12, br.x - 26, floor.y, iron);
            w.draw_line(br.x + 20, br.y + 12, br.x + 26, floor.y, iron);
            if (status_of(frame).bell_brazier_lit) {
                w.fill_circle(br.x - 12, br.y - 8, 10, ember);
                w.fill_circle(br.x + 10, br.y - 10, 12, ember);
                w.fill_circle(br.x, br.y - 20, 9, flame);
            } else {
                w.fill_circle(br.x - 10, br.y - 2, 6, Color{ .r = 60, .g = 55, .b = 55 });
                w.fill_circle(br.x + 8, br.y - 3, 7, Color{ .r = 50, .g = 48, .b = 48 });
            }

            // Iron gate wound with ivy
            const gate = world_to_screen(24, -8, w.width, w.height);
            var bar: i32 = -36;
            while (bar <= 36) : (bar += 12) {
                w.draw_line(gate.x + bar, gate.y - 40, gate.x + bar, floor.y, iron);
            }
            w.draw_line(gate.x - 40, gate.y - 40, gate.x + 40, gate.y - 40, iron);
            const leaf = Color{ .r = 52, .g = 130, .b = 60 };
            var v: i32 = 0;
            while (v < 8) : (v += 1) {
                const vy = gate.y - 36 + v * 18;
                const vx = gate.x + (if (@mod(v, 2) == 0) @as(i32, -20) else 20);
                w.draw_line(gate.x, vy, vx, vy + 9, leaf);
                w.fill_circle(vx, vy + 9, 4, leaf);
            }

            // Stairwell: black until the brazier lights it
            const st = world_to_screen(36, -6, w.width, w.height);
            w.fill_rect(st.x - 40, st.y - 50, 80, floor.y - st.y + 50, Color{ .r = 8, .g = 8, .b = 12 });
            if (status_of(frame).bell_brazier_lit) {
                var step: i32 = 0;
                while (step < 6) : (step += 1) {
                    const sy = floor.y - 12 - step * 16;
                    w.fill_rect(st.x - 34 + step * 4, sy, 60 - step * 6, 6, Color{ .r = 110, .g = 80, .b = 50 });
                }
            }

            w.draw_text("BELL TOWER - BASE", rx + 16, ry + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
            w.draw_text("(LANTERN * BRAZIER * IVY GATE * STAIRWELL)", rx + 16, ry + 36, 1, Color.hud_subtext);
        } else {
            // Great bell on its beam; motion arcs while it rings
            const bell = world_to_screen(21, -10, w.width, w.height);
            w.fill_rect(bell.x - 90, bell.y - 60, 180, 10, Color{ .r = 90, .g = 60, .b = 35 });
            const sway: i32 = if (status_of(frame).bell_ringing) 12 else 0;
            const bx = bell.x + sway;
            w.draw_line(bell.x, bell.y - 50, bx, bell.y - 34, iron);
            var row: i32 = 0;
            while (row < 50) : (row += 2) {
                const half = 18 + @divTrunc(row * 22, 50);
                w.draw_line(bx - half, bell.y - 34 + row, bx + half, bell.y - 34 + row, bronze);
            }
            w.fill_rect(bx - 44, bell.y + 16, 88, 6, Color{ .r = 150, .g = 105, .b = 45 });
            w.fill_circle(bx, bell.y + 26, 6, Color{ .r = 120, .g = 85, .b = 40 });
            if (status_of(frame).bell_ringing) {
                var arc: i32 = 0;
                while (arc < 3) : (arc += 1) {
                    w.draw_circle_outline(bx, bell.y, 70 + arc * 18, Color{ .r = 253, .g = 224, .b = 71, .a = 120 });
                }
            }

            // Chain wound around the clapper, or lying slack on the boards
            const ch = world_to_screen(16, -2, w.width, w.height);
            if (!status_of(frame).bell_chain_loosed) {
                var link: i32 = 0;
                while (link < 7) : (link += 1) {
                    const lx = bx - 40 + link * 14;
                    w.draw_circle_outline(lx, bell.y + 26 + @mod(link, 2) * 6, 6, iron);
                }
                w.draw_line(bx + 44, bell.y + 30, ch.x + 40, floor.y, iron);
            } else {
                var link: i32 = 0;
                while (link < 8) : (link += 1) {
                    w.draw_circle_outline(ch.x - 50 + link * 12, floor.y - 6, 5, iron);
                }
            }

            // Tuning fork: hidden under the chain, glinting once freed, gone when taken
            if (status_of(frame).bell_chain_loosed and !status_of(frame).bell_fork_taken) {
                const fk = world_to_screen(10, 3, w.width, w.height);
                w.draw_line(fk.x, fk.y + 8, fk.x, fk.y - 4, bronze);
                w.draw_line(fk.x - 4, fk.y - 4, fk.x - 4, fk.y - 16, bronze);
                w.draw_line(fk.x + 4, fk.y - 4, fk.x + 4, fk.y - 16, bronze);
                w.draw_line(fk.x - 4, fk.y - 4, fk.x + 4, fk.y - 4, bronze);
                w.fill_circle(fk.x + 7, fk.y - 18, 2, Color.white);
            }

            // Beacon basket on the parapet
            const bc = world_to_screen(36, -8, w.width, w.height);
            if (status_of(frame).bell_beacon_lit) {
                w.fill_circle(bc.x, bc.y - 16, 70, Color{ .r = 120, .g = 60, .b = 20, .a = 70 });
            }
            w.draw_line(bc.x, bc.y + 14, bc.x, floor.y, iron);
            w.fill_rect(bc.x - 24, bc.y, 48, 14, iron);
            w.draw_line(bc.x - 24, bc.y, bc.x - 30, bc.y - 10, iron);
            w.draw_line(bc.x + 24, bc.y, bc.x + 30, bc.y - 10, iron);
            if (status_of(frame).bell_beacon_lit) {
                w.fill_circle(bc.x - 8, bc.y - 6, 10, ember);
                w.fill_circle(bc.x + 8, bc.y - 8, 11, ember);
                w.fill_circle(bc.x, bc.y - 22, 9, flame);
            }

            w.draw_text("BELL TOWER - BELFRY", rx + 16, ry + 16, 2, Color{ .r = 254, .g = 240, .b = 138 });
            w.draw_text("(GREAT BELL * IRON CHAIN * BEACON)", rx + 16, ry + 36, 1, Color.hud_subtext);
        }
}

fn prop(w: *DisplayWindow, frame: *const RenderFrame, view: r.PropView) bool {
    const sc = detect(frame);
    const hs = view.hotspot;
    const pt = view.pos;
    const name = hs.get_name();
    // The gallery backdrop draws its trough, torch, tapestry, and door from grid state; its
    // hotspots stay clickable but get no separate art.
    if (sc.is_gallery_scene) return true;
    if (std.mem.indexOf(u8, name, "Fire") != null or std.mem.indexOf(u8, name, "Hearth") != null) {
        // Stone fireplace & fire glow
        w.fill_rect(pt.x - 22, pt.y - 24, 44, 48, Color{ .r = 55, .g = 45, .b = 40 });
        w.draw_rect_outline(pt.x - 22, pt.y - 24, 44, 48, Color{ .r = 85, .g = 70, .b = 60 });
        w.fill_rect(pt.x - 14, pt.y - 10, 28, 30, Color{ .r = 25, .g = 18, .b = 16 });
        w.fill_circle(pt.x, pt.y + 4, 10, Color{ .r = 239, .g = 68, .b = 68 });
        w.fill_circle(pt.x, pt.y + 2, 6, Color{ .r = 245, .g = 158, .b = 11 });
    } else if (std.mem.indexOf(u8, name, "Bar") != null or std.mem.indexOf(u8, name, "Counter") != null) {
        // Polished tavern counter
        w.fill_rect(pt.x - 28, pt.y - 14, 56, 28, Color{ .r = 110, .g = 50, .b = 18 });
        w.draw_rect_outline(pt.x - 28, pt.y - 14, 56, 28, Color{ .r = 145, .g = 75, .b = 30 });
        w.fill_rect(pt.x - 26, pt.y - 12, 52, 4, Color{ .r = 180, .g = 83, .b = 9 });
    } else if (std.mem.indexOf(u8, name, "Cask") != null or std.mem.indexOf(u8, name, "Barrel") != null) {
        // Vintage wine cask
        w.fill_rect(pt.x - 18, pt.y - 22, 36, 44, Color{ .r = 69, .g = 26, .b = 3 });
        w.draw_rect_outline(pt.x - 18, pt.y - 22, 36, 44, Color{ .r = 120, .g = 53, .b = 15 });
        w.draw_line(pt.x - 18, pt.y - 10, pt.x + 18, pt.y - 10, Color{ .r = 140, .g = 140, .b = 150 });
        w.draw_line(pt.x - 18, pt.y + 10, pt.x + 18, pt.y + 10, Color{ .r = 140, .g = 140, .b = 150 });
    } else if (std.mem.indexOf(u8, name, "Flag") != null) {
        // Spitting Competition Distance Flags (P10-03, D-012)
        const flag_x = if (status_of(frame).flags_tampered) pt.x - 70 else pt.x;
        w.fill_rect(flag_x - 2, pt.y - 32, 4, 40, Color{ .r = 217, .g = 119, .b = 6 });
        const fcol = if (status_of(frame).flags_tampered) Palette.flag_tampered else Palette.flag_color;
        w.fill_rect(flag_x + 2, pt.y - 32, 28, 18, fcol);
        w.draw_line(flag_x + 2, pt.y - 14, flag_x + 30, pt.y - 32, Color.white);

        if (status_of(frame).flags_tampered) {
            w.draw_rect_outline(pt.x - 1, pt.y - 30, 2, 38, Color.hud_subtext);
            w.draw_text("[MOVED!]", flag_x - 20, pt.y + 14, 2, Palette.flag_tampered);
        } else {
            w.draw_text("Flags", flag_x - 14, pt.y + 14, 2, Color.hud_text);
        }
    } else if (std.mem.indexOf(u8, name, "Fence") != null or std.mem.indexOf(u8, name, "Hole") != null) {
        // Garden Fence Hole (P14-02, D-016)
        w.fill_rect(pt.x - 20, pt.y - 16, 40, 32, Palette.garden_fence);
        w.fill_rect(pt.x - 12, pt.y - 4, 24, 20, Color.black);
        if (status_of(frame).fence_taped) {
            w.fill_rect(pt.x - 14, pt.y + 4, 28, 6, Color{ .r = 254, .g = 243, .b = 199 });
        }
    } else if (std.mem.indexOf(u8, name, "Door") != null) {
        // Mosely's Door (P14-02, D-016)
        w.fill_rect(pt.x - 16, pt.y - 24, 32, 48, Palette.hotel_door);
        w.draw_rect_outline(pt.x - 16, pt.y - 24, 32, 48, Color{ .r = 180, .g = 120, .b = 50 });
    } else if (std.mem.indexOf(u8, name, "Desk") != null) {
        // Hotel Room Desk (P14-02, D-016)
        w.fill_rect(pt.x - 22, pt.y - 12, 44, 24, Palette.hotel_wainscot);
        w.draw_rect_outline(pt.x - 22, pt.y - 12, 44, 24, Color{ .r = 140, .g = 80, .b = 40 });
    } else if (std.mem.indexOf(u8, name, "Shrub") != null or std.mem.indexOf(u8, name, "Bench") != null) {
        // Garden Lavender Shrub & Potting Bench (P14-02, D-016)
        w.fill_circle(pt.x - 8, pt.y - 4, 14, Color{ .r = 34, .g = 197, .b = 94 });
        w.fill_circle(pt.x + 8, pt.y - 6, 12, Color{ .r = 74, .g = 222, .b = 128 });
        w.fill_circle(pt.x, pt.y - 12, 10, Color{ .r = 168, .g = 85, .b = 247 }); // Lavender blossom
        w.fill_rect(pt.x - 18, pt.y + 6, 36, 10, Color{ .r = 120, .g = 80, .b = 50 }); // Potting bench
    } else if (std.mem.indexOf(u8, name, "Motorcycle") != null) {
        // Motorcycle prop (P14-02, D-016)
        w.fill_rect(pt.x - 20, pt.y - 12, 40, 24, Palette.motorcycle_red);
        w.fill_circle(pt.x - 14, pt.y + 12, 8, Color.black);
        w.fill_circle(pt.x + 14, pt.y + 12, 8, Color.black);
    } else if (std.mem.indexOf(u8, name, "Plough") != null) {
        // Broken Sword Farm Plough (P20-02, D-023)
        const px = if (status_of(frame).plough_moved) pt.x + 25 else pt.x;
        w.fill_rect(px - 18, pt.y - 8, 36, 14, Color{ .r = 65, .g = 55, .b = 50 });
        w.draw_rect_outline(px - 18, pt.y - 8, 36, 14, Color{ .r = 110, .g = 100, .b = 95 });
        w.draw_line(px - 14, pt.y - 8, px - 28, pt.y - 24, Color{ .r = 130, .g = 85, .b = 45 });
        w.draw_line(px - 10, pt.y - 8, px - 24, pt.y - 24, Color{ .r = 130, .g = 85, .b = 45 });
    } else if (std.mem.indexOf(u8, name, "Tether") != null or std.mem.indexOf(u8, name, "Stake") != null) {
        // Tether Stake (P20-02, D-023)
        w.fill_rect(pt.x - 4, pt.y - 14, 8, 28, Color{ .r = 110, .g = 70, .b = 35 });
        w.draw_circle_outline(pt.x, pt.y - 10, 5, Color{ .r = 180, .g = 180, .b = 190 });
    } else if (std.mem.indexOf(u8, name, "Cellar") != null or std.mem.indexOf(u8, name, "Opening") != null) {
        // Cellar Pit opening (P20-02, D-023)
        w.fill_rect(pt.x - 22, pt.y - 14, 44, 28, Color{ .r = 20, .g = 18, .b = 16 });
        w.draw_rect_outline(pt.x - 22, pt.y - 14, 44, 28, Color{ .r = 100, .g = 65, .b = 30 });
        w.fill_rect(pt.x - 8, pt.y - 16, 4, 30, Color{ .r = 140, .g = 90, .b = 45 });
        w.fill_rect(pt.x + 4, pt.y - 16, 4, 30, Color{ .r = 140, .g = 90, .b = 45 });
    } else if (std.mem.indexOf(u8, name, "Mural") != null) {
        // Carved Mural (P20-02, D-023)
        w.fill_rect(pt.x - 24, pt.y - 20, 48, 40, Color{ .r = 60, .g = 55, .b = 52 });
        w.draw_rect_outline(pt.x - 24, pt.y - 20, 48, 40, Color{ .r = 120, .g = 115, .b = 110 });
        w.fill_rect(pt.x - 3, pt.y - 12, 6, 24, Palette.templar_red);
        w.fill_rect(pt.x - 12, pt.y - 3, 24, 6, Palette.templar_red);
    } else if (std.mem.indexOf(u8, name, "Altar") != null) {
        // Crypt Altar (P20-02, D-023)
        w.fill_rect(pt.x - 24, pt.y - 14, 48, 28, Color{ .r = 85, .g = 80, .b = 78 });
        w.draw_rect_outline(pt.x - 24, pt.y - 14, 48, 28, Color{ .r = 140, .g = 135, .b = 130 });
        w.fill_circle(pt.x, pt.y, 5, Color{ .r = 251, .g = 191, .b = 36 });
    } else if (std.mem.indexOf(u8, name, "JetEngine") != null or std.mem.indexOf(u8, name, "Engine") != null) {
        // Artifact of Metal: Jet Engine Cowling (P31-01, P31-03, D-027)
        w.fill_circle(pt.x, pt.y, 22, Color{ .r = 100, .g = 110, .b = 125 });
        w.fill_circle(pt.x, pt.y, 16, Color{ .r = 40, .g = 45, .b = 55 });
        w.fill_circle(pt.x, pt.y, 6, Color{ .r = 160, .g = 170, .b = 185 });
        w.draw_circle_outline(pt.x, pt.y, 22, Color{ .r = 180, .g = 190, .b = 210 });
        // Turbine blades
        w.draw_line(pt.x - 14, pt.y - 14, pt.x + 14, pt.y + 14, Color{ .r = 140, .g = 150, .b = 165 });
        w.draw_line(pt.x + 14, pt.y - 14, pt.x - 14, pt.y + 14, Color{ .r = 140, .g = 150, .b = 165 });
        w.draw_line(pt.x, pt.y - 16, pt.x, pt.y + 16, Color{ .r = 140, .g = 150, .b = 165 });
        w.draw_line(pt.x - 16, pt.y, pt.x + 16, pt.y, Color{ .r = 140, .g = 150, .b = 165 });
        if (status_of(frame).tangent_active) {
            w.draw_circle_outline(pt.x, pt.y, 26, Palette.tangent_glow);
        }
    } else if (std.mem.indexOf(u8, name, "WaterPipe") != null or std.mem.indexOf(u8, name, "Pipe") != null) {
        // High School Water Pipe (P31-03, D-027)
        w.fill_rect(pt.x - 6, pt.y - 20, 12, 40, Color{ .r = 110, .g = 120, .b = 135 });
        w.draw_rect_outline(pt.x - 6, pt.y - 20, 12, 40, Color{ .r = 160, .g = 170, .b = 185 });
        w.fill_rect(pt.x - 10, pt.y - 8, 20, 16, Color{ .r = 90, .g = 100, .b = 115 });
        if (status_of(frame).darko_water_flooded) {
            w.fill_circle(pt.x, pt.y - 14, 8, Palette.tangent_glow);
            w.draw_line(pt.x, pt.y - 14, pt.x - 18, pt.y + 16, Palette.tangent_core);
            w.draw_line(pt.x, pt.y - 14, pt.x + 18, pt.y + 16, Palette.tangent_core);
        }
    } else if (std.mem.indexOf(u8, name, "Axe") != null) {
        // Fire Axe (P31-03, D-027)
        w.draw_line(pt.x - 12, pt.y + 16, pt.x + 12, pt.y - 16, Color{ .r = 140, .g = 95, .b = 50 });
        w.fill_rect(pt.x + 4, pt.y - 20, 12, 10, Color{ .r = 220, .g = 38, .b = 38 });
        w.draw_rect_outline(pt.x + 4, pt.y - 20, 12, 10, Color.white);
    } else if (std.mem.indexOf(u8, name, "Vortex") != null or std.mem.indexOf(u8, name, "Anomaly") != null) {
        // Time Vortex threshold (P31-01, P31-03, D-027)
        w.fill_circle(pt.x, pt.y, 22, Color.vortex_purple);
        w.fill_circle(pt.x, pt.y, 14, Palette.tangent_glow);
        w.fill_circle(pt.x, pt.y, 6, Palette.tangent_core);
        w.draw_circle_outline(pt.x, pt.y, 24, Palette.tangent_core);
    } else if (std.mem.indexOf(u8, name, "Mailbox") != null or std.mem.indexOf(u8, name, "Envelope") != null) {
        // Roberta Sparrow's Mailbox (P31-03, D-027)
        w.fill_rect(pt.x - 4, pt.y - 6, 8, 26, Color{ .r = 75, .g = 85, .b = 95 });
        w.fill_rect(pt.x - 14, pt.y - 22, 28, 16, Color{ .r = 160, .g = 170, .b = 180 });
        w.draw_rect_outline(pt.x - 14, pt.y - 22, 28, 16, Color.white);
        // Red flag
        w.draw_line(pt.x + 12, pt.y - 18, pt.x + 12, pt.y - 28, Color{ .r = 220, .g = 38, .b = 38 });
        w.fill_rect(pt.x + 12, pt.y - 28, 6, 4, Color{ .r = 220, .g = 38, .b = 38 });
    } else if (sc.is_bell_base_scene or sc.is_bell_belfry_scene) {
        // The Bell Tower draws its props in its backdrop (D-030).
    } else {
        return false;
    }
    return true;
}

fn actor(w: *DisplayWindow, frame: *const RenderFrame, view: r.ActorView) bool {
    const e = view.entity;
    const name = e.get_name();
    const layout = view.layout;
    const pt = layout.pos;
    const layout_resolver = view.labels;
    if (std.mem.eql(u8, name, "Cat")) {
        // Cat (Player): Orange token with cat ears
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.cat_color);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Ears
        w.fill_rect(pt.x - 12, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Palette.cat_color);
        w.fill_rect(pt.x + 6, pt.y - ACTOR_SCREEN_RADIUS - 4, 6, 6, Palette.cat_color);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Cat (Player)",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.cat_color),
            .actor_name,
            .actor_name,
        ));

        // Carried Cheese
        if (status_of(frame).cheese_holder == e.entity) {
            w.fill_circle(pt.x + 14, pt.y - 10, 8, Palette.cheese_color);
            w.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
            w.draw_text("Cheese", pt.x + 24, pt.y - 14, 1, Palette.cheese_color);
        }
    } else if (std.mem.eql(u8, name, "Guard")) {
        // Guard: Steel Blue token
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.guard_color);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Shield visor
        w.fill_rect(pt.x - 8, pt.y - 4, 16, 6, Color.white);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Guard",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.guard_color),
            .actor_name,
            .actor_name,
        ));

        // Carried Cheese
        if (status_of(frame).cheese_holder == e.entity) {
            w.fill_circle(pt.x + 14, pt.y - 10, 8, Palette.cheese_color);
            w.draw_circle_outline(pt.x + 14, pt.y - 10, 8, Color.white);
            w.draw_text("Cheese", pt.x + 24, pt.y - 14, 1, Palette.cheese_color);
        }

        // Charmed status
        if (status_of(frame).charmed_target == e.entity) {
            layout_resolver.submit(TextLabel.init(
                "[Charmed!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.cue_alert),
                .actor_status,
                .actor_alert,
            ));
        }
    } else if (std.mem.eql(u8, name, "Bard")) {
        // Bard: Purple token
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.bard_color);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Feather cap / lute indicator
        w.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 6, 4, 8, Color.white);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Bard",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.bard_color),
            .actor_name,
            .actor_name,
        ));
    } else if (std.mem.eql(u8, name, "Guybrush")) {
        // Guybrush (Player): Blonde hair, pirate blue coat
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.guybrush_coat);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Blonde hair
        w.fill_circle(pt.x, pt.y - 8, 8, Palette.guybrush_hair);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Guybrush",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.guybrush_hair),
            .actor_name,
            .actor_name,
        ));

        // Spit Status
        const spit_str = if (status_of(frame).spit_is_thick) "[Thick Spit Ready!]" else "[Spit: Thin]";
        const spit_col = if (status_of(frame).spit_is_thick) Palette.spit_color else Color.hud_subtext;
        const spit_prio: LabelPriority = if (status_of(frame).spit_is_thick) .actor_alert else .actor_status;
        layout_resolver.submit(TextLabel.init(
            spit_str,
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(spit_col),
            .actor_status,
            spit_prio,
        ));
    } else if (std.mem.eql(u8, name, "Organiser")) {
        // Organiser: Velvet red coat, fancy hat
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.organiser_coat);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Cocked hat / feather
        w.fill_rect(pt.x - 8, pt.y - ACTOR_SCREEN_RADIUS - 4, 16, 5, Color.black);
        w.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 8, 4, 6, Palette.guybrush_hair);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Organiser",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.organiser_coat),
            .actor_name,
            .actor_name,
        ));

        // Distracted / watching status
        const org_str = if (status_of(frame).organiser_distracted) "[DISTRACTED!]" else "[Watching]";
        const org_col = if (status_of(frame).organiser_distracted) Color.cue_alert else Color.status_running;
        const org_prio: LabelPriority = if (status_of(frame).organiser_distracted) .actor_alert else .actor_status;
        layout_resolver.submit(TextLabel.init(
            org_str,
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(org_col),
            .actor_status,
            org_prio,
        ));
    } else if (std.mem.eql(u8, name, "Onlookers")) {
        // Onlookers: Crowd of spectator circles
        w.fill_circle(pt.x - 8, pt.y, ACTOR_SCREEN_RADIUS - 2, Palette.onlookers_color);
        w.fill_circle(pt.x + 8, pt.y, ACTOR_SCREEN_RADIUS - 2, Palette.onlookers_color);
        w.fill_circle(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 2, Color{ .r = 140, .g = 100, .b = 160 });
        w.draw_circle_outline(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 2, Color.white);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Onlookers",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.onlookers_color),
            .actor_name,
            .actor_name,
        ));
        if (status_of(frame).organiser_distracted) {
            layout_resolver.submit(TextLabel.init(
                "[Looking Offstage]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.cue_alert),
                .actor_status,
                .actor_alert,
            ));
        }
    } else if (std.mem.eql(u8, name, "George")) {
        // George Stobbart: Leather jacket, middle-parted blonde hair, blue jeans (P20-02, D-023)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.george_jacket);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Blonde hair parted in the middle
        w.fill_circle(pt.x - 4, pt.y - 8, 6, Palette.george_hair);
        w.fill_circle(pt.x + 4, pt.y - 8, 6, Palette.george_hair);
        // Blue shirt collar
        w.fill_rect(pt.x - 5, pt.y + 4, 10, 4, Color{ .r = 70, .g = 130, .b = 200 });

        // Dizzy stars if knocked down
        if (status_of(frame).george_knocked_down) {
            w.fill_circle(pt.x - 12, pt.y - 16, 3, Color{ .r = 250, .g = 204, .b = 21 });
            w.fill_circle(pt.x, pt.y - 20, 4, Color{ .r = 254, .g = 240, .b = 138 });
            w.fill_circle(pt.x + 12, pt.y - 16, 3, Color{ .r = 250, .g = 204, .b = 21 });
        }

        // Label
        layout_resolver.submit(TextLabel.init(
            "George",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.george_hair),
            .actor_name,
            .actor_name,
        ));

        // Status
        if (status_of(frame).george_knocked_down) {
            layout_resolver.submit(TextLabel.init(
                "[KNOCKED DOWN!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.cue_alert),
                .actor_status,
                .actor_alert,
            ));
        } else {
            layout_resolver.submit(TextLabel.init(
                "[Standing]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.hud_subtext),
                .actor_status,
                .actor_status,
            ));
        }
    } else if (std.mem.eql(u8, name, "BillyGoat")) {
        // Billy Goat: Off-white fleece, curved dark horns, goatee beard (P20-02, D-023)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.goat_body);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Dark horns
        w.draw_line(pt.x - 6, pt.y - 8, pt.x - 12, pt.y - 18, Palette.goat_horns);
        w.draw_line(pt.x - 12, pt.y - 18, pt.x - 16, pt.y - 14, Palette.goat_horns);
        w.draw_line(pt.x + 6, pt.y - 8, pt.x + 12, pt.y - 18, Palette.goat_horns);
        w.draw_line(pt.x + 12, pt.y - 18, pt.x + 16, pt.y - 14, Palette.goat_horns);

        // Red collar & ring
        w.fill_rect(pt.x - 8, pt.y - 2, 16, 4, Palette.goat_collar);
        w.fill_circle(pt.x, pt.y + 2, 3, Color{ .r = 180, .g = 180, .b = 190 });

        // Chin goatee beard
        w.fill_rect(pt.x - 2, pt.y + ACTOR_SCREEN_RADIUS - 2, 4, 6, Color{ .r = 210, .g = 205, .b = 195 });

        // Tangled coils if tangled
        if (status_of(frame).goat_is_tangled) {
            w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 3, Palette.rope_color);
            w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 6, Palette.rope_color);
            w.fill_circle(pt.x - 10, pt.y - 18, 3, Color{ .r = 250, .g = 204, .b = 21 });
            w.fill_circle(pt.x + 10, pt.y - 18, 3, Color{ .r = 250, .g = 204, .b = 21 });
        }

        // Label
        layout_resolver.submit(TextLabel.init(
            "Billy Goat",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color.hud_text),
            .actor_name,
            .actor_name,
        ));

        // Status
        if (status_of(frame).goat_is_tangled) {
            layout_resolver.submit(TextLabel.init(
                "[TANGLED IN ROPE!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.status_running),
                .actor_status,
                .actor_alert,
            ));
        } else if (status_of(frame).goat_is_retreating) {
            layout_resolver.submit(TextLabel.init(
                "[RETREATING TO STAKE!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.status_paused),
                .actor_status,
                .actor_alert,
            ));
        } else if (status_of(frame).goat_is_charging) {
            layout_resolver.submit(TextLabel.init(
                "[CHARGING! RAMMING GEORGE!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.cue_alert),
                .actor_status,
                .actor_alert,
            ));
        } else {
            layout_resolver.submit(TextLabel.init(
                "[Guarding Dig Entrance]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.cue_alert),
                .actor_status,
                .actor_status,
            ));
        }
    } else if (std.mem.eql(u8, name, "Hoagie")) {
        // Hoagie: Heavy build, black vest, red backwards cap, long hair (P21-03, D-025)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 2, Color{ .r = 40, .g = 40, .b = 45 });
        w.fill_circle(pt.x, pt.y - 6, ACTOR_SCREEN_RADIUS - 4, Color{ .r = 240, .g = 180, .b = 140 });
        // Red backwards baseball cap
        w.fill_rect(pt.x - 12, pt.y - ACTOR_SCREEN_RADIUS - 4, 24, 8, Palette.hoagie_cap);
        w.fill_rect(pt.x + 8, pt.y - ACTOR_SCREEN_RADIUS, 8, 4, Palette.hoagie_cap);
        // Long brown hair
        w.fill_rect(pt.x - 14, pt.y - 2, 4, 16, Color{ .r = 80, .g = 50, .b = 25 });
        w.fill_rect(pt.x + 10, pt.y - 2, 4, 16, Color{ .r = 80, .g = 50, .b = 25 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 2, Color.white);

        layout_resolver.submit(TextLabel.init("Hoagie", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
    } else if (std.mem.eql(u8, name, "Bernard")) {
        // Bernard: White collared shirt, black tie, glasses (P21-03, D-025)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // Blue suspenders & black tie
        w.fill_rect(pt.x - 2, pt.y - 4, 4, 16, Color.black);
        w.fill_rect(pt.x - 8, pt.y + 2, 2, 14, Palette.bernard_shirt);
        w.fill_rect(pt.x + 6, pt.y + 2, 2, 14, Palette.bernard_shirt);
        // Thick black horn-rimmed glasses
        w.draw_rect_outline(pt.x - 10, pt.y - 10, 8, 7, Color.black);
        w.draw_rect_outline(pt.x + 2, pt.y - 10, 8, 7, Color.black);
        w.draw_line(pt.x - 2, pt.y - 7, pt.x + 2, pt.y - 7, Color.black);

        layout_resolver.submit(TextLabel.init("Bernard", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 2, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
    } else if (std.mem.eql(u8, name, "Laverne")) {
        // Laverne: Spiky blonde hair, cyan dress, wide eyes (P21-03, D-025)
        const dress_col = if (status_of(frame).dott_laverne_disguised) Palette.tentacle_purple else Palette.laverne_dress;
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, dress_col);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // Spiky blonde hair
        w.fill_circle(pt.x, pt.y - 14, 10, Palette.laverne_hair);
        w.fill_rect(pt.x - 14, pt.y - 18, 6, 8, Palette.laverne_hair);
        w.fill_rect(pt.x + 8, pt.y - 18, 6, 8, Palette.laverne_hair);
        // Wide expressive eyes
        w.fill_circle(pt.x - 4, pt.y - 4, 4, Color.white);
        w.fill_circle(pt.x + 4, pt.y - 4, 4, Color.white);
        w.fill_circle(pt.x - 4, pt.y - 4, 2, Color.black);
        w.fill_circle(pt.x + 4, pt.y - 4, 2, Color.black);

        layout_resolver.submit(TextLabel.init("Laverne", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
        if (status_of(frame).dott_laverne_disguised) {
            layout_resolver.submit(TextLabel.init("[DISGUISED AS TENTACLE]", pt.x, pt.y, .below, ACTOR_SCREEN_RADIUS + 4, 1, to_layout(Palette.tentacle_purple), .actor_status, .actor_status));
        }
    } else if (std.mem.eql(u8, name, "Washington") or std.mem.eql(u8, name, "GeorgeWashington")) {
        // George Washington: Powdered wig, continental blue coat, axe (P21-03, D-025)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.washington_coat);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // Powdered white wig with side rolls
        w.fill_circle(pt.x, pt.y - 12, 11, Color{ .r = 240, .g = 240, .b = 245 });
        w.fill_circle(pt.x - 12, pt.y - 8, 6, Color{ .r = 230, .g = 230, .b = 235 });
        w.fill_circle(pt.x + 12, pt.y - 8, 6, Color{ .r = 230, .g = 230, .b = 235 });
        // Gold epaulettes
        w.fill_rect(pt.x - 14, pt.y - 2, 6, 4, Color{ .r = 250, .g = 204, .b = 21 });
        w.fill_rect(pt.x + 8, pt.y - 2, 6, 4, Color{ .r = 250, .g = 204, .b = 21 });
        // Hatchet / Axe in hand
        w.draw_line(pt.x + 12, pt.y + 4, pt.x + 20, pt.y - 10, Color{ .r = 130, .g = 85, .b = 45 });
        w.fill_rect(pt.x + 16, pt.y - 14, 8, 6, Color{ .r = 180, .g = 185, .b = 195 });

        layout_resolver.submit(TextLabel.init("G. Washington", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
    } else if (std.mem.eql(u8, name, "BetsyRoss") or std.mem.eql(u8, name, "Betsy")) {
        // Betsy Ross: White bonnet, maroon gown, apron (P21-03, D-025)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.betsy_dress);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // White ruffled mob cap / bonnet
        w.fill_circle(pt.x, pt.y - 12, 10, Color.white);
        w.draw_circle_outline(pt.x, pt.y - 12, 10, Color{ .r = 210, .g = 215, .b = 225 });
        // White apron
        w.fill_rect(pt.x - 7, pt.y + 2, 14, 12, Color.white);
        // Tailor shears
        w.draw_line(pt.x + 10, pt.y + 6, pt.x + 18, pt.y + 2, Color{ .r = 200, .g = 205, .b = 215 });
        w.draw_line(pt.x + 10, pt.y + 2, pt.x + 18, pt.y + 6, Color{ .r = 200, .g = 205, .b = 215 });

        layout_resolver.submit(TextLabel.init("Betsy Ross", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
    } else if (std.mem.eql(u8, name, "PurpleTentacle") or std.mem.eql(u8, name, "TentacleGuard")) {
        // Purple Tentacle: Conical purple stalk, suction cups, angry brows (P21-03, D-025)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 2, Palette.tentacle_purple);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 2, Color.white);
        // Suction cups
        w.fill_circle(pt.x, pt.y + 8, 4, Palette.tentacle_sucker);
        w.fill_circle(pt.x - 6, pt.y + 2, 3, Palette.tentacle_sucker);
        w.fill_circle(pt.x + 6, pt.y + 2, 3, Palette.tentacle_sucker);
        // Angry red eyes & slant brows
        w.fill_circle(pt.x - 5, pt.y - 4, 3, Color{ .r = 239, .g = 68, .b = 68 });
        w.fill_circle(pt.x + 5, pt.y - 4, 3, Color{ .r = 239, .g = 68, .b = 68 });
        w.draw_line(pt.x - 9, pt.y - 9, pt.x - 2, pt.y - 7, Color.black);
        w.draw_line(pt.x + 9, pt.y - 9, pt.x + 2, pt.y - 7, Color.black);

        layout_resolver.submit(TextLabel.init("Purple Tentacle", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
    } else if (std.mem.eql(u8, name, "Donnie")) {
        // Donnie Darko: Dark disheveled hair, dark grey jacket, chest vector worm anchor node (P31-01, P31-03, D-027)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 55, .g = 60, .b = 75 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // Disheveled dark hair
        w.fill_circle(pt.x, pt.y - 10, 10, Color{ .r = 30, .g = 25, .b = 20 });
        w.fill_rect(pt.x - 12, pt.y - 14, 6, 8, Color{ .r = 30, .g = 25, .b = 20 });
        w.fill_rect(pt.x + 6, pt.y - 14, 6, 8, Color{ .r = 30, .g = 25, .b = 20 });
        // Chest vector worm anchor node
        w.fill_circle(pt.x, pt.y + 2, 4, Palette.tangent_core);
        w.draw_circle_outline(pt.x, pt.y + 2, 6, Palette.tangent_glow);

        layout_resolver.submit(TextLabel.init("Donnie", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
        if (status_of(frame).tangent_active) {
            layout_resolver.submit(TextLabel.init("[LIVING RECEIVER]", pt.x, pt.y, .below, ACTOR_SCREEN_RADIUS + 4, 1, to_layout(Palette.tangent_glow), .actor_status, .actor_status));
        }
    } else if (std.mem.eql(u8, name, "Frank")) {
        // Frank: Demonic silver rabbit suit, sinister skull mask, tall ears (P31-01, P31-03, D-027)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 2, Palette.frank_silver);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS + 2, Color.white);
        // Tall pointed metallic rabbit ears
        w.fill_rect(pt.x - 10, pt.y - ACTOR_SCREEN_RADIUS - 16, 6, 18, Palette.frank_silver);
        w.fill_rect(pt.x + 4, pt.y - ACTOR_SCREEN_RADIUS - 16, 6, 18, Palette.frank_silver);
        w.draw_rect_outline(pt.x - 10, pt.y - ACTOR_SCREEN_RADIUS - 16, 6, 18, Color.white);
        w.draw_rect_outline(pt.x + 4, pt.y - ACTOR_SCREEN_RADIUS - 16, 6, 18, Color.white);
        // Sinister dark hollow eyes
        w.fill_circle(pt.x - 5, pt.y - 4, 4, Color.black);
        w.fill_circle(pt.x + 5, pt.y - 4, 4, Color.black);
        // Silver skull grin
        w.draw_line(pt.x - 8, pt.y + 8, pt.x + 8, pt.y + 8, Color.black);
        w.draw_line(pt.x - 6, pt.y + 6, pt.x - 6, pt.y + 10, Color.black);
        w.draw_line(pt.x - 2, pt.y + 6, pt.x - 2, pt.y + 10, Color.black);
        w.draw_line(pt.x + 2, pt.y + 6, pt.x + 2, pt.y + 10, Color.black);
        w.draw_line(pt.x + 6, pt.y + 6, pt.x + 6, pt.y + 10, Color.black);

        layout_resolver.submit(TextLabel.init("Frank", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
        layout_resolver.submit(TextLabel.init("[MANIPULATED DEAD]", pt.x, pt.y, .below, ACTOR_SCREEN_RADIUS + 4, 1, to_layout(Color{ .r = 239, .g = 68, .b = 68 }), .actor_status, .actor_status));
    } else if (std.mem.eql(u8, name, "Gretchen")) {
        // Gretchen Ross: Red knit sweater, brunette hair (P31-03, D-027)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 185, .g = 28, .b = 28 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // Long brown hair
        w.fill_circle(pt.x, pt.y - 10, 9, Color{ .r = 80, .g = 50, .b = 30 });
        w.fill_rect(pt.x - 12, pt.y - 6, 4, 14, Color{ .r = 80, .g = 50, .b = 30 });
        w.fill_rect(pt.x + 8, pt.y - 6, 4, 14, Color{ .r = 80, .g = 50, .b = 30 });

        layout_resolver.submit(TextLabel.init("Gretchen", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
    } else if (std.mem.eql(u8, name, "RobertaSparrow") or std.mem.eql(u8, name, "Roberta")) {
        // Roberta Sparrow (Grandma Death): Floral dress, frazzled hair, letter (P31-01, P31-03, D-027)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 120, .g = 100, .b = 135 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        // Frazzled white curls
        w.fill_circle(pt.x, pt.y - 12, 10, Color{ .r = 235, .g = 235, .b = 240 });
        w.fill_circle(pt.x - 10, pt.y - 8, 5, Color{ .r = 225, .g = 225, .b = 230 });
        w.fill_circle(pt.x + 10, pt.y - 8, 5, Color{ .r = 225, .g = 225, .b = 230 });
        // Envelope in hand
        w.fill_rect(pt.x + 8, pt.y + 4, 10, 7, Color.white);
        w.draw_rect_outline(pt.x + 8, pt.y + 4, 10, 7, Color{ .r = 100, .g = 100, .b = 100 });

        layout_resolver.submit(TextLabel.init("Roberta Sparrow", pt.x, pt.y, .above, ACTOR_SCREEN_RADIUS + 4, 2, to_layout(Color.hud_text), .actor_name, .actor_name));
        layout_resolver.submit(TextLabel.init("['Grandma Death']", pt.x, pt.y, .below, ACTOR_SCREEN_RADIUS + 4, 1, to_layout(Color.hud_subtext), .actor_status, .actor_status));
    } else if (std.mem.eql(u8, name, "Gabriel")) {
        // Gabriel Knight: Leather trench coat, signature blonde hair, dark shades (P14-02, D-016)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.gabriel_coat);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Blonde hair
        w.fill_circle(pt.x, pt.y - 8, 8, Palette.gabriel_hair);

        // Dark sunglasses
        w.fill_rect(pt.x - 7, pt.y - 4, 14, 4, Color.black);

        // Cat-hair moustache if disguised
        if (status_of(frame).gabriel_disguised) {
            w.fill_rect(pt.x - 6, pt.y + 2, 12, 4, Color.black);
            w.draw_rect_outline(pt.x - 6, pt.y + 2, 12, 4, Color{ .r = 250, .g = 204, .b = 21 });
        }

        // Label
        layout_resolver.submit(TextLabel.init(
            "Gabriel",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Palette.gabriel_hair),
            .actor_name,
            .actor_name,
        ));

        // Status
        if (status_of(frame).gabriel_disguised) {
            layout_resolver.submit(TextLabel.init(
                "[DISGUISED AS MOSELY!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.status_running),
                .actor_status,
                .actor_alert,
            ));
        } else {
            layout_resolver.submit(TextLabel.init(
                "[Undisguised]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.hud_subtext),
                .actor_status,
                .actor_status,
            ));
        }
    } else if (std.mem.eql(u8, name, "Mosely")) {
        // Detective Franklin Mosely: Navy suit, genuine moustache (P14-02, D-016)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.mosely_suit);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Brown hair & real moustache
        w.fill_circle(pt.x, pt.y - 8, 8, Color{ .r = 90, .g = 55, .b = 30 });
        w.fill_rect(pt.x - 6, pt.y + 2, 12, 4, Color.black);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Mosely",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 147, .g = 197, .b = 253 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Detective]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color.hud_subtext),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "Buthane")) {
        // Madame Buthane: Crimson vest, auburn hair (P14-02, D-016)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.buthane_vest);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Auburn hair
        w.fill_circle(pt.x, pt.y - 8, 8, Palette.buthane_hair);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Madame Buthane",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 252, .g = 165, .b = 165 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Rental Desk]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color.hud_subtext),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "StrayCat")) {
        // Stray Cat: Black cat token with green eyes & ears (P14-02, D-016)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS - 2, Palette.stray_cat_color);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS - 2, Color.white);

        // Ears
        w.fill_rect(pt.x - 8, pt.y - ACTOR_SCREEN_RADIUS - 4, 4, 6, Palette.stray_cat_color);
        w.fill_rect(pt.x + 4, pt.y - ACTOR_SCREEN_RADIUS - 4, 4, 6, Palette.stray_cat_color);

        // Green eyes
        w.fill_rect(pt.x - 5, pt.y - 3, 3, 3, Palette.cat_eye_color);
        w.fill_rect(pt.x + 2, pt.y - 3, 3, 3, Palette.cat_eye_color);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Stray Cat",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color.hud_text),
            .actor_name,
            .actor_name,
        ));

        if (status_of(frame).cat_startled) {
            layout_resolver.submit(TextLabel.init(
                "[STARTLED!]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.cue_alert),
                .actor_status,
                .actor_alert,
            ));
        } else {
            layout_resolver.submit(TextLabel.init(
                "[Napping]",
                pt.x,
                pt.y,
                .below,
                ACTOR_SCREEN_RADIUS + 4,
                1,
                to_layout(Color.hud_subtext),
                .actor_status,
                .actor_status,
            ));
        }
    } else if (std.mem.eql(u8, name, "DoryQuill")) {
        // Dory Quill: sea-green smock, knotted headscarf, and a boathook over her shoulder
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 13, .g = 148, .b = 136 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_rect(pt.x - 9, pt.y - ACTOR_SCREEN_RADIUS - 2, 18, 5, Color{ .r = 250, .g = 204, .b = 21 });
        w.draw_line(pt.x + 8, pt.y + 10, pt.x + 16, pt.y - 18, Color{ .r = 180, .g = 140, .b = 90 });
        w.draw_line(pt.x + 16, pt.y - 18, pt.x + 20, pt.y - 14, Color{ .r = 203, .g = 213, .b = 225 });
        layout_resolver.submit(TextLabel.init(
            name,
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 153, .g = 246, .b = 228 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Fencer]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color.hud_subtext),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "BosunPike") or std.mem.eql(u8, name, "OldGannet")) {
        // Bosun Pike / Old Gannet: crimson vest, tricorn hat, eye patch
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 185, .g = 28, .b = 28 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Tricorn hat
        w.fill_rect(pt.x - 10, pt.y - ACTOR_SCREEN_RADIUS - 4, 20, 6, Color.black);
        // Eye patch
        w.fill_rect(pt.x + 1, pt.y - 4, 6, 6, Color.black);
        w.draw_line(pt.x - 6, pt.y - 7, pt.x + 8, pt.y - 1, Color.black);

        // Label
        layout_resolver.submit(TextLabel.init(
            name,
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 252, .g = 165, .b = 165 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Fencer]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color.hud_subtext),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "Tamsin")) {
        // Tamsin (player): sea-green coat, dark hair
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.tamsin_coat);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_circle(pt.x, pt.y - 8, 8, Palette.tamsin_hair);

        layout_resolver.submit(TextLabel.init(
            "Tamsin",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 153, .g = 246, .b = 228 }),
            .actor_name,
            .actor_name,
        ));
    } else if (std.mem.eql(u8, name, "Vell")) {
        // Mistress Vell: the fencing mistress of Brackwater. Crimson sash, fencing stance
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 225, .g = 29, .b = 72 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 250, .g = 204, .b = 21 });

        // Crimson headband
        w.fill_rect(pt.x - 8, pt.y - 10, 16, 5, Color{ .r = 244, .g = 63, .b = 94 });

        // Label
        layout_resolver.submit(TextLabel.init(
            "Vell",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 254, .g = 205, .b = 211 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Fencing Mistress]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color{ .r = 250, .g = 204, .b = 21 }),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "Barkeep")) {
        // Barkeep: Brown vest, white apron
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 120, .g = 70, .b = 40 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Apron
        w.fill_rect(pt.x - 6, pt.y - 2, 12, 10, Color.white);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Barkeep",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 253, .g = 230, .b = 138 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Drowned Lantern]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color.hud_subtext),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "Citizen")) {
        // Citizen of Brackwater: green coat
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 16, .g = 120, .b = 70 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        // Label
        layout_resolver.submit(TextLabel.init(
            "Citizen",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 167, .g = 243, .b = 208 }),
            .actor_name,
            .actor_name,
        ));
        layout_resolver.submit(TextLabel.init(
            "[Citizen]",
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(Color.hud_subtext),
            .actor_status,
            .actor_status,
        ));
    } else if (std.mem.eql(u8, name, "Sheriff")) {
        // Sheriff: Navy lawman coat & gold star badge (P18-03, D-021)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 30, .g = 58, .b = 138 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_rect(pt.x - 10, pt.y - ACTOR_SCREEN_RADIUS - 4, 20, 5, Color{ .r = 120, .g = 75, .b = 35 });
        w.fill_circle(pt.x + 5, pt.y + 2, 4, Color{ .r = 250, .g = 204, .b = 21 });

        layout_resolver.submit(TextLabel.init(
            "Sheriff",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 147, .g = 197, .b = 253 }),
            .actor_name,
            .actor_name,
        ));
        const st = if (status_of(frame).village_warrant_active) "[Warrant Hunt!]" else "[Lawman]";
        const st_col = if (status_of(frame).village_warrant_active) Color.cue_alert else Color.hud_subtext;
        const st_prio: LabelPriority = if (status_of(frame).village_warrant_active) .actor_alert else .actor_status;
        layout_resolver.submit(TextLabel.init(
            st,
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(st_col),
            .actor_status,
            st_prio,
        ));
    } else if (std.mem.eql(u8, name, "Baker")) {
        // Baker: White tunic & chef toque hat (P18-03, D-021)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 217, .g = 119, .b = 6 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_rect(pt.x - 7, pt.y - ACTOR_SCREEN_RADIUS - 8, 14, 9, Color.white);

        layout_resolver.submit(TextLabel.init(
            "Baker",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 254, .g = 240, .b = 138 }),
            .actor_name,
            .actor_name,
        ));
    } else if (std.mem.eql(u8, name, "Farmer")) {
        // Farmer: Earthy green tunic & golden straw hat (P18-03, D-021)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 22, .g = 101, .b = 52 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_rect(pt.x - 11, pt.y - ACTOR_SCREEN_RADIUS - 4, 22, 5, Color{ .r = 250, .g = 204, .b = 21 });

        layout_resolver.submit(TextLabel.init(
            "Farmer",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 134, .g = 239, .b = 172 }),
            .actor_name,
            .actor_name,
        ));
    } else if (std.mem.eql(u8, name, "Innkeeper")) {
        // Innkeeper: Warm burgundy coat & apron (P18-03, D-021)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color{ .r = 153, .g = 27, .b = 27 });
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_rect(pt.x - 6, pt.y - 2, 12, 10, Color.white);

        layout_resolver.submit(TextLabel.init(
            "Innkeeper",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 252, .g = 165, .b = 165 }),
            .actor_name,
            .actor_name,
        ));
    } else if (std.mem.eql(u8, name, "Gossip")) {
        // Gossip: Royal purple cloak & plume (P18-03, D-021)
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Palette.bard_color);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);
        w.fill_rect(pt.x - 2, pt.y - ACTOR_SCREEN_RADIUS - 7, 4, 8, Color{ .r = 250, .g = 204, .b = 21 });

        layout_resolver.submit(TextLabel.init(
            "Gossip",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color{ .r = 216, .g = 180, .b = 254 }),
            .actor_name,
            .actor_name,
        ));
    } else if (std.mem.eql(u8, name, "Drifter")) {
        // Drifter: Weathered cloak, shows crime/arrest state (P18-03, D-021)
        const d_col = if (status_of(frame).village_arrest_made)
            Color{ .r = 100, .g = 116, .b = 139 }
        else if (status_of(frame).village_crime_active)
            Color.cue_alert
        else
            Color{ .r = 101, .g = 163, .b = 13 };
        w.fill_circle(pt.x, pt.y, ACTOR_SCREEN_RADIUS, d_col);
        w.draw_circle_outline(pt.x, pt.y, ACTOR_SCREEN_RADIUS, Color.white);

        layout_resolver.submit(TextLabel.init(
            "Drifter",
            pt.x,
            pt.y,
            .above,
            ACTOR_SCREEN_RADIUS + 2,
            2,
            to_layout(Color.white),
            .actor_name,
            .actor_name,
        ));
        const st = if (status_of(frame).village_arrest_made)
            "[ARRESTED]"
        else if (status_of(frame).village_crime_active)
            "[THIEF / WANTED]"
        else
            "[Hungry]";
        const st_prio: LabelPriority = if (status_of(frame).village_arrest_made or status_of(frame).village_crime_active) .actor_alert else .actor_status;
        layout_resolver.submit(TextLabel.init(
            st,
            pt.x,
            pt.y,
            .below,
            ACTOR_SCREEN_RADIUS + 4,
            1,
            to_layout(d_col),
            .actor_status,
            st_prio,
        ));
    } else {
        return false;
    }
    return true;
}

fn walkway(w: *DisplayWindow, frame: *const RenderFrame, p1: r.Point, p2: r.Point) bool {
    if (!detect(frame).is_garden_scene) return false;
    // In Garden: Stone flagstone garden path
    w.draw_line(p1.x, p1.y - 2, p2.x, p2.y - 2, Color{ .r = 135, .g = 120, .b = 100 });
    w.draw_line(p1.x, p1.y - 1, p2.x, p2.y - 1, Color{ .r = 195, .g = 180, .b = 155 });
    w.draw_line(p1.x, p1.y, p2.x, p2.y, Color{ .r = 195, .g = 180, .b = 155 });
    w.draw_line(p1.x, p1.y + 1, p2.x, p2.y + 1, Color{ .r = 195, .g = 180, .b = 155 });
    w.draw_line(p1.x, p1.y + 2, p2.x, p2.y + 2, Color{ .r = 135, .g = 120, .b = 100 });
    return true;
}

/// The spitting field has no visible paths: its marks are places to stand, not corridors.
fn shows_walkways(frame: *const RenderFrame) bool {
    return !detect(frame).is_spitting_scene;
}

const HINT_GOLD = Color{ .r = 250, .g = 204, .b = 21 };

fn footer(frame: *const RenderFrame) ?r.FooterHint {
    const sc = detect(frame);
    if (sc.is_spitting_scene) {
        return .{ .text = "[S]: Spit! | [H]: Horn | [G]: GreenDrink | [-]/[+]: Speed | [Space]: Pause | [< / >]: Scrub" };
    } else if (sc.is_dott_past_scene or sc.is_dott_present_scene or sc.is_dott_future_scene) {
        return .{ .text = "[1]: Hoagie | [2]: Bernard | [3]: Laverne | [-]/[+]: Speed | [Space]: Pause | Flush Item to Portrait", .color = HINT_GOLD };
    } else if (sc.is_goat_courtyard_scene or sc.is_templar_crypt_scene) {
        return .{ .text = "[C]: Courtyard | [T]: Crypt | [1]: Dig | [2]: Plough | [-]/[+]: Speed | [Space]: Pause", .color = HINT_GOLD };
    } else if (sc.is_hotel_scene or sc.is_garden_scene or sc.is_bike_rental_scene) {
        return .{ .text = "[H]: Hotel | [G]: Garden | [B]: Bike Shop | [-]/[+]: Speed | [Space]: Pause | [0-8]: Steps", .color = HINT_GOLD };
    } else if (sc.is_village_scene) {
        return .{ .text = "[S]: Theft | [F]: Feast | [G]: Tip | [-]/[+]: Speed | [Space/N]: Pause/Step | [< / >]: Scrub", .color = HINT_GOLD };
    } else if (sc.is_darko_bedroom_scene or sc.is_darko_school_scene or sc.is_darko_vortex_scene or status_of(frame).tangent_active) {
        return .{ .text = "[1]: Bedroom | [2]: High School | [3]: Ridge | [V]: Conduit | [-]/[+]: Speed | [Space]: Pause", .color = Color{ .r = 168, .g = 85, .b = 247 } };
    }
    return null;
}

// ---------------------------------------------------------------------------
// Sound (P32-02d, D-040): the proofs' music, scene-to-track rule, and effects
// ---------------------------------------------------------------------------

const audio = bespoke.audio;

/// The proofs' music tracks, in soundtrack order.
pub const Track = enum(u8) {
    tavern,
    cellar,
    spitting_contest,
    tidewalk,
    fencing_yard,
    lantern,
    courtyard,
    bike_shop,
    lochmarne,
    tentacle,
    bell_tower,
};

/// The proofs' sound effects, in soundtrack order.
pub const Sfx = enum(u8) {
    horn,
    splash,
    sword_clash,
    whistle,
    goat_bleat,
    thud,
    toilet_flush,
    snip_shears,
    wood_chop,
    sizzle,
};

pub fn track(t: Track) u8 {
    return @intFromEnum(t);
}

pub fn sfx(s: Sfx) audio.Sound {
    return .{ .host = @intFromEnum(s) };
}

pub const soundtrack = audio.Soundtrack{
    .tracks = &TRACKS,
    .sfx = &SFX,
    .track_for_scene = track_for_scene,
};

const TRACKS = blk: {
    @setEvalBranchQuota(20_000);
    const tags = std.meta.tags(Track);
    var t: [tags.len]audio.Music = undefined;
    for (tags, 0..) |tag, i| {
        // Every proof track is arranged sections (P34-08, D-089), written in `music.zig`.
        const a = arranged(tag);
        t[i] = .{ .name = @tagName(tag), .sections = a.sections, .arrangement = a.arrangement };
    }
    break :blk t;
};

fn arranged(which: Track) music.Arranged {
    return switch (which) {
        .tavern => music.tavern,
        .cellar => music.cellar,
        .spitting_contest => music.spitting_contest,
        .tidewalk => music.tidewalk,
        .fencing_yard => music.fencing_yard,
        .lantern => music.lantern,
        .courtyard => music.courtyard,
        .bike_shop => music.bike_shop,
        .lochmarne => music.lochmarne,
        .tentacle => music.tentacle,
        .bell_tower => music.bell_tower,
    };
}

fn wave(source: anytype, shape: audio.Wave, weight: i32) audio.Term {
    return .{ .source = source, .shape = shape, .weight = weight };
}

const SFX = blk: {
    var t: [std.meta.fields(Sfx).len]audio.SfxPatch = undefined;
    // Two detuned saw voices: a ship's foghorn
    t[@intFromEnum(Sfx.horn)] = .{ .note1 = 38, .note2 = 45, .env = 30000, .decay = 3, .samples = 11000, .terms = &.{ wave(.osc1, .saw, 1), wave(.osc2, .saw, 1) }, .mix = .{ .shift = 1 } };
    // Falling bubble over noise
    t[@intFromEnum(Sfx.splash)] = .{ .note1 = 72, .sweep = -6000, .env = 28000, .decay = 3, .samples = 9000, .terms = &.{ .{ .source = .noise, .weight = 2 }, wave(.osc1, .triangle, 1) }, .mix = .{ .div = 3 } };
    // Inharmonic ring (C7 x F#7) with noise
    t[@intFromEnum(Sfx.sword_clash)] = .{ .note1 = 84, .note2 = 90, .env = 32000, .decay = 6, .samples = 5500, .terms = &.{ .{ .source = .ring }, .{ .source = .noise } }, .mix = .{ .shift = 1 } };
    // Rising slide whistle
    t[@intFromEnum(Sfx.whistle)] = .{ .note1 = 60, .sweep = 3500, .env = 22000, .decay = 2, .samples = 11000, .terms = &.{wave(.osc1, .triangle, 1)} };
    // Dual saw/pulse bleat alternating C4 and Eb4 (P20-03, D-023)
    t[@intFromEnum(Sfx.goat_bleat)] = .{ .note1 = 60, .note2 = 63, .duty = 0x60000000, .sweep = 150, .env = 30000, .decay = 3, .samples = 9000, .step_samples = 1200, .steps = &.{ .{ .note = 63, .samples = 1200 }, .{ .note = 60, .samples = 1200 } }, .loop = true, .terms = &.{ wave(.osc1, .saw, 1), wave(.osc2, .pulse, 1) }, .mix = .{ .shift = 1 } };
    // Heavy headbutt impact with a fast pitch drop (P20-03, D-023)
    t[@intFromEnum(Sfx.thud)] = .{ .note1 = 40, .sweep = -1800, .env = 32000, .decay = 20, .samples = 1600, .terms = &.{ .{ .source = .noise }, wave(.osc1, .triangle, 3) }, .mix = .{ .shift = 2 } };
    // Downward swirling flush (P21-03, D-025)
    t[@intFromEnum(Sfx.toilet_flush)] = .{ .note1 = 64, .sweep = -120, .env = 28000, .decay = 2, .samples = 18000, .terms = &.{ .{ .source = .noise }, wave(.osc1, .saw, 1) }, .mix = .{ .shift = 1 } };
    // Sharp metallic snip (P21-03, D-025)
    t[@intFromEnum(Sfx.snip_shears)] = .{ .note1 = 84, .duty = 0x40000000, .sweep = -1200, .env = 26000, .decay = 18, .samples = 2200, .terms = &.{ wave(.osc1, .pulse, 1), .{ .source = .noise } }, .mix = .{ .shift = 1 } };
    // Axe on timber (P21-03, D-025)
    t[@intFromEnum(Sfx.wood_chop)] = .{ .note1 = 36, .sweep = -2200, .env = 32000, .decay = 24, .samples = 2000, .terms = &.{ .{ .source = .noise, .weight = 2 }, wave(.osc1, .triangle, 2) }, .mix = .{ .shift = 2 } };
    // Corrosive hiss: noise over a bubbling saw tone (P23-03)
    t[@intFromEnum(Sfx.sizzle)] = .{ .note1 = 66, .sweep = 900, .env = 24000, .decay = 4, .samples = 7000, .terms = &.{ .{ .source = .noise, .weight = 3 }, wave(.osc1, .saw, 1) }, .mix = .{ .div = 4 } };
    break :blk t;
};

fn track_for_scene(scene_name: []const u8) ?u8 {
    if (scene_name.len == 0) return null;

    // Checked first: later substrings ("Sanctuary", "Courtyard") belong to other slices.
    if (std.mem.indexOf(u8, scene_name, "Bell Tower") != null) return track(.bell_tower);

    if (std.mem.indexOf(u8, scene_name, "Spitting") != null or
        std.mem.indexOf(u8, scene_name, "Booty") != null or
        std.mem.indexOf(u8, scene_name, "Spit") != null)
    {
        return track(.spitting_contest);
    } else if (std.mem.indexOf(u8, scene_name, "Tidewalk") != null) {
        return track(.tidewalk);
    } else if (std.mem.indexOf(u8, scene_name, "Fencing Yard") != null) {
        return track(.fencing_yard);
    } else if (std.mem.indexOf(u8, scene_name, "Drowned Lantern") != null) {
        return track(.lantern);
    } else if (std.mem.indexOf(u8, scene_name, "Cellar") != null) {
        return track(.cellar);
    } else if (std.mem.indexOf(u8, scene_name, "Tavern") != null or
        std.mem.indexOf(u8, scene_name, "Common") != null)
    {
        return track(.tavern);
    } else if (std.mem.indexOf(u8, scene_name, "Garden") != null or
        std.mem.indexOf(u8, scene_name, "Courtyard") != null or
        std.mem.indexOf(u8, scene_name, "Corridor") != null)
    {
        return track(.courtyard);
    } else if (std.mem.indexOf(u8, scene_name, "Bike") != null or
        std.mem.indexOf(u8, scene_name, "Rental") != null)
    {
        return track(.bike_shop);
    } else if (std.mem.indexOf(u8, scene_name, "Lochmarne") != null or
        std.mem.indexOf(u8, scene_name, "Goat") != null or
        std.mem.indexOf(u8, scene_name, "Crypt") != null or
        std.mem.indexOf(u8, scene_name, "Templar") != null)
    {
        return track(.lochmarne);
    } else if (std.mem.indexOf(u8, scene_name, "Colonial") != null or
        std.mem.indexOf(u8, scene_name, "Motel") != null or
        std.mem.indexOf(u8, scene_name, "Dystopia") != null or
        std.mem.indexOf(u8, scene_name, "Tentacle") != null or
        std.mem.indexOf(u8, scene_name, "Dott") != null or
        std.mem.indexOf(u8, scene_name, "Chrono") != null)
    {
        return track(.tentacle);
    }

    return track(.tavern);
}

// ---------------------------------------------------------------------------
// Status (P32-03b, D-041): what the proof art shows about puzzle progress
// ---------------------------------------------------------------------------

pub const VillagerDrive = struct {
    entity: bespoke.EntityId = .none,
    name: [16]u8 = [_]u8{0} ** 16,
    name_len: u8 = 0,
    hunger: u8 = 0,
    energy: u8 = 0,
    gold: u16 = 0,
    activity: u8 = 0,
    knows_rumor: bool = false,
    is_witness: bool = false,
    is_arrested: bool = false,

    pub fn get_name(self: *const VillagerDrive) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// A directed social or emergence edge for the live Social Graph HUD (P18-02, P18-03, D-021).
pub const SocialEdge = struct {
    from_name: [16]u8 = [_]u8{0} ** 16,
    from_len: u8 = 0,
    to_name: [16]u8 = [_]u8{0} ** 16,
    to_len: u8 = 0,
    /// 0 = Friend, 1 = Grudge/Rival, 2 = KnowsRumor, 3 = WarrantFor, 4 = Arrested
    kind: u8 = 0,

    pub fn get_from(self: *const SocialEdge) []const u8 {
        return self.from_name[0..self.from_len];
    }
    pub fn get_to(self: *const SocialEdge) []const u8 {
        return self.to_name[0..self.to_len];
    }
};

/// The proofs' status block, carried in `RenderFrame.host_status_bytes`. Every field is valid
/// at zero, which is how a frame's block starts.
pub const Status = struct {
    cheese_holder: bespoke.EntityId = .none,
    charmed_target: bespoke.EntityId = .none,
    spit_is_thick: bool = false,
    flags_tampered: bool = false,
    wind_blowing: bool = false,
    organiser_distracted: bool = false,
    fence_taped: bool = false,
    fence_has_hair: bool = false,
    cat_startled: bool = false,
    cat_hair_collected: bool = false,
    gabriel_disguised: bool = false,
    bike_rented: bool = false,
    goat_is_tangled: bool = false,
    goat_is_charging: bool = false,
    goat_is_retreating: bool = false,
    george_knocked_down: bool = false,
    plough_moved: bool = false,
    dott_tree_chopped: bool = false,
    dott_wine_aged: bool = false,
    dott_battery_charged: bool = false,
    dott_flag_sewn: bool = false,
    dott_laverne_freed: bool = false,
    dott_laverne_disguised: bool = false,
    dott_puzzle_solved: bool = false,
    tangent_active: bool = false,
    singularity_collapsed: bool = false,
    darko_water_flooded: bool = false,
    darko_letter_delivered: bool = false,
    darko_vortex_reached: bool = false,
    darko_artifact_returned: bool = false,
    darko_puzzle_solved: bool = false,
    bell_brazier_lit: bool = false,
    bell_chain_loosed: bool = false,
    bell_fork_taken: bool = false,
    bell_ringing: bool = false,
    bell_beacon_lit: bool = false,
    village_crime_active: bool = false,
    village_warrant_active: bool = false,
    village_arrest_made: bool = false,
    tangent_countdown: [16]u8 = [_]u8{0} ** 16,
    tangent_countdown_len: u8 = 0,
    /// Castle Fire Escape (P25-03): one attribute mask per gallery cell, bit n set when
    /// `grid.Attribute` n holds, and whether the hidden door has been found.
    gallery_cells: [GALLERY_CELLS]u8 = [_]u8{0} ** GALLERY_CELLS,
    gallery_door_revealed: bool = false,
    villager_drives: [8]VillagerDrive = [_]VillagerDrive{.{}} ** 8,
    villager_drive_count: usize = 0,
    social_edges: [16]SocialEdge = [_]SocialEdge{.{}} ** 16,
    social_edge_count: usize = 0,

    pub fn countdown(self: *const Status) []const u8 {
        return self.tangent_countdown[0..self.tangent_countdown_len];
    }
};

pub fn status_of(frame: *const RenderFrame) *const Status {
    return frame.host_status(Status);
}

/// Shows the branch-world collapse countdown (the Middlesex Anomaly sets it every tick).
pub fn set_countdown(bridge: *bespoke.DisplayBridge, text: []const u8) void {
    const status = bridge.back_buffer.host_status_mut(Status);
    const len = @min(text.len, status.tangent_countdown.len);
    @memcpy(status.tangent_countdown[0..len], text[0..len]);
    status.tangent_countdown_len = @intCast(len);
    status.tangent_active = true;
}

/// Sets the collapse fail-state on both buffers, so it shows before the next capture.
pub fn set_collapsed(bridge: *bespoke.DisplayBridge, collapsed: bool) void {
    bridge.back_buffer.host_status_mut(Status).singularity_collapsed = collapsed;
    bridge.front_buffer.host_status_mut(Status).singularity_collapsed = collapsed;
}

/// Reads the gallery grid's cell facts by the names its script uses (P25-03).
fn capture_gallery(world: *const bespoke.World, st: *Status) void {
    st.gallery_cells = [_]u8{0} ** GALLERY_CELLS;
    st.gallery_door_revealed = false;
    const floor = world.lookup_entity("GalleryFloor") orelse return;
    inline for (@typeInfo(bespoke.grid.Attribute).Enum.fields) |field| {
        const attribute: bespoke.grid.Attribute = @enumFromInt(field.value);
        if (world.lookup_relation(attribute.relation_name())) |rel| {
            for (&st.gallery_cells, 0..) |*mask, i| {
                if (world.has_fact(floor, rel, @intCast(i))) mask.* |= @as(u8, 1) << field.value;
            }
        }
    }
    // The same rule as the proof host: the door shows once the tapestry beside it (cell 4)
    // has caught and stopped being flammable.
    st.gallery_door_revealed = !gallery_has(st, 4, .flammable);
}

fn gallery_has(st: *const Status, i: usize, attribute: bespoke.grid.Attribute) bool {
    return st.gallery_cells[i] & (@as(u8, 1) << @intCast(@intFromEnum(attribute))) != 0;
}

/// The Larkspur Observatory (P33-03): a night sky with the dome, over two floors whose rows
/// match the proof's mark layout (public floor above, working floor below).
fn render_observatory(w: *DisplayWindow) void {
    w.fill_rect(0, 0, w.width, w.height, Color{ .r = 8, .g = 12, .b = 30 });
    var star: i32 = 0;
    while (star < 40) : (star += 1) {
        w.fill_rect(@mod(star * 211, w.width), 60 + @mod(star * 97, 80), 2, 2, Color{ .r = 226, .g = 232, .b = 240 });
    }
    // The script's `LarkspurPlan` grid: six 8-unit cells per floor, public floor on top.
    const left = world_to_screen(0, 0, w.width, w.height).x;
    const right = world_to_screen(48, 0, w.width, w.height).x;
    const upper = world_to_screen(0, 0, w.width, w.height).y;
    const middle = world_to_screen(0, 8, w.width, w.height).y;
    const lower = world_to_screen(0, 16, w.width, w.height).y;
    // The dome rises above the Dome room's column.
    const dome = world_to_screen(36, 0, w.width, w.height);
    w.fill_circle(dome.x, upper - 10, 70, Color{ .r = 148, .g = 163, .b = 184 });
    w.fill_rect(dome.x - 6, upper - 80, 12, 70, Color{ .r = 30, .g = 41, .b = 59 });
    w.fill_rect(left, upper, right - left, middle - upper, Color{ .r = 51, .g = 65, .b = 85 });
    w.fill_rect(left, middle, right - left, lower - middle, Color{ .r = 41, .g = 37, .b = 36 });
    w.draw_rect_outline(left, upper, right - left, lower - upper, Color{ .r = 100, .g = 116, .b = 139 });
    w.draw_line(left, middle, right, middle, Color{ .r = 100, .g = 116, .b = 139 });
    w.draw_text("LARKSPUR OBSERVATORY - THE NIGHT PLATE 41 VANISHED", left + 12, upper - 34, 2, Color{ .r = 191, .g = 219, .b = 254 });
    w.draw_text("PUBLIC FLOOR", left + 8, upper + 6, 1, Color.hud_subtext);
    w.draw_text("WORKING FLOOR", left + 8, middle + 6, 1, Color.hud_subtext);
}

/// Hollin Keep's long gallery (P25-03): a wall band with the tapestry, door, trough, and
/// torch above a one-row floor whose cells show the grid's state.
fn render_gallery(w: *DisplayWindow, frame: *const RenderFrame) void {
    const st = status_of(frame);
    const stone = Color{ .r = 52, .g = 48, .b = 46 };
    const mortar = Color{ .r = 34, .g = 31, .b = 30 };
    w.fill_rect(0, 0, w.width, w.height, Color{ .r = 14, .g = 12, .b = 14 });

    const origin = world_to_screen(0, 0, w.width, w.height);
    const far = world_to_screen(@as(i32, GALLERY_CELLS) * @as(i32, GALLERY_CELL_SIZE), @as(i32, GALLERY_CELL_SIZE), w.width, w.height);
    const cell_w = @divTrunc(far.x - origin.x, GALLERY_CELLS);
    const wall_top: i32 = 150;
    const wall_h = origin.y - wall_top;

    // Wall band with coursed stone.
    w.fill_rect(origin.x, wall_top, far.x - origin.x, wall_h, stone);
    var course = wall_top + 28;
    while (course < origin.y) : (course += 28) w.draw_line(origin.x, course, far.x, course, mortar);
    w.draw_text("HOLLIN KEEP - THE LONG GALLERY", origin.x + 12, wall_top - 40, 2, Color{ .r = 253, .g = 186, .b = 116 });
    w.draw_text("(THE ONLY WAY OUT IS BEHIND THE TAPESTRY)", origin.x + 12, wall_top - 18, 1, Color.hud_subtext);

    for (0..GALLERY_CELLS) |i| {
        const x = origin.x + @as(i32, @intCast(i)) * cell_w;
        const burning = gallery_has(st, i, .burning);
        const flammable = gallery_has(st, i, .flammable);
        const wet = gallery_has(st, i, .liquid);
        const rubble = gallery_has(st, i, .blocking);
        // Cells 2 to 5 are the tapestry's span; a span cell that is neither flammable nor
        // burning has been consumed.
        const in_span = i >= 2;
        const spent = in_span and !flammable and !burning;

        // Wall decoration above the cell.
        if (i == 0) {
            w.fill_rect(x + 24, origin.y - 70, cell_w - 48, 50, Color{ .r = 88, .g = 84, .b = 80 });
            w.fill_rect(x + 30, origin.y - 64, cell_w - 60, 20, Color{ .r = 37, .g = 99, .b = 155 });
        } else if (i == 1) {
            w.fill_rect(x + @divTrunc(cell_w, 2) - 4, wall_top + 60, 8, 40, Color{ .r = 70, .g = 60, .b = 50 });
            w.fill_circle(x + @divTrunc(cell_w, 2), wall_top + 52, 10, Color{ .r = 245, .g = 158, .b = 11 });
            w.fill_circle(x + @divTrunc(cell_w, 2), wall_top + 49, 5, Color{ .r = 254, .g = 240, .b = 138 });
        } else if (i == 5 and (st.gallery_door_revealed or spent or rubble)) {
            const door_col = if (rubble) Color{ .r = 30, .g = 26, .b = 24 } else Color{ .r = 101, .g = 67, .b = 33 };
            w.fill_rect(x + 30, wall_top + 40, cell_w - 60, wall_h - 40, door_col);
            w.draw_rect_outline(x + 30, wall_top + 40, cell_w - 60, wall_h - 40, Color{ .r = 60, .g = 40, .b = 20 });
        }
        if (in_span and flammable and !(i == 5 and st.gallery_door_revealed)) {
            w.fill_rect(x + 2, wall_top + 20, cell_w - 4, wall_h - 30, Color{ .r = 128, .g = 28, .b = 40 });
            w.draw_line(x + 10, wall_top + 60, x + cell_w - 10, wall_top + 60, Color{ .r = 202, .g = 138, .b = 4 });
        } else if (in_span and spent and i != 5) {
            w.fill_rect(x + 2, origin.y - 24, cell_w - 4, 18, Color{ .r = 28, .g = 22, .b = 20 });
        }
        if (burning) {
            var f: i32 = 0;
            while (f < 4) : (f += 1) {
                const fx = x + 18 + f * @divTrunc(cell_w - 36, 3);
                w.fill_circle(fx, origin.y - 40 - @mod(f * 17, 30), 16, Color{ .r = 234, .g = 88, .b = 12 });
                w.fill_circle(fx, origin.y - 34 - @mod(f * 17, 30), 8, Color{ .r = 253, .g = 224, .b = 71 });
            }
        }

        // Floor tile.
        const floor_col = if (rubble)
            Color{ .r = 40, .g = 36, .b = 34 }
        else if (burning)
            Color{ .r = 150, .g = 52, .b = 12 }
        else if (wet)
            Color{ .r = 32, .g = 74, .b = 120 }
        else if (flammable)
            Color{ .r = 150, .g = 128, .b = 62 }
        else if (spent)
            Color{ .r = 36, .g = 30, .b = 28 }
        else
            Color{ .r = 72, .g = 68, .b = 64 };
        w.fill_rect(x, origin.y, cell_w, far.y - origin.y, floor_col);
        w.draw_rect_outline(x, origin.y, cell_w, far.y - origin.y, mortar);
        if (rubble) {
            w.draw_line(x + 10, origin.y + 10, x + cell_w - 10, far.y - 10, Color{ .r = 90, .g = 84, .b = 80 });
            w.draw_line(x + cell_w - 10, origin.y + 10, x + 10, far.y - 10, Color{ .r = 90, .g = 84, .b = 80 });
        }
        if (gallery_has(st, i, .smoke)) {
            w.fill_rect(x, wall_top, cell_w, far.y - wall_top, Color{ .r = 140, .g = 140, .b = 150, .a = 90 });
        }
    }
}

fn entity_in_state(world: *const bespoke.World, entity_name: []const u8, state: []const u8) bool {
    const ent = world.lookup_entity(entity_name) orelse return false;
    const rel = world.lookup_relation(state) orelse return false;
    return world.has_fact(ent, rel, null);
}

/// The status hook every proof registers with its bridge: reads each proof's puzzle facts
/// by the names its script uses. Moved unchanged from the engine's `capture_frame`.
pub fn capture_status(world: *const bespoke.World, frame: *RenderFrame) void {
    const st = frame.host_status_mut(Status);
    capture_gallery(world, st);
    // 5. Query relational facts for status indicators
    st.cheese_holder = .none;
    st.charmed_target = .none;
    if (world.lookup_entity("Cheese")) |cheese_id| {
        if (world.lookup_relation("Carries")) |carries_rel| {
            if (world.find_first(null, carries_rel, @intFromEnum(cheese_id))) |f| {
                st.cheese_holder = f.subject;
            }
        }
    }
    if (world.lookup_relation("CharmedBy")) |charmed_rel| {
        if (world.find_first(null, charmed_rel, null)) |f| {
            st.charmed_target = f.subject;
        }
    }

    // 5b. Capture Spitting Contest facts (P10-03, D-012)
    st.spit_is_thick = false;
    if (world.lookup_relation("thick")) |rel| {
        st.spit_is_thick = world.has_fact(null, rel, null);
    }
    st.flags_tampered = false;
    if (world.lookup_relation("tampered")) |rel| {
        st.flags_tampered = world.has_fact(null, rel, null);
    }
    st.wind_blowing = false;
    if (world.lookup_relation("blowing")) |rel| {
        st.wind_blowing = world.has_fact(null, rel, null);
    }
    st.organiser_distracted = false;
    if (world.lookup_relation("Distracted")) |rel| {
        st.organiser_distracted = world.has_fact(null, rel, null);
    }

    // GK3 Cat Moustache scenario status flags (P14-02)
    st.fence_taped = false;
    if (world.lookup_relation("taped") orelse world.lookup_relation("Taped")) |rel| {
        st.fence_taped = world.has_fact(null, rel, null);
    }
    st.fence_has_hair = false;
    if (world.lookup_relation("FenceHasHair")) |rel| {
        st.fence_has_hair = world.has_fact(null, rel, null);
    }
    st.cat_startled = false;
    if (world.lookup_relation("startled") orelse world.lookup_relation("Startled")) |rel| {
        st.cat_startled = world.has_fact(null, rel, null);
    }
    st.cat_hair_collected = false;
    if (world.lookup_relation("Carries")) |c_rel| {
        if (world.lookup_entity("CatHair")) |ch_id| {
            st.cat_hair_collected = world.has_fact(null, c_rel, ch_id.to_int());
        }
    }
    st.gabriel_disguised = false;
    if (world.lookup_relation("disguised") orelse world.lookup_relation("Disguised")) |rel| {
        st.gabriel_disguised = world.has_fact(null, rel, null);
    }
    st.bike_rented = false;
    if (world.lookup_relation("HasBikeKeys") orelse world.lookup_relation("BikeRented")) |rel| {
        st.bike_rented = world.has_fact(null, rel, null);
    }

    // 5c. Capture Living Village drives & social graph relations (P18-01..P18-03, D-021)
    st.villager_drive_count = 0;
    st.social_edge_count = 0;
    st.village_crime_active = false;
    st.village_warrant_active = false;
    st.village_arrest_made = false;

    if (world.lookup_relation("Hunger")) |hunger_rel| {
        const energy_rel = world.lookup_relation("Energy");
        const gold_rel = world.lookup_relation("Gold");
        const act_rel = world.lookup_relation("Activity");
        const rumor_rel = world.lookup_relation("KnowsRumor");
        const wit_rel = world.lookup_relation("Witnessed");
        const arr_rel = world.lookup_relation("Arrested");
        const stolen_rel = world.lookup_relation("StolenFrom");
        const warrant_rel = world.lookup_relation("WarrantFor");

        if (stolen_rel) |sr| st.village_crime_active = world.has_fact(null, sr, null);
        if (warrant_rel) |wr| st.village_warrant_active = world.has_fact(null, wr, null);
        if (arr_rel) |ar| st.village_arrest_made = world.has_fact(null, ar, null);

        var vd_count: usize = 0;
        for (frame.entities[0..frame.entity_count]) |re| {
            if (vd_count >= st.villager_drives.len) break;
            if (world.get_property(re.entity, hunger_rel)) |h_val| {
                var vd = VillagerDrive{
                    .entity = re.entity,
                    .hunger = @intCast(@min(100, h_val)),
                    .energy = if (energy_rel) |er| @intCast(@min(100, world.get_property(re.entity, er) orelse 0)) else 0,
                    .gold = if (gold_rel) |gr| @intCast(@min(999, world.get_property(re.entity, gr) orelse 0)) else 0,
                    .activity = if (act_rel) |ar| @intCast(@min(20, world.get_property(re.entity, ar) orelse 0)) else 0,
                    .knows_rumor = if (rumor_rel) |rr| world.has_fact(re.entity, rr, null) else false,
                    .is_witness = if (wit_rel) |wr| world.has_fact(re.entity, wr, null) else false,
                    .is_arrested = if (arr_rel) |ar| world.has_fact(re.entity, ar, null) else false,
                };
                const n = re.get_name();
                const nlen = @min(n.len, vd.name.len);
                @memcpy(vd.name[0..nlen], n[0..nlen]);
                vd.name_len = @intCast(nlen);
                st.villager_drives[vd_count] = vd;
                vd_count += 1;
            }
        }
        st.villager_drive_count = vd_count;

        // Capture key social and emergence edges for the Social Graph HUD
        const edge_rels = [_]struct { name: []const u8, kind: u8 }{
            .{ .name = "Arrested", .kind = 4 },
            .{ .name = "WarrantFor", .kind = 3 },
            .{ .name = "KnowsRumor", .kind = 2 },
            .{ .name = "Grudge", .kind = 1 },
            .{ .name = "Friend", .kind = 0 },
        };
        var se_count: usize = 0;
        for (edge_rels) |er_info| {
            if (world.lookup_relation(er_info.name)) |rel_id| {
                var q_it = world.query(null, rel_id, null);
                while (q_it.next()) |f| {
                    if (se_count >= st.social_edges.len) break;
                    const s_name = world.get_entity_name(f.subject) orelse continue;
                    const o_name = world.get_entity_name(bespoke.EntityId.from_int(f.object_or_value)) orelse continue;
                    // Avoid duplicate undirected Friend lines
                    if (er_info.kind == 0 and f.subject.to_int() > f.object_or_value) continue;

                    var se = SocialEdge{ .kind = er_info.kind };
                    const slen = @min(s_name.len, se.from_name.len);
                    @memcpy(se.from_name[0..slen], s_name[0..slen]);
                    se.from_len = @intCast(slen);

                    const olen = @min(o_name.len, se.to_name.len);
                    @memcpy(se.to_name[0..olen], o_name[0..olen]);
                    se.to_len = @intCast(olen);

                    st.social_edges[se_count] = se;
                    se_count += 1;
                }
            }
        }
        st.social_edge_count = se_count;
    }

    // 5c-bell. Capture Bell Tower scenario state (P22-03). Looked up by entity, not just by
    // relation, because `lit` is a generic state other scripts may also use.
    st.bell_brazier_lit = entity_in_state(world, "Brazier", "lit");
    st.bell_chain_loosed = entity_in_state(world, "IronChain", "loosed");
    st.bell_ringing = entity_in_state(world, "GreatBell", "ringing");
    st.bell_beacon_lit = entity_in_state(world, "Beacon", "lit");
    st.bell_fork_taken = false;
    if (world.lookup_relation("Carries")) |carries| {
        if (world.lookup_entity("TuningFork")) |fork| {
            st.bell_fork_taken = world.has_fact(null, carries, fork.to_int());
        }
    }

    // 5d. Capture Broken Sword Goat Puzzle status flags (P20-01..P20-03, D-023)
    st.goat_is_tangled = false;
    if (world.lookup_relation("tangled") orelse world.lookup_relation("Tangled") orelse world.lookup_relation("TangledWith")) |rel| {
        st.goat_is_tangled = world.has_fact(null, rel, null);
    }
    st.goat_is_retreating = false;
    if (world.lookup_relation("GoatRetreating") orelse world.lookup_relation("retreating")) |rel| {
        st.goat_is_retreating = world.has_fact(null, rel, null);
    }
    st.george_knocked_down = false;
    if (world.lookup_relation("KnockedDown") orelse world.lookup_relation("knocked_down")) |rel| {
        st.george_knocked_down = world.has_fact(null, rel, null);
    }
    st.plough_moved = false;
    if (world.lookup_relation("PloughMoved") orelse world.lookup_relation("plough_moved")) |rel| {
        st.plough_moved = world.has_fact(null, rel, null);
    }

    // 5f. Capture Day of the Tentacle puzzle status flags (P21-03, D-025)
    st.dott_tree_chopped = false;
    if (world.lookup_relation("TreeChoppedDown")) |rel| {
        st.dott_tree_chopped = world.has_fact(null, rel, null);
    }
    st.dott_wine_aged = false;
    if (world.lookup_relation("WineAgedIntoVinegar")) |rel| {
        st.dott_wine_aged = world.has_fact(null, rel, null);
    }
    st.dott_battery_charged = false;
    if (world.lookup_relation("ToiletPowered")) |rel| {
        st.dott_battery_charged = world.has_fact(null, rel, null);
    }
    st.dott_flag_sewn = false;
    if (world.lookup_relation("TentacleFlagSewn")) |rel| {
        st.dott_flag_sewn = world.has_fact(null, rel, null);
    }
    st.dott_laverne_freed = false;
    if (world.lookup_relation("FreedFromTree")) |rel| {
        st.dott_laverne_freed = world.has_fact(null, rel, null);
    }
    st.dott_laverne_disguised = false;
    if (world.lookup_relation("TentacleDisguiseActive")) |rel| {
        st.dott_laverne_disguised = world.has_fact(null, rel, null);
    }
    st.dott_puzzle_solved = false;
    if (world.lookup_relation("DottSolved")) |rel| {
        st.dott_puzzle_solved = world.has_fact(null, rel, null);
    }

    // 5g. Capture Donnie Darko / Roberta Sparrow status flags (P31-01..P31-03, D-027)
    st.darko_water_flooded = false;
    if (world.lookup_relation("SchoolFlooded")) |rel| {
        st.darko_water_flooded = world.has_fact(null, rel, null);
    }
    st.darko_letter_delivered = false;
    if (world.lookup_relation("LetterDelivered")) |rel| {
        st.darko_letter_delivered = world.has_fact(null, rel, null);
    }
    st.darko_vortex_reached = false;
    if (world.lookup_relation("VortexReady")) |rel| {
        st.darko_vortex_reached = world.has_fact(null, rel, null);
    }
    st.darko_artifact_returned = false;
    if (world.lookup_relation("ArtifactMaterialized")) |rel| {
        st.darko_artifact_returned = world.has_fact(null, rel, null);
    }
    st.darko_puzzle_solved = false;
    if (world.lookup_relation("DarkoSolved")) |rel| {
        st.darko_puzzle_solved = world.has_fact(null, rel, null);
    }
}

fn hud(w: *DisplayWindow, frame: *const RenderFrame) void {
    // 6-tangent. Branch-world collapse countdown HUD (P31-01, P31-02, D-027)
    if (status_of(frame).tangent_active) {
        const count_str = status_of(frame).countdown();
        const bw: i32 = 360;
        const bh: i32 = 34;
        const party_right_w: i32 = if (frame.party_count > 1)
            @as(i32, @intCast(frame.party_count)) * (88 + 8) + 10
        else
            0;
        const bx = w.width - bw - 20 - party_right_w;
        const by: i32 = 7;

        w.fill_rect(bx, by, bw, bh, Color{ .r = 25, .g = 15, .b = 40, .a = 235 });
        w.draw_rect_outline(bx, by, bw, bh, Color.countdown_warn);
        w.draw_rect_outline(bx + 1, by + 1, bw - 2, bh - 2, Color.vortex_purple);

        var t_buf: [64]u8 = undefined;
        const t_text = std.fmt.bufPrint(&t_buf, "TANGENT COLLAPSE: {s}", .{count_str}) catch "TANGENT COLLAPSE";
        w.draw_text(t_text, bx + 12, by + 9, 2, Color{ .r = 254, .g = 202, .b = 202 });
    }
}

fn overlay(w: *DisplayWindow, frame: *const RenderFrame) void {
    // 12b. Black Hole Singularity Catastrophic Fail-State Modal (P31-01, D-027)
    if (status_of(frame).singularity_collapsed) {
        w.fill_rect(0, 0, w.width, w.height, Color{ .r = 0, .g = 0, .b = 0, .a = 230 });
        const mw: i32 = 640;
        const mh: i32 = 120;
        const mx = @divTrunc(w.width - mw, 2);
        const my = @divTrunc(w.height - mh, 2);
        w.fill_rect(mx, my, mw, mh, Color{ .r = 15, .g = 8, .b = 20, .a = 250 });
        w.draw_rect_outline(mx, my, mw, mh, Color.countdown_warn);
        w.draw_rect_outline(mx + 2, my + 2, mw - 4, mh - 4, Color.vortex_purple);
        w.draw_text("BLACK HOLE SINGULARITY COLLAPSE", mx + 36, my + 24, 2, Color.countdown_warn);
        w.draw_text("The Tangent Universe collapsed without loop closure. Rewind [R] required.", mx + 24, my + 66, 1, Color{ .r = 224, .g = 242, .b = 254 });
    }
}

// ---------------------------------------------------------------------------
// Save thumbnails (P32-03d, D-041): the proofs' 16x12 save-slot palettes
// ---------------------------------------------------------------------------

const save = bespoke.save;

pub const thumbnails = save.ThumbnailPainter{
    .backdrop = thumbnail_backdrop,
    .actor = thumbnail_actor,
};

/// Moved unchanged from the engine's `generate_thumbnail`. Scenes it does not recognise,
/// including a save with no scene, get the tavern's hearth.
fn thumbnail_backdrop(scene_name: []const u8, x: usize, y: usize) ?u8 {
    const has = struct {
        fn f(name: []const u8, part: []const u8) bool {
            return std.mem.indexOf(u8, name, part) != null;
        }
    }.f;
    const rgb = save.pack_rgb332;
    if (has(scene_name, "Spit") or has(scene_name, "Booty")) {
        if (y < 4) return rgb(25, 45, 95); // Dusk sky
        if (y < 7) return rgb(20, 90, 150); // Ocean
        return if (x < 10) rgb(45, 110, 55) else rgb(190, 170, 110); // Grass & beach
    } else if (has(scene_name, "Garden") or has(scene_name, "Courtyard")) {
        if (y < 4) return rgb(135, 185, 230); // French sky
        if (y < 7) return rgb(160, 110, 60); // Courtyard fence & stone
        return rgb(55, 125, 50); // Courtyard lawn
    } else if (has(scene_name, "Bike") or has(scene_name, "Shop")) {
        return if (y < 6) rgb(85, 75, 65) else rgb(150, 95, 45); // Shop wall, floor & counter
    } else if (has(scene_name, "Hotel") or has(scene_name, "Corridor")) {
        return if (y < 6) rgb(110, 30, 40) else rgb(55, 25, 20); // Burgundy wallpaper, wainscot
    } else if (has(scene_name, "Cellar")) {
        return if (y < 6) rgb(25, 35, 55) else rgb(40, 50, 70); // Cellar wall, stone floor
    } else if (has(scene_name, "Tidewalk")) {
        return if (y < 5) rgb(15, 30, 70) else rgb(40, 75, 50); // Night sky, harbour walk
    } else if (has(scene_name, "Fencing Yard")) {
        return if (y < 5) rgb(70, 20, 35) else rgb(45, 35, 45); // Yard wall, duel circle
    }
    // Tavern warm hearth & timber
    if (x >= 1 and x <= 3 and y >= 3 and y <= 5) return rgb(245, 140, 30); // Hearth fire glow
    return if (y < 6) rgb(55, 38, 28) else rgb(80, 52, 34);
}

fn thumbnail_actor(name: []const u8) ?u8 {
    const is = struct {
        fn f(a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    }.f;
    if (is(name, "Guard") or is(name, "Guybrush") or is(name, "Tamsin") or is(name, "Mosely")) return save.pack_rgb332(50, 130, 245); // Blue
    if (is(name, "Cat") or is(name, "Gabriel")) return save.pack_rgb332(240, 120, 30); // Orange / Tan
    if (is(name, "Bard") or is(name, "Vell")) return save.pack_rgb332(180, 70, 240); // Purple
    return null;
}
