import Foundation

/// Original characters; raw values are the bundled Blender asset names.
enum RealmFriend: String, CaseIterable, Identifiable, Codable {
    case mosskip = "Mosskip", glimlo = "Glimlo", pebblin = "Pebblin"
    case bloopi = "Bloopi", nibbi = "Nibbi", cindlet = "Cindlet"
    case pufflo = "Pufflo", trufflet = "Trufflet", dottli = "Dottli"
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
        case .pufflo: return 0.8
        case .trufflet: return 0.72
        case .dottli: return 1.35
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
            title: "Speak fluent Bloop", item: "ripple stone",
            request: "Bloop! Find my ripple stone, then come back for a puddle concert. I'll teach you the bubble-wiggle-plop song!",
            thanks: "PLOP! Perfect! The next puddle I discover is officially named after you.",
            reward: "Puddle Pal", symbol: "drop.fill",
            chat: "If a puddle is tiny, does that make it a pocket ocean? I'm investigating.",
            pet: "Bloopi fans their rosy gills and wiggles their paddle tail.",
            play: "Bloopi practices swimming through the air. Excellent splashing form!")
        case .nibbi: return Story(
            role: "Pocket baker",
            personality: "A strawberry bunny baker with floppy ears, a cookie pocket, and wildly ambitious snack plans.",
            title: "The impossible snack", item: "sugar star",
            request: "Find my sugar star, then help me invent a cookie! We'll mix three ingredients and taste-test them together.",
            thanks: "Ta-daaa! A cookie for my favorite helper. I made it extra big because you are extra nice.",
            reward: "Cookie Comrade", symbol: "star.fill",
            chat: "The recipe said a pinch of joy. I added seven. I think we're going to need a bigger bowl.",
            pet: "Nibbi squishes happily and flops both ears. A very pleased little bun.",
            play: "Nibbi starts the cookie-hop dance. One hop per imaginary sprinkle!")
        case .cindlet: return Story(
            role: "Wish warmer",
            personality: "A honey-colored ember fox whose fluffy flame tail keeps small wishes warm.",
            title: "Too hot for toast", item: "wish cinder",
            request: "My tiny oven needs its wish cinder! Bring it back, then help me choose just enough ember treats for perfectly cozy toast.",
            thanks: "Safe and warm! I made a wish too. It was to find a friend like you. It worked!",
            reward: "Cozy Guardian", symbol: "flame.fill",
            chat: "My tail is warm like toast. My ideas are also mostly about toast.",
            pet: "Cindlet leans in with a warm little nuzzle and a swishy tail.",
            play: "Cindlet chases their own tail, then acts like that was the plan all along.")
        case .pufflo: return Story(
            role: "Cloud scout",
            personality: "A pillowy sky whale who charts cloud shapes and rings a tiny bell when a friend looks up.",
            title: "A cloud calling", item: "cloud bell",
            request: "Pwooo! My cloud bell drifted away. Could you find it? The little clouds won't know when it's snack time!",
            thanks: "Ding! That's the sound of a perfect cloud day. You're my honorary cloud captain!",
            reward: "Cloud Captain", symbol: "cloud.fill",
            chat: "That cloud looks like a sandwich. That one too. I may be a little hungry.",
            pet: "Pufflo closes their eyes and leans into a pillowy nuzzle. Their flippers flutter like little blankets.",
            play: "Pufflo glides through a pretend cloud tunnel and gives an enormous, very tiny tail swish.")
        case .trufflet: return Story(
            role: "Story keeper",
            personality: "A shy mushroom friend with a spotted cap and a pocket book full of wonderfully silly forest tales.",
            title: "One more little chapter", item: "spore bookmark",
            request: "Um, I lost my spore bookmark. Would you help me find it? We were just getting to the part with the dancing turnip.",
            thanks: "Here it is! I saved you a place in the story. You're the brave friend with the excellent pockets.",
            reward: "Story Sprout", symbol: "book.fill",
            chat: "Once upon a time, a turnip learned to tap dance. I'm still working on the next sentence.",
            pet: "Trufflet ducks under their spotted cap, then peeks out with the happiest little smile.",
            play: "Trufflet performs a shy cap bow and the forest's smallest mushroom shuffle.")
        case .dottli: return Story(
            role: "Daisy florist",
            personality: "A butter-yellow duckling who wears a daisy and delivers bouquets with far too much enthusiasm.",
            title: "A buttonful of sunshine", item: "sun button",
            request: "Peep! My bouquet needs its sun button. Can you bring it back? I picked the friendliest daisy just for you!",
            thanks: "A perfect sunny bouquet! You get the first flower, and all of my very best peeps.",
            reward: "Petal Pal", symbol: "camera.macro",
            chat: "I told a daisy a joke. It didn't laugh, but I think its petals looked happier.",
            pet: "Dottli makes a tiny pleased peep and folds their wings. The daisy gives a little nod.",
            play: "Dottli flaps both wings and tries three very important daisy hops.")
        }
    }
}
