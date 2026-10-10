import Foundation

/// Original characters; raw values are the bundled Blender asset names.
enum RealmFriend: String, CaseIterable, Identifiable, Codable {
    case mosskip = "Mosskip", glimlo = "Glimlo", pebblin = "Pebblin"
    case bloopi = "Bloopi", nibbi = "Nibbi", cindlet = "Cindlet"
    var id: String { rawValue }
    var name: String { rawValue }
    var role: String { story.role }
    var personality: String { story.personality }
    var questTitle: String { story.title }
    var itemName: String { story.item }
    var questRequest: String { story.request }
    var thanks: String { story.thanks }
    var reward: String { story.reward }
    var symbol: String { story.symbol }
    var chat: String { story.chat }
    var petReaction: String { story.pet }
    var playReaction: String { story.play }
    var tempo: Float {
        switch self {
        case .mosskip: return 1
        case .glimlo: return 1.25
        case .pebblin: return 0.65
        case .bloopi: return 1.1
        case .nibbi: return 1.45
        case .cindlet: return 1.2
        }
    }

    private struct Story {
        let role, personality, title, item, request, thanks, reward, symbol, chat, pet, play: String
    }
    private var story: Story {
        switch self {
        case .mosskip: return Story(
            role: "Sprout courier",
            personality: "A pocket-sized gardener who delivers seeds and gets delightfully lost.",
            title: "A seed of friendship", item: "dew seed",
            request: "My satchel has a teeny hole! Could you find my dew seed? It's going to grow into something wonderful.",
            thanks: "You found it! I'll plant a whole garden for us. You're officially my best sprout!",
            reward: "Sprout Scout", symbol: "leaf.fill",
            chat: "Do you think this room needs a garden? I vote yes. I always vote yes.",
            pet: "Mosskip leans into your hand. Those little leaves can't stop swaying!",
            play: "Mosskip demonstrates the very important sprout dance.")
        case .glimlo: return Story(
            role: "Lantern keeper",
            personality: "A bashful little moth who lights the way for friends afraid of the dark.",
            title: "A little light, please", item: "lantern spark",
            request: "Oh! My lantern spark floated away. Will you help me find it? Even little lights need a friend.",
            thanks: "Look, we're glowing! I'll always save a little light for you.",
            reward: "Little Light", symbol: "sun.max.fill",
            chat: "I tried counting all the lights once. Fell asleep at three. Very cozy research.",
            pet: "Glimlo closes their eyes and gives a delighted flutter.",
            play: "Glimlo is practicing a tiny lantern ballet just for you.")
        case .pebblin: return Story(
            role: "Dream collector",
            personality: "A sleepy pebble snail who keeps lovely dreams tucked inside a crystal shell.",
            title: "The missing dream", item: "dream pearl",
            request: "Yaaawn. One of my dreams rolled away. Could you bring back my dream pearl before it turns into a daydream?",
            thanks: "There it is… the dream where we fly on a giant pancake. Next time, you're coming too.",
            reward: "Dream Keeper", symbol: "moon.stars.fill",
            chat: "I'm not slow. I'm taking the scenic route through this very excellent moment.",
            pet: "Pebblin melts into a sleepy, happy puddle. Almost a purr.",
            play: "Pebblin does the world's tiniest victory dance. Then a little rest.")
        case .bloopi: return Story(
            role: "Puddle explorer",
            personality: "A blue tide pup with rosy gills who maps puddles and names every ripple.",
            title: "One perfect plop", item: "ripple stone",
            request: "Bloop! I lost my favorite ripple stone. It's perfectly ploppy. Could you bring it back?",
            thanks: "PLOP! Perfect! The next puddle I discover is officially named after you.",
            reward: "Puddle Pal", symbol: "drop.fill",
            chat: "If a puddle is tiny, does that make it a pocket ocean? I'm investigating.",
            pet: "Bloopi fans their rosy gills and wiggles their paddle tail.",
            play: "Bloopi practices swimming through the air. Excellent splashing form!")
        case .nibbi: return Story(
            role: "Pocket baker",
            personality: "A strawberry bunny baker with floppy ears, a cookie pocket, and wildly ambitious snack plans.",
            title: "A sprinkle of courage", item: "sugar star",
            request: "My friendship cookies need one last sugar star! Would you find it? You get the first bite. And the second.",
            thanks: "Ta-daaa! A cookie for my favorite helper. I made it extra big because you are extra nice.",
            reward: "Cookie Comrade", symbol: "star.fill",
            chat: "The recipe said a pinch of joy. I added seven. I think we're going to need a bigger bowl.",
            pet: "Nibbi squishes happily and flops both ears. A very pleased little bun.",
            play: "Nibbi starts the cookie-hop dance. One hop per imaginary sprinkle!")
        case .cindlet: return Story(
            role: "Wish warmer",
            personality: "A honey-colored ember fox whose fluffy flame tail keeps small wishes warm.",
            title: "Keep a wish warm", item: "wish cinder",
            request: "A little wish escaped my tail! Could you find its wish cinder? I promised to keep it cozy.",
            thanks: "Safe and warm! I made a wish too. It was to find a friend like you. It worked!",
            reward: "Cozy Guardian", symbol: "flame.fill",
            chat: "My tail is warm like toast. My ideas are also mostly about toast.",
            pet: "Cindlet leans in with a warm little nuzzle and a swishy tail.",
            play: "Cindlet chases their own tail, then acts like that was the plan all along.")
        }
    }
}
