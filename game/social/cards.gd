class_name TableCards
extends RefCounted
## Integer cards: four suits, ranks two through ace. Scores compare numerically.
const SUITS = ["♣", "♦", "♥", "♠"]
const CATEGORIES = ["Carta alta", "Pareja", "Doble pareja", "Trío", "Escalera", "Color", "Full", "Póker", "Escalera de color"]

static func rank(card: int) -> int: return card % 13 + 2

static func label(card: int) -> String:
 var value = rank(card)
 return str({11: "J", 12: "Q", 13: "K", 14: "A"}.get(value, str(value))) + SUITS[card / 13]

static func labels(cards: Array) -> String:
 return "  ".join(cards.map(func(card): return label(int(card))))

static func shuffled(rng: RandomNumberGenerator) -> Array:
 var deck: Array = range(52)
 for i in range(51, 0, -1):
  var j = rng.randi_range(0, i)
  var card = deck[i]
  deck[i] = deck[j]
  deck[j] = card
 return deck

static func blackjack(cards: Array) -> int:
 var total = 0
 var aces = 0
 for card in cards:
  var value = rank(int(card))
  total += 11 if value == 14 else mini(value, 10)
  if value == 14: aces += 1
 while total > 21 and aces > 0:
  total -= 10
  aces -= 1
 return total

static func natural(cards: Array) -> bool:
 return cards.size() == 2 and blackjack(cards) == 21

static func score(cards: Array) -> int:
 if cards.size() < 5: return 0
 var best = 0
 for a in range(cards.size() - 4):
  for b in range(a + 1, cards.size() - 3):
   for c in range(b + 1, cards.size() - 2):
    for d in range(c + 1, cards.size() - 1):
     for e in range(d + 1, cards.size()):
      best = maxi(best, _five([cards[a], cards[b], cards[c], cards[d], cards[e]]))
 return best

static func category(score_value: int) -> String:
 return CATEGORIES[score_value / 759375]

static func _five(cards: Array) -> int:
 var counts: Dictionary = {}
 var flush = true
 for card in cards:
  var r = rank(int(card))
  counts[r] = int(counts.get(r, 0)) + 1
  if int(card) / 13 != int(cards[0]) / 13: flush = false
 var ranks = counts.keys()
 ranks.sort()
 ranks.reverse()
 var straight = 0
 if ranks.size() == 5:
  if ranks[0] - ranks[4] == 4: straight = ranks[0]
  elif ranks == [14, 5, 4, 3, 2]: straight = 5
 var groups = ranks.duplicate()
 groups.sort_custom(func(a, b): return counts[a] > counts[b] if counts[a] != counts[b] else a > b)
 var category_value = 0
 var kickers = ranks
 if flush and straight: category_value = 8; kickers = [straight]
 elif counts[groups[0]] == 4: category_value = 7; kickers = groups
 elif counts[groups[0]] == 3 and counts[groups[1]] == 2: category_value = 6; kickers = groups
 elif flush: category_value = 5
 elif straight: category_value = 4; kickers = [straight]
 elif counts[groups[0]] == 3: category_value = 3; kickers = groups
 elif counts[groups[0]] == 2 and counts[groups[1]] == 2: category_value = 2; kickers = groups
 elif counts[groups[0]] == 2: category_value = 1; kickers = groups
 var result = category_value
 for i in 5: result = result * 15 + (int(kickers[i]) if i < kickers.size() else 0)
 return result
